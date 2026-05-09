defmodule Peggy.Imports do
  @moduledoc """
  CSV-driven legacy data import for an existing farm.

  Two-phase pipeline:

    1. `parse_and_validate/2` — pure: reads CSVs, normalises rows,
       resolves cross-file references (sow ear-tags, pen codes), and
       returns a per-file `%{ok: [...], warn: [...], err: [...]}` map.
       No DB writes.

    2. `commit/2` — only invoked after the user reviews the report.
       Writes via the existing context functions
       (`Animals.create_animal`, `Breeding.record_service_with_backfill`,
       etc.) inside per-file transactions. Each created row is tagged
       with `created_via: "csv_import:<run_id>"` so a later rollback
       task can find them.

  Designed to feed a 3-step LiveView wizard (upload → review → commit).
  See `PeggyWeb.FarmLive.DataImport`.
  """

  import Ecto.Query

  alias NimbleCSV.RFC4180, as: CSV
  alias Peggy.{Animals, Audit, Breeding, Locations, Repo}
  alias Peggy.Accounts.Scope
  alias Peggy.Animals.{Animal, Movement}
  alias Peggy.Audit.AuditLog
  alias Peggy.Breeding.{Farrowing, Service, Weaning}
  alias Peggy.Locations.{House, Pen}

  @max_rows_per_file 100_000

  # Required + optional columns per CSV. Unknown columns are silently
  # ignored so the user can keep extra metadata without it blocking.
  @schema %{
    locations: %{
      required: ~w(house_code house_purpose pen_code),
      optional: ~w(capacity status notes)
    },
    sows: %{
      required: ~w(ear_tag),
      optional: ~w(breed dob status sire_tag dam_tag legacy_parity rfid notes)
    },
    services: %{
      required: ~w(sow_ear_tag served_at service_type),
      optional: ~w(boar_ear_tag result result_at notes)
    },
    farrowings: %{
      required: ~w(sow_ear_tag farrowed_at born_alive),
      optional: ~w(stillborn mummified total_birth_weight_g pen notes)
    },
    weanings: %{
      required: ~w(sow_ear_tag weaned_at weaned_count),
      optional: ~w(avg_wean_weight_g batch_tag notes)
    },
    # Final-state CSV. Covers any sow no longer in the herd: cull,
    # natural death, sold-as-breeder, etc. Closes the sow's last open
    # service (with a service-side `result` derived from `reason`) and
    # marks her status="culled". Processed AFTER the event timeline.
    culls: %{
      required: ~w(ear_tag culled_at),
      optional: ~w(reason notes)
    },
    # Per-sow chronological pen history. Inserts `pen_transfer` movement
    # rows so the audit trail shows where each sow has been. Doesn't
    # touch `current_pen_id` — sows.csv already set that to the latest
    # pen, and we treat movements.csv as historical record only.
    movements: %{
      required: ~w(ear_tag moved_at house_code pen_code),
      optional: ~w(notes)
    }
  }

  @valid_statuses ~w(active open served lactating dry culled)
  @valid_service_types ~w(ai natural)
  @valid_results ~w(farrowing abortion re_service death cull)
  # Reasons accepted in culls.csv. Each maps to a final sow `status`
  # (per `Peggy.Animals.Animal` taxonomy) and a `Service.result` for
  # the sow's last open service:
  #   cull        → status "culled",      service result "cull"
  #   slaughtered → status "slaughtered", service result "cull"
  #   sold        → status "sold",        service result "cull"
  #   transferred → status "transferred", service result "cull"
  #   death       → status "deceased",    service result "death"
  # Blank reason defaults to "cull".
  @valid_cull_reasons ~w(cull slaughtered sold transferred death)
  @valid_house_purposes ~w(breeding gestation farrowing nursery grower finisher quarantine hospital)
  @valid_pen_statuses ~w(active quarantine cleaning retired)

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Parses + validates the supplied CSV files. Each file argument is a
  path on disk (or `nil` if the user didn't upload that file).

  Returns:

      %{
        sows:       %{rows: [...], ok: [...], warn: [...], err: [...]},
        services:   %{...},
        farrowings: %{...},
        weanings:   %{...},
        summary:    %{sows_imported: n, services_imported: n, ...}
      }

  - `rows` are decoded + normalised maps with a `:line` key.
  - `ok`   are rows that will be imported as-is.
  - `warn` are rows that will be imported but with a soft issue noted
           (missing pen, sow auto-backfilled, etc.).
  - `err`  are rows that block the import.
  """
  def parse_and_validate(%Scope{} = scope, files) when is_map(files) do
    # Pull the existing animal index once so service / farrowing /
    # weaning lookups can resolve sow ear_tags without N+1s.
    existing_sows = existing_sows_index(scope)
    existing_pens = pen_index(scope)

    locations = parse_file(:locations, files[:locations]) |> validate_locations()

    # Combined pen index: existing DB pens + ones declared in
    # locations.csv. sows.csv pen lookups should hit either.
    combined_pens =
      Map.merge(existing_pens, build_pen_index_from_locations(locations.rows))

    sows = parse_file(:sows, files[:sows])
    sow_index = build_sow_index(sows.rows)

    sows = validate_sows(sows)

    # Combined index of "what sow ear tags will exist after sows.csv
    # commits": existing DB rows + freshly imported sows.
    combined_sows = Map.merge(existing_sows, sow_index)

    services = parse_file(:services, files[:services]) |> validate_services(scope, combined_sows)

    farrowings =
      parse_file(:farrowings, files[:farrowings]) |> validate_farrowings(scope, combined_sows)

    weanings = parse_file(:weanings, files[:weanings]) |> validate_weanings(scope, combined_sows)

    culls = parse_file(:culls, files[:culls]) |> validate_culls(combined_sows)

    movements =
      parse_file(:movements, files[:movements])
      |> validate_movements(combined_sows, combined_pens)

    %{
      locations: locations,
      sows: sows,
      services: services,
      farrowings: farrowings,
      weanings: weanings,
      culls: culls,
      movements: movements,
      summary: summarise(locations, sows, services, farrowings, weanings, culls, movements)
    }
  end

  # ── Parsing ────────────────────────────────────────────────────────

  defp parse_file(_kind, nil), do: %{rows: [], ok: [], warn: [], err: []}

  defp parse_file(kind, path) when is_binary(path) do
    case File.exists?(path) do
      false ->
        %{
          rows: [],
          ok: [],
          warn: [],
          err: [%{line: 0, kind: :missing_file, msg: "file not found: #{Path.basename(path)}"}]
        }

      true ->
        do_parse_file(kind, path)
    end
  end

  defp do_parse_file(kind, path) do
    %{required: required, optional: optional} = Map.fetch!(@schema, kind)
    expected = required ++ optional

    case File.read(path) do
      {:error, reason} ->
        %{
          rows: [],
          ok: [],
          warn: [],
          err: [%{line: 0, kind: :read_error, msg: "could not read file: #{inspect(reason)}"}]
        }

      {:ok, raw} ->
        try do
          parsed = CSV.parse_string(raw, skip_headers: false)
          decode_rows(parsed, required, expected)
        rescue
          e ->
            %{
              rows: [],
              ok: [],
              warn: [],
              err: [%{line: 0, kind: :parse_error, msg: Exception.message(e)}]
            }
        end
    end
  end

  defp decode_rows([], _required, _expected),
    do: %{
      rows: [],
      ok: [],
      warn: [],
      err: [%{line: 0, kind: :empty, msg: "CSV is empty (no header row)"}]
    }

  defp decode_rows([header | data_rows], required, expected) do
    headers = Enum.map(header, &normalise_header/1)
    missing = required -- headers

    cond do
      missing != [] ->
        %{
          rows: [],
          ok: [],
          warn: [],
          err: [
            %{
              line: 1,
              kind: :missing_columns,
              msg: "missing required columns: #{Enum.join(missing, ", ")}"
            }
          ]
        }

      length(data_rows) > @max_rows_per_file ->
        %{
          rows: [],
          ok: [],
          warn: [],
          err: [
            %{
              line: 1,
              kind: :too_many_rows,
              msg: "file has #{length(data_rows)} rows; limit is #{@max_rows_per_file} per import"
            }
          ]
        }

      true ->
        rows =
          data_rows
          |> Enum.with_index(2)
          |> Enum.map(fn {cells, line_no} ->
            row_from_cells(headers, cells, expected, line_no)
          end)

        %{rows: rows, ok: [], warn: [], err: []}
    end
  end

  defp row_from_cells(headers, cells, expected, line_no) do
    map =
      Enum.zip(headers, cells)
      |> Enum.into(%{})
      |> Map.take(expected)
      |> Map.new(fn {k, v} -> {k, normalise_cell(v)} end)

    Map.put(map, :line, line_no)
  end

  defp normalise_header(h), do: h |> to_string() |> String.trim() |> String.downcase()

  defp normalise_cell(nil), do: nil

  defp normalise_cell(v) when is_binary(v) do
    case String.trim(v) do
      "" -> nil
      s -> s
    end
  end

  defp normalise_cell(v), do: v

  # ── Locations validation ──────────────────────────────────────────

  defp validate_locations(%{err: errs} = state) when errs != [], do: state

  defp validate_locations(%{rows: rows} = state) do
    {ok, warn, err, _seen} =
      Enum.reduce(rows, {[], [], [], MapSet.new()}, fn row, {o, w, e, seen} ->
        {status, msgs} = check_location_row(row, seen)

        seen =
          case {row["house_code"], row["pen_code"]} do
            {h, p} when is_binary(h) and is_binary(p) -> MapSet.put(seen, location_key(h, p))
            _ -> seen
          end

        case status do
          :ok -> {[row | o], w, e, seen}
          :warn -> {o, [row_with_msgs(row, msgs) | w], e, seen}
          :err -> {o, w, [row_with_msgs(row, msgs) | e], seen}
        end
      end)

    %{state | ok: Enum.reverse(ok), warn: Enum.reverse(warn), err: Enum.reverse(err)}
  end

  defp check_location_row(row, seen) do
    issues = []

    issues =
      if is_nil(row["house_code"]),
        do: [%{level: :err, kind: :missing, msg: "house_code is required"} | issues],
        else: issues

    issues =
      if is_nil(row["pen_code"]),
        do: [%{level: :err, kind: :missing, msg: "pen_code is required"} | issues],
        else: issues

    issues =
      case row["house_purpose"] do
        nil ->
          [%{level: :err, kind: :missing, msg: "house_purpose is required"} | issues]

        s when s in @valid_house_purposes ->
          issues

        s ->
          [
            %{
              level: :err,
              kind: :bad_value,
              msg:
                "house_purpose \"#{s}\" not allowed " <>
                  "(#{Enum.join(@valid_house_purposes, "|")})"
            }
            | issues
          ]
      end

    issues =
      case row["status"] do
        nil ->
          issues

        s when s in @valid_pen_statuses ->
          issues

        s ->
          [
            %{
              level: :err,
              kind: :bad_value,
              msg: "pen status \"#{s}\" not allowed (#{Enum.join(@valid_pen_statuses, "|")})"
            }
            | issues
          ]
      end

    issues =
      case row["capacity"] do
        nil ->
          issues

        v ->
          case Integer.parse(to_string(v)) do
            {n, ""} when n >= 0 ->
              issues

            _ ->
              [
                %{level: :err, kind: :bad_int, msg: "capacity must be a non-negative integer"}
                | issues
              ]
          end
      end

    issues =
      case {row["house_code"], row["pen_code"]} do
        {h, p} when is_binary(h) and is_binary(p) ->
          if MapSet.member?(seen, location_key(h, p)) do
            [
              %{
                level: :err,
                kind: :duplicate,
                msg: "#{h}+#{p} duplicate house_code+pen_code in this CSV"
              }
              | issues
            ]
          else
            issues
          end

        _ ->
          issues
      end

    classify(issues)
  end

  defp location_key(house, pen),
    do: String.upcase("#{String.trim(house)}-#{String.trim(pen)}")

  defp build_pen_index_from_locations(rows) do
    rows
    |> Enum.filter(&(&1["house_code"] && &1["pen_code"]))
    |> Map.new(fn r -> {location_key(r["house_code"], r["pen_code"]), :pending} end)
  end

  # ── Sow validation ─────────────────────────────────────────────────

  defp validate_sows(%{err: errs} = state) when errs != [], do: state

  defp validate_sows(%{rows: rows} = state) do
    {ok, warn, err, _seen} =
      Enum.reduce(rows, {[], [], [], MapSet.new()}, fn row, {ok_acc, warn_acc, err_acc, seen} ->
        {row_status, msgs} = check_sow_row(row, seen)
        seen = if row["ear_tag"], do: MapSet.put(seen, row["ear_tag"]), else: seen

        case row_status do
          :ok -> {[row | ok_acc], warn_acc, err_acc, seen}
          :warn -> {ok_acc, [row_with_msgs(row, msgs) | warn_acc], err_acc, seen}
          :err -> {ok_acc, warn_acc, [row_with_msgs(row, msgs) | err_acc], seen}
        end
      end)

    %{state | ok: Enum.reverse(ok), warn: Enum.reverse(warn), err: Enum.reverse(err)}
  end

  defp check_sow_row(row, seen) do
    issues = []

    issues =
      if is_nil(row["ear_tag"]),
        do: [%{level: :err, kind: :missing, msg: "ear_tag is required"} | issues],
        else: issues

    issues =
      if row["ear_tag"] in seen,
        do: [
          %{level: :err, kind: :duplicate, msg: "duplicate ear_tag in this CSV"} | issues
        ],
        else: issues

    issues =
      case parse_date(row["dob"]) do
        {:ok, _} -> issues
        :empty -> issues
        :invalid -> [%{level: :err, kind: :bad_date, msg: "dob must be YYYY-MM-DD"} | issues]
      end

    issues =
      case row["status"] do
        nil -> issues
        s when s in @valid_statuses -> issues
        s -> [%{level: :err, kind: :bad_status, msg: "status \"#{s}\" not allowed"} | issues]
      end

    issues =
      case row["legacy_parity"] do
        nil ->
          issues

        s ->
          case Integer.parse(to_string(s)) do
            {n, ""} when n >= 0 ->
              issues

            _ ->
              [
                %{
                  level: :err,
                  kind: :bad_int,
                  msg: "legacy_parity must be a non-negative integer"
                }
                | issues
              ]
          end
      end

    classify(issues)
  end

  # ── Service validation ────────────────────────────────────────────

  defp validate_services(%{err: errs} = state, _scope, _sows) when errs != [], do: state

  defp validate_services(%{rows: rows} = state, _scope, sow_index) do
    {ok, warn, err} =
      Enum.reduce(rows, {[], [], []}, fn row, {o, w, e} ->
        {status, msgs} = check_service_row(row, sow_index)

        case status do
          :ok -> {[row | o], w, e}
          :warn -> {o, [row_with_msgs(row, msgs) | w], e}
          :err -> {o, w, [row_with_msgs(row, msgs) | e]}
        end
      end)

    %{state | ok: Enum.reverse(ok), warn: Enum.reverse(warn), err: Enum.reverse(err)}
  end

  defp check_service_row(row, sow_index) do
    issues = []

    issues =
      if is_nil(row["sow_ear_tag"]),
        do: [%{level: :err, kind: :missing, msg: "sow_ear_tag is required"} | issues],
        else: issues

    issues =
      case parse_date(row["served_at"]) do
        {:ok, _} ->
          issues

        :empty ->
          [%{level: :err, kind: :missing, msg: "served_at is required"} | issues]

        :invalid ->
          [%{level: :err, kind: :bad_date, msg: "served_at must be YYYY-MM-DD"} | issues]
      end

    issues =
      case row["service_type"] do
        nil ->
          [%{level: :err, kind: :missing, msg: "service_type is required"} | issues]

        s when s in @valid_service_types ->
          issues

        s ->
          [
            %{
              level: :err,
              kind: :bad_value,
              msg: "service_type \"#{s}\" not allowed (ai|natural)"
            }
            | issues
          ]
      end

    issues =
      case row["result"] do
        nil -> issues
        s when s in @valid_results -> issues
        s -> [%{level: :err, kind: :bad_value, msg: "result \"#{s}\" not allowed"} | issues]
      end

    issues =
      case parse_date(row["result_at"]) do
        {:ok, _} ->
          issues

        :empty ->
          issues

        :invalid ->
          [%{level: :err, kind: :bad_date, msg: "result_at must be YYYY-MM-DD"} | issues]
      end

    issues =
      if row["sow_ear_tag"] && not Map.has_key?(sow_index, row["sow_ear_tag"]),
        do: [
          %{
            level: :warn,
            kind: :unknown_sow,
            msg: "sow \"#{row["sow_ear_tag"]}\" not in sows.csv or DB — will be auto-registered"
          }
          | issues
        ],
        else: issues

    classify(issues)
  end

  # ── Farrowing validation ──────────────────────────────────────────

  defp validate_farrowings(%{err: errs} = state, _scope, _sows) when errs != [], do: state

  defp validate_farrowings(%{rows: rows} = state, _scope, sow_index) do
    {ok, warn, err} =
      Enum.reduce(rows, {[], [], []}, fn row, {o, w, e} ->
        {status, msgs} = check_farrowing_row(row, sow_index)

        case status do
          :ok -> {[row | o], w, e}
          :warn -> {o, [row_with_msgs(row, msgs) | w], e}
          :err -> {o, w, [row_with_msgs(row, msgs) | e]}
        end
      end)

    %{state | ok: Enum.reverse(ok), warn: Enum.reverse(warn), err: Enum.reverse(err)}
  end

  defp check_farrowing_row(row, sow_index) do
    issues = []

    issues =
      if is_nil(row["sow_ear_tag"]),
        do: [%{level: :err, kind: :missing, msg: "sow_ear_tag is required"} | issues],
        else: issues

    issues =
      case parse_date(row["farrowed_at"]) do
        {:ok, _} ->
          issues

        :empty ->
          [%{level: :err, kind: :missing, msg: "farrowed_at is required"} | issues]

        :invalid ->
          [%{level: :err, kind: :bad_date, msg: "farrowed_at must be YYYY-MM-DD"} | issues]
      end

    issues =
      Enum.reduce(~w(born_alive stillborn mummified total_birth_weight_g), issues, fn col, acc ->
        case row[col] do
          nil ->
            acc

          v ->
            case Integer.parse(to_string(v)) do
              {n, ""} when n >= 0 ->
                acc

              _ ->
                [
                  %{level: :err, kind: :bad_int, msg: "#{col} must be a non-negative integer"}
                  | acc
                ]
            end
        end
      end)

    issues =
      if row["sow_ear_tag"] && not Map.has_key?(sow_index, row["sow_ear_tag"]),
        do: [
          %{
            level: :warn,
            kind: :unknown_sow,
            msg: "sow \"#{row["sow_ear_tag"]}\" not in sows.csv or DB — will be auto-registered"
          }
          | issues
        ],
        else: issues

    classify(issues)
  end

  # ── Weaning validation ────────────────────────────────────────────

  defp validate_weanings(%{err: errs} = state, _scope, _sows) when errs != [], do: state

  defp validate_weanings(%{rows: rows} = state, _scope, sow_index) do
    {ok, warn, err} =
      Enum.reduce(rows, {[], [], []}, fn row, {o, w, e} ->
        {status, msgs} = check_weaning_row(row, sow_index)

        case status do
          :ok -> {[row | o], w, e}
          :warn -> {o, [row_with_msgs(row, msgs) | w], e}
          :err -> {o, w, [row_with_msgs(row, msgs) | e]}
        end
      end)

    %{state | ok: Enum.reverse(ok), warn: Enum.reverse(warn), err: Enum.reverse(err)}
  end

  defp check_weaning_row(row, sow_index) do
    issues = []

    issues =
      if is_nil(row["sow_ear_tag"]),
        do: [%{level: :err, kind: :missing, msg: "sow_ear_tag is required"} | issues],
        else: issues

    issues =
      case parse_date(row["weaned_at"]) do
        {:ok, _} ->
          issues

        :empty ->
          [%{level: :err, kind: :missing, msg: "weaned_at is required"} | issues]

        :invalid ->
          [%{level: :err, kind: :bad_date, msg: "weaned_at must be YYYY-MM-DD"} | issues]
      end

    issues =
      case row["weaned_count"] do
        nil ->
          [%{level: :err, kind: :missing, msg: "weaned_count is required"} | issues]

        v ->
          case Integer.parse(to_string(v)) do
            {n, ""} when n > 0 ->
              issues

            {0, ""} ->
              [
                %{
                  level: :warn,
                  kind: :empty_wean,
                  msg: "weaned_count is 0"
                }
                | issues
              ]

            {n, ""} when n < 0 ->
              [
                %{
                  level: :err,
                  kind: :bad_int,
                  msg: "weaned_count must be >= 0 (negative not allowed)"
                }
                | issues
              ]

            _ ->
              [
                %{level: :err, kind: :bad_int, msg: "weaned_count must be a non-negative integer"}
                | issues
              ]
          end
      end

    issues =
      if row["sow_ear_tag"] && not Map.has_key?(sow_index, row["sow_ear_tag"]),
        do: [
          %{
            level: :warn,
            kind: :unknown_sow,
            msg: "sow \"#{row["sow_ear_tag"]}\" not in sows.csv or DB"
          }
          | issues
        ],
        else: issues

    classify(issues)
  end

  # ── Culls validation ──────────────────────────────────────────────

  defp validate_culls(%{err: errs} = state, _sows) when errs != [], do: state

  defp validate_culls(%{rows: rows} = state, sow_index) do
    {ok, warn, err, _seen} =
      Enum.reduce(rows, {[], [], [], MapSet.new()}, fn row, {o, w, e, seen} ->
        {status, msgs} = check_cull_row(row, sow_index, seen)
        seen = if row["ear_tag"], do: MapSet.put(seen, row["ear_tag"]), else: seen

        case status do
          :ok -> {[row | o], w, e, seen}
          :warn -> {o, [row_with_msgs(row, msgs) | w], e, seen}
          :err -> {o, w, [row_with_msgs(row, msgs) | e], seen}
        end
      end)

    %{state | ok: Enum.reverse(ok), warn: Enum.reverse(warn), err: Enum.reverse(err)}
  end

  defp check_cull_row(row, sow_index, seen) do
    issues = []

    issues =
      if is_nil(row["ear_tag"]),
        do: [%{level: :err, kind: :missing, msg: "ear_tag is required"} | issues],
        else: issues

    issues =
      if row["ear_tag"] in seen,
        do: [%{level: :err, kind: :duplicate, msg: "duplicate ear_tag in culls.csv"} | issues],
        else: issues

    issues =
      case parse_date(row["culled_at"]) do
        {:ok, _} ->
          issues

        :empty ->
          [%{level: :err, kind: :missing, msg: "culled_at is required"} | issues]

        :invalid ->
          [%{level: :err, kind: :bad_date, msg: "culled_at must be YYYY-MM-DD"} | issues]
      end

    issues =
      case row["reason"] do
        nil ->
          issues

        s when s in @valid_cull_reasons ->
          issues

        s ->
          [
            %{
              level: :err,
              kind: :bad_value,
              msg: "reason \"#{s}\" not allowed (#{Enum.join(@valid_cull_reasons, "|")})"
            }
            | issues
          ]
      end

    issues =
      if row["ear_tag"] && not Map.has_key?(sow_index, row["ear_tag"]),
        do: [
          %{
            level: :warn,
            kind: :unknown_sow,
            msg:
              "sow \"#{row["ear_tag"]}\" not in sows.csv or DB — removal will be skipped at commit"
          }
          | issues
        ],
        else: issues

    classify(issues)
  end

  # ── Movements validation ──────────────────────────────────────────

  defp validate_movements(%{err: errs} = state, _sows, _pens) when errs != [], do: state

  defp validate_movements(%{rows: rows} = state, sow_index, pen_index) do
    {ok, warn, err} =
      Enum.reduce(rows, {[], [], []}, fn row, {o, w, e} ->
        {status, msgs} = check_movement_row(row, sow_index, pen_index)

        case status do
          :ok -> {[row | o], w, e}
          :warn -> {o, [row_with_msgs(row, msgs) | w], e}
          :err -> {o, w, [row_with_msgs(row, msgs) | e]}
        end
      end)

    %{state | ok: Enum.reverse(ok), warn: Enum.reverse(warn), err: Enum.reverse(err)}
  end

  defp check_movement_row(row, sow_index, pen_index) do
    issues = []

    issues =
      if is_nil(row["ear_tag"]),
        do: [%{level: :err, kind: :missing, msg: "ear_tag is required"} | issues],
        else: issues

    issues =
      case parse_date(row["moved_at"]) do
        {:ok, _} -> issues
        :empty -> [%{level: :err, kind: :missing, msg: "moved_at is required"} | issues]
        :invalid -> [%{level: :err, kind: :bad_date, msg: "moved_at must be YYYY-MM-DD"} | issues]
      end

    issues =
      if is_nil(row["house_code"]),
        do: [%{level: :err, kind: :missing, msg: "house_code is required"} | issues],
        else: issues

    issues =
      if is_nil(row["pen_code"]),
        do: [%{level: :err, kind: :missing, msg: "pen_code is required"} | issues],
        else: issues

    issues =
      if row["ear_tag"] && not Map.has_key?(sow_index, row["ear_tag"]),
        do: [
          %{
            level: :warn,
            kind: :unknown_sow,
            msg:
              "sow \"#{row["ear_tag"]}\" not in sows.csv or DB — movement will be skipped at commit"
          }
          | issues
        ],
        else: issues

    issues =
      if row["house_code"] && row["pen_code"] do
        key = String.upcase("#{row["house_code"]}-#{row["pen_code"]}")

        if Map.has_key?(pen_index, key),
          do: issues,
          else: [
            %{
              level: :warn,
              kind: :unknown_pen,
              msg:
                "pen \"#{row["house_code"]}-#{row["pen_code"]}\" not found — movement will be skipped at commit"
            }
            | issues
          ]
      else
        issues
      end

    classify(issues)
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp existing_sows_index(scope) do
    Animals.list_animals(scope, stage: "sow", status: nil)
    |> Enum.filter(&is_binary(&1.ear_tag))
    |> Map.new(fn a -> {a.ear_tag, a.id} end)
  end

  defp build_sow_index(rows) do
    rows
    |> Enum.filter(& &1["ear_tag"])
    |> Map.new(fn r -> {r["ear_tag"], :pending} end)
  end

  defp pen_index(scope) do
    Locations.list_all_pens(scope)
    |> Map.new(fn p -> {String.upcase("#{p.house.code}-#{p.code}"), p.id} end)
  end

  defp parse_date(nil), do: :empty
  defp parse_date(""), do: :empty
  defp parse_date(%Date{}), do: {:ok, :date}

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> {:ok, d}
      _ -> :invalid
    end
  end

  defp parse_date(_), do: :invalid

  # Roll up per-row issues into a single status + the messages.
  defp classify([]), do: {:ok, []}

  defp classify(issues) do
    cond do
      Enum.any?(issues, &(&1.level == :err)) -> {:err, issues}
      true -> {:warn, issues}
    end
  end

  defp row_with_msgs(row, msgs), do: Map.put(row, :issues, msgs)

  defp summarise(locations, sows, services, farrowings, weanings, culls, movements) do
    %{
      locations_in: length(locations.rows),
      locations_importable: length(locations.ok) + length(locations.warn),
      locations_errors: length(locations.err),
      sows_in: length(sows.rows),
      sows_importable: length(sows.ok) + length(sows.warn),
      sows_errors: length(sows.err),
      services_in: length(services.rows),
      services_importable: length(services.ok) + length(services.warn),
      services_errors: length(services.err),
      farrowings_in: length(farrowings.rows),
      farrowings_importable: length(farrowings.ok) + length(farrowings.warn),
      farrowings_errors: length(farrowings.err),
      weanings_in: length(weanings.rows),
      weanings_importable: length(weanings.ok) + length(weanings.warn),
      weanings_errors: length(weanings.err),
      culls_in: length(culls.rows),
      culls_importable: length(culls.ok) + length(culls.warn),
      culls_errors: length(culls.err),
      movements_in: length(movements.rows),
      movements_importable: length(movements.ok) + length(movements.warn),
      movements_errors: length(movements.err),
      blocking_errors:
        length(locations.err) +
          length(sows.err) + length(services.err) +
          length(farrowings.err) + length(weanings.err) +
          length(culls.err) + length(movements.err)
    }
  end

  # ── Commit ────────────────────────────────────────────────────────

  @doc """
  Commits a previously-validated import. Refuses to run if any file
  has blocking errors — the caller should re-run `parse_and_validate`
  and clear the report first.

  Returns:

      {:ok, %{
         run_id: "csv_import:1693420800-abc",
         locations: %{ok: n, failed: n, errors: [...]},
         sows:      %{...},
         services:  %{...},
         farrowings: %{...},
         weanings:  %{...}
       }}

  Each file is committed in its own transaction. A row failure inside
  a file rolls back that file but leaves earlier files intact, with
  the failure reason recorded in the per-file `errors` list.
  """
  def commit(%Scope{} = scope, %{summary: %{blocking_errors: 0}} = report) do
    run_id = generate_run_id()
    via = "csv_import:#{run_id}"

    locations = commit_locations(scope, report.locations, via)
    sows = commit_sows(scope, report.sows, via)

    # Services / farrowings / weanings / movements commit as a single
    # per-sow chronological timeline. Movements are interleaved so that
    # by the time a farrowing event runs, the sow's current_pen_id
    # reflects the pen she was in on that date (Farrowing.pen_id falls
    # back to sow.current_pen_id when the row has no explicit pen).
    events = build_event_timeline(report)
    pens = pen_index(scope)
    {services, farrowings, weanings, movements} = commit_events(scope, events, via, pens)

    # Culls run AFTER the event timeline so any open service the
    # timeline left behind (e.g. a sow whose last legacy event was a
    # service that nothing closed) gets closed with the cull result.
    culls = commit_culls(scope, report[:culls] || empty_file_state(), via)

    Audit.log_now!(scope, "import.run",
      entity_type: :import,
      entity_id: run_id,
      changes: %{
        "run_id" => run_id,
        "locations_ok" => locations.ok,
        "sows_ok" => sows.ok,
        "services_ok" => services.ok,
        "farrowings_ok" => farrowings.ok,
        "weanings_ok" => weanings.ok,
        "culls_ok" => culls.ok,
        "movements_ok" => movements.ok
      }
    )

    {:ok,
     %{
       run_id: run_id,
       locations: locations,
       sows: sows,
       services: services,
       farrowings: farrowings,
       weanings: weanings,
       culls: culls,
       movements: movements
     }}
  end

  def commit(_scope, %{summary: %{blocking_errors: n}}) when n > 0,
    do: {:error, :blocking_errors}

  defp empty_file_state, do: %{rows: [], ok: [], warn: [], err: []}

  # ── Locations commit ──────────────────────────────────────────────

  defp commit_locations(_scope, %{ok: [], warn: []}, _via),
    do: %{ok: 0, failed: 0, errors: []}

  defp commit_locations(scope, file, via) do
    rows = file.ok ++ file.warn

    houses_by_code =
      rows
      |> Enum.group_by(&String.upcase(&1["house_code"]))
      |> Enum.map(fn {key, group_rows} ->
        first = hd(group_rows)
        {key, ensure_house!(scope, first["house_code"], first["house_purpose"])}
      end)
      |> Map.new()

    Enum.reduce(rows, %{ok: 0, failed: 0, errors: []}, fn row, acc ->
      house = Map.fetch!(houses_by_code, String.upcase(row["house_code"]))

      run_row(acc, row, fn ->
        case Repo.get_by(Pen, house_id: house.id, code: row["pen_code"]) do
          %Pen{} ->
            :ok

          nil ->
            attrs = %{
              "code" => row["pen_code"],
              "capacity" => parse_int(row["capacity"]) || 0,
              "status" => row["status"] || "active",
              "house_id" => house.id,
              "created_via" => via
            }

            Locations.create_pen(scope, house, attrs)
        end
      end)
    end)
  end

  defp ensure_house!(scope, code, purpose) do
    farm_id = scope.farm.id

    case Repo.get_by(House, farm_id: farm_id, code: code) do
      nil ->
        {:ok, house} = Locations.create_house(scope, %{"code" => code, "purpose" => purpose})
        house

      house ->
        house
    end
  end

  # ── Sows commit ───────────────────────────────────────────────────

  defp commit_sows(_scope, %{ok: [], warn: []}, _via),
    do: %{ok: 0, failed: 0, errors: []}

  defp commit_sows(scope, file, via) do
    rows = file.ok ++ file.warn

    # Sows are inserted with no pen — movements.csv (if provided) sets
    # current_pen_id via the chain of pen_transfer movements processed
    # later. Sows with no movement history land pen-less; assign through
    # the UI.
    Enum.reduce(rows, %{ok: 0, failed: 0, errors: []}, fn row, acc ->
      attrs =
        %{
          "tracking_type" => "individual",
          "stage" => "sow",
          "ear_tag" => row["ear_tag"],
          "breed" => row["breed"],
          "dob" => row["dob"],
          "status" => row["status"] || "active",
          "rfid" => row["rfid"],
          "notes" => row["notes"],
          "legacy_parity" => parse_int(row["legacy_parity"]) || 0,
          "created_via" => via
        }
        |> drop_nils()

      run_row(acc, row, fn ->
        Animals.create_animal(scope, attrs, seed_initial_movement: false)
      end)
    end)
  end

  # ── Event timeline commit ─────────────────────────────────────────

  # Builds a flat list of {kind, file, line, sow_ear_tag, date, row}
  # events, ordered per sow by date ascending. Service < Farrowing <
  # Weaning is the tie-break for events sharing the same date so that
  # an open service is closed by its farrowing on the same day before
  # any weaning lookup runs.
  defp build_event_timeline(report) do
    services_events =
      Enum.map(report.services.ok ++ report.services.warn, fn r ->
        %{
          kind: :service,
          file: :services,
          line: r[:line],
          sow_ear_tag: r["sow_ear_tag"],
          date: parse_date_or_nil(r["served_at"]),
          row: r
        }
      end)

    farrowing_events =
      Enum.map(report.farrowings.ok ++ report.farrowings.warn, fn r ->
        %{
          kind: :farrowing,
          file: :farrowings,
          line: r[:line],
          sow_ear_tag: r["sow_ear_tag"],
          date: parse_date_or_nil(r["farrowed_at"]),
          row: r
        }
      end)

    weaning_events =
      Enum.map(report.weanings.ok ++ report.weanings.warn, fn r ->
        %{
          kind: :weaning,
          file: :weanings,
          line: r[:line],
          sow_ear_tag: r["sow_ear_tag"],
          date: parse_date_or_nil(r["weaned_at"]),
          row: r
        }
      end)

    movement_events =
      case report do
        %{movements: %{ok: ok, warn: warn}} ->
          Enum.map(ok ++ warn, fn r ->
            %{
              kind: :movement,
              file: :movements,
              line: r[:line],
              sow_ear_tag: r["ear_tag"],
              date: parse_date_or_nil(r["moved_at"]),
              row: r
            }
          end)

        _ ->
          []
      end

    (services_events ++ farrowing_events ++ weaning_events ++ movement_events)
    |> Enum.group_by(& &1.sow_ear_tag)
    |> Enum.flat_map(fn {_tag, events} ->
      Enum.sort_by(events, fn e -> {date_sort_key(e.date), kind_rank(e.kind), e.line} end)
    end)
  end

  # Same-day tie-break: a movement on date D applies BEFORE the
  # service/farrowing/weaning of that day so the breeding event reads
  # the correct pen.
  defp kind_rank(:movement), do: -1
  defp kind_rank(:service), do: 0
  defp kind_rank(:farrowing), do: 1
  defp kind_rank(:weaning), do: 2

  # Sort key: rows with no parseable date sink to the end so events
  # with valid dates are processed first and the bad ones surface as
  # per-row errors at insert time.
  defp date_sort_key(%Date{} = d), do: {0, Date.to_erl(d)}
  defp date_sort_key(_), do: {1, nil}

  defp parse_date_or_nil(s) do
    case parse_date(s) do
      {:ok, %Date{} = d} -> d
      _ -> nil
    end
  end

  defp commit_events(scope, events, via, pens) do
    init = %{
      services: %{ok: 0, failed: 0, errors: []},
      farrowings: %{ok: 0, failed: 0, errors: []},
      weanings: %{ok: 0, failed: 0, errors: []},
      movements: %{ok: 0, failed: 0, errors: []}
    }

    final =
      Enum.reduce(events, init, fn event, acc ->
        file_acc = Map.fetch!(acc, event.file)
        updated = run_row(file_acc, event.row, fn -> process_event(scope, event, via, pens) end)
        Map.put(acc, event.file, updated)
      end)

    {
      %{final.services | errors: Enum.reverse(final.services.errors)},
      %{final.farrowings | errors: Enum.reverse(final.farrowings.errors)},
      %{final.weanings | errors: Enum.reverse(final.weanings.errors)},
      %{final.movements | errors: Enum.reverse(final.movements.errors)}
    }
  end

  # `result` in services.csv is treated as a *hint* for `farrowing` and
  # `re_service` — both outcomes are inferable from the natural chain
  # (the matching farrowings.csv row closes a `farrowing` service; the
  # auto-resolver in `record_service` closes a prior service as
  # `re_service` when the next service for the same sow is inserted).
  # We drop those values and route the row as an open service so it can
  # participate in the chain. `abortion / death / cull` aren't inferable
  # from anything else, so we keep the pre-closed historic path.
  defp process_event(scope, %{kind: :service, row: row}, via, _pens) do
    case row["result"] do
      result when result in ["abortion", "death", "cull"] ->
        commit_closed_service(scope, row, via)

      _ ->
        commit_open_service(scope, row, via)
    end
  end

  defp process_event(scope, %{kind: :farrowing, row: row}, via, pens) do
    do_commit_farrowing(scope, row, via, pens)
  end

  defp process_event(scope, %{kind: :weaning, row: row}, via, pens) do
    do_commit_weaning(scope, row, via, pens)
  end

  defp process_event(scope, %{kind: :movement, row: row}, _via, pens) do
    do_commit_movement(scope, row, pens)
  end

  # Open service: route through `record_service_with_backfill` so the
  # auto-resolver handles within-7d collapse and outside-window auto-
  # close-as-re_service. Sow auto-creation also lives in that path.
  defp commit_open_service(scope, row, via) do
    attrs =
      %{
        "sow_ear_tag" => row["sow_ear_tag"],
        "service_type" => row["service_type"],
        "served_at" => row["served_at"],
        "boar_id" => lookup_boar_id(scope, row["boar_ear_tag"]),
        "notes" => row["notes"],
        "inferred" => true,
        "created_via" => via
      }
      |> drop_nils()

    case Breeding.record_service_with_backfill(scope, attrs) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  # Pre-resolved historic service for outcomes that nothing else in the
  # import chain closes — `abortion`, `death`, `cull`. Insert directly
  # via `Service.changeset` so the auto-resolver doesn't try to
  # collapse / re-classify it. The sow's status isn't promoted —
  # whatever sows.csv says (or the existing DB row) stands.
  #
  # Legacy `result_at` columns are sometimes blank or carry a value
  # that pre-dates `served_at` (the legacy system used the column for
  # different bookkeeping). Either case fails the schema's
  # `validate_result_date`, so we fall back to `served_at` whenever the
  # supplied `result_at` is missing or earlier than `served_at`.
  defp commit_closed_service(scope, row, via) do
    with {:ok, sow} <- ensure_sow_for_service(scope, row, via) do
      attrs =
        %{
          "farm_id" => scope.farm.id,
          "sow_id" => sow.id,
          "service_type" => row["service_type"],
          "served_at" => row["served_at"],
          "boar_id" => lookup_boar_id(scope, row["boar_ear_tag"]),
          "notes" => row["notes"],
          "result" => row["result"],
          "result_at" => coerce_result_at(row["result_at"], row["served_at"]),
          "inferred" => true,
          "created_via" => via
        }
        |> drop_nils()

      case Service.changeset(%Service{}, attrs) |> Repo.insert() do
        {:ok, _service} -> :ok
        {:error, cs} -> {:error, cs}
      end
    end
  end

  defp coerce_result_at(result_at, served_at) do
    with {:ok, %Date{} = r} <- parse_date(result_at),
         {:ok, %Date{} = s} <- parse_date(served_at),
         true <- Date.compare(r, s) != :lt do
      result_at
    else
      _ -> served_at
    end
  end

  defp ensure_sow_for_service(scope, row, via) do
    case Animals.find_by_ear_tag(scope, row["sow_ear_tag"]) do
      %Animal{} = sow ->
        {:ok, sow}

      nil ->
        attrs =
          %{
            "tracking_type" => "individual",
            "stage" => "sow",
            "status" => "active",
            "ear_tag" => row["sow_ear_tag"],
            "inferred" => true,
            "needs_review" => true,
            "created_via" => via
          }
          |> drop_nils()

        Animals.create_animal(scope, attrs, seed_initial_movement: false)
    end
  end

  # Farrowing: if the sow exists and has an open service inside the
  # gestation window, attach to it (which closes the service with
  # result="farrowing"). Otherwise fall back to the back-fill cascade
  # which inserts an inferred service first.
  defp do_commit_farrowing(scope, row, via, pens) do
    sow_tag = row["sow_ear_tag"]
    farrowed_at = parse_date_or_nil(row["farrowed_at"])

    pen_id =
      case row["pen"] do
        nil -> nil
        code -> Map.get(pens, String.upcase(code))
      end

    attrs =
      %{
        "farrowed_at" => row["farrowed_at"],
        "born_alive" => parse_int(row["born_alive"]),
        "stillborn" => parse_int(row["stillborn"]) || 0,
        "mummified" => parse_int(row["mummified"]) || 0,
        "total_birth_weight_g" => parse_int(row["total_birth_weight_g"]),
        "pen_id" => pen_id,
        "notes" => row["notes"],
        "created_via" => via,
        # served_at is only consumed by the back-fill cascade. When we
        # match an existing open service, `record_farrowing` ignores it.
        "served_at" => derive_served_at(row["farrowed_at"])
      }
      |> drop_nils()

    case Animals.find_by_ear_tag(scope, sow_tag) do
      %Animal{id: sow_id} ->
        case find_open_service_for_farrowing(scope, sow_id, farrowed_at) do
          %Service{} = service ->
            case Breeding.record_farrowing(scope, service, attrs) do
              {:ok, _} -> :ok
              err -> err
            end

          nil ->
            case Breeding.record_farrowing_with_backfill(scope, {:existing_sow, sow_id}, attrs) do
              {:ok, _} -> :ok
              err -> err
            end
        end

      nil ->
        case Breeding.record_farrowing_with_backfill(
               scope,
               {:new_sow, %{"ear_tag" => sow_tag}},
               attrs
             ) do
          {:ok, _} -> :ok
          err -> err
        end
    end
  end

  # Weaning: if the sow exists and has an open farrowing (no live
  # weaning row yet), attach to it. Otherwise cascade.
  defp do_commit_weaning(scope, row, via, _pens) do
    sow_tag = row["sow_ear_tag"]

    attrs =
      %{
        "weaned_at" => row["weaned_at"],
        "weaned_count" => parse_int(row["weaned_count"]),
        "avg_wean_weight_g" => parse_int(row["avg_wean_weight_g"]),
        "batch_tag" => row["batch_tag"] || "W#{row["weaned_at"]}",
        "notes" => row["notes"],
        "created_via" => via
      }
      |> drop_nils()

    case Animals.find_by_ear_tag(scope, sow_tag) do
      %Animal{id: sow_id} ->
        case Breeding.latest_open_farrowing_for_sow(scope, sow_id) do
          %Farrowing{} = farrowing ->
            case Breeding.record_weaning(scope, farrowing, attrs) do
              {:ok, _, _} -> :ok
              err -> err
            end

          nil ->
            case Breeding.record_weaning_with_backfill(scope, {:existing_sow, sow_id}, attrs) do
              {:ok, _, _} -> :ok
              err -> err
            end
        end

      nil ->
        case Breeding.record_weaning_with_backfill(
               scope,
               {:new_sow, %{"ear_tag" => sow_tag}},
               attrs
             ) do
          {:ok, _, _} -> :ok
          err -> err
        end
    end
  end

  # Locates an open (no result, not deleted) service for the sow whose
  # served_at is within the gestation window of farrowed_at. Returns
  # the most recent match or nil.
  defp find_open_service_for_farrowing(_scope, _sow_id, nil), do: nil

  defp find_open_service_for_farrowing(%Scope{farm: farm}, sow_id, %Date{} = farrowed_at) do
    gestation = Breeding.gestation_days(farm)
    tol = Breeding.gestation_tolerance_days(farm)
    earliest = Date.add(farrowed_at, -(gestation + tol))
    latest = Date.add(farrowed_at, -(gestation - tol))

    Repo.one(
      from(s in Service,
        where:
          s.farm_id == ^farm.id and
            s.sow_id == ^sow_id and
            is_nil(s.result) and
            is_nil(s.deleted_at) and
            s.served_at >= ^earliest and
            s.served_at <= ^latest,
        order_by: [desc: s.served_at, desc: s.id],
        limit: 1
      )
    )
  end

  # ── Culls commit ──────────────────────────────────────────────────

  defp commit_culls(_scope, %{ok: [], warn: []}, _via),
    do: %{ok: 0, failed: 0, errors: []}

  defp commit_culls(scope, file, via) do
    rows = file.ok ++ file.warn

    Enum.reduce(rows, %{ok: 0, failed: 0, errors: []}, fn row, acc ->
      run_row(acc, row, fn -> do_commit_cull(scope, row, via) end)
    end)
    |> Map.update!(:errors, &Enum.reverse/1)
  end

  defp do_commit_cull(scope, row, via) do
    ear_tag = row["ear_tag"]
    culled_at = row["culled_at"]
    reason = row["reason"] || "cull"

    case Animals.find_by_ear_tag(scope, ear_tag) do
      nil ->
        # Skipping unknown sow is a warning at validation time; here we
        # just record it as a row-level error so the count is accurate.
        {:error, :sow_not_found}

      %Animal{status: prev_status} = sow ->
        Repo.transaction(fn ->
          with {:ok, _service} <- close_open_service_for_cull(scope, sow, reason, culled_at),
               {:ok, updated} <- depart_sow(scope, sow, reason, culled_at, via) do
            Audit.log_now!(scope, "animal.removed",
              entity_type: :animal,
              entity_id: updated.id,
              changes: %{
                "ear_tag" => updated.ear_tag,
                "reason" => reason,
                "culled_at" => culled_at,
                "previous_status" => prev_status,
                "new_status" => updated.status
              }
            )

            updated
          else
            {:error, err} -> Repo.rollback(err)
          end
        end)
    end
  end

  # Departure path:
  #   - reasons that map to a movement-system departure reason (sold,
  #     slaughtered, transferred, death) → record a movement so the sow
  #     has a proper audit row showing she left the farm. Status flips
  #     automatically as part of the movement.
  #   - reason "cull" → no movement (she's marked for cull, hasn't yet
  #     departed; final disposition will produce the actual movement).
  #     Just flip status → "culled" so she drops out of working lists.
  defp depart_sow(scope, %Animal{} = sow, reason, culled_at, _via) do
    case cull_movement_reason(reason) do
      nil ->
        mark_sow_departed(sow, reason)

      movement_reason ->
        attrs = %{
          "reason" => movement_reason,
          "moved_at" => culled_at || Date.to_iso8601(Peggy.FarmClock.today(scope)),
          "notes" => "legacy import: #{reason}"
        }

        case Animals.record_movement(scope, sow, attrs) do
          {:ok, _movement} ->
            # Reload to reflect the status/current_pen_id update from
            # the movement. record_movement returns the movement, not
            # the updated animal.
            {:ok, Repo.reload!(sow)}

          {:error, %Ecto.Changeset{} = cs} ->
            {:error, {:departure_movement, cs}}

          {:error, reason} ->
            {:error, {:departure_movement, reason}}
        end
    end
  end

  defp cull_movement_reason("sold"), do: "sale"
  defp cull_movement_reason("slaughtered"), do: "slaughter"
  defp cull_movement_reason("transferred"), do: "farm_transfer"
  defp cull_movement_reason("death"), do: "death"
  defp cull_movement_reason(_), do: nil

  # Closes the sow's most recent open service (if any) with a result
  # derived from the cull reason. No-op when the sow has no open
  # service — `{:ok, nil}` lets the with-chain continue.
  defp close_open_service_for_cull(
         %Scope{farm: farm} = scope,
         %Animal{id: sow_id},
         reason,
         culled_at
       ) do
    open =
      Repo.one(
        from(s in Service,
          where:
            s.farm_id == ^farm.id and
              s.sow_id == ^sow_id and
              is_nil(s.result) and
              is_nil(s.deleted_at),
          order_by: [desc: s.served_at, desc: s.id],
          limit: 1
        )
      )

    case open do
      nil ->
        {:ok, nil}

      %Service{served_at: served_at} = service ->
        result_at =
          case parse_date(culled_at) do
            {:ok, %Date{} = d} ->
              if Date.compare(d, served_at) == :lt, do: served_at, else: culled_at

            _ ->
              served_at
          end

        attrs = %{"result" => cull_service_result(reason), "result_at" => result_at}

        case service |> Service.close_changeset(attrs) |> Repo.update() do
          {:ok, closed} ->
            Audit.log_now!(scope, "service.closed",
              entity_type: :service,
              entity_id: closed.id,
              changes: %{"result" => closed.result, "result_at" => to_string(closed.result_at)}
            )

            {:ok, closed}

          {:error, cs} ->
            {:error, {:service_close, cs}}
        end
    end
  end

  defp mark_sow_departed(%Animal{} = sow, reason) do
    new_status = cull_sow_status(reason)

    if sow.status == new_status do
      {:ok, sow}
    else
      sow |> Ecto.Changeset.change(%{status: new_status}) |> Repo.update()
    end
  end

  defp cull_service_result("death"), do: "death"
  defp cull_service_result(_), do: "cull"

  defp cull_sow_status("death"), do: "deceased"
  defp cull_sow_status("sold"), do: "sold"
  defp cull_sow_status("slaughtered"), do: "slaughtered"
  defp cull_sow_status("transferred"), do: "transferred"
  defp cull_sow_status(_), do: "culled"

  # ── Movement event commit ─────────────────────────────────────────
  #
  # Each row inserts one `Movement` and updates the sow's
  # `current_pen_id`. Because rows are processed inside the per-sow
  # chronological event timeline (movements ranked before
  # services/farrowings/weanings on the same date), the sow's
  # `current_pen_id` accurately reflects her pen at every breeding
  # event. The very first move for a sow is `placement`
  # (`from_pen_id = nil`); subsequent ones are `pen_transfer` with
  # `from_pen_id = sow.current_pen_id`.

  defp do_commit_movement(scope, row, pens) do
    pen_key = String.upcase("#{row["house_code"]}-#{row["pen_code"]}")
    sow_tag = row["ear_tag"]
    to_pen_id = Map.get(pens, pen_key)
    sow = sow_tag && Animals.find_by_ear_tag(scope, sow_tag)

    cond do
      is_nil(sow) ->
        {:error, :sow_not_found}

      is_nil(to_pen_id) ->
        {:error, {:pen_not_found, pen_key}}

      true ->
        from_pen_id = sow.current_pen_id

        attrs = %{
          "farm_id" => scope.farm.id,
          "animal_id" => sow.id,
          "reason" => if(is_nil(from_pen_id), do: "placement", else: "pen_transfer"),
          "quantity" => 1,
          "moved_at" => row["moved_at"],
          "from_pen_id" => from_pen_id,
          "to_pen_id" => to_pen_id,
          "notes" => row["notes"]
        }

        Repo.transaction(fn ->
          with {:ok, mv} <- %Movement{} |> Movement.changeset(attrs) |> Repo.insert(),
               {:ok, _sow} <-
                 sow
                 |> Ecto.Changeset.change(%{current_pen_id: to_pen_id})
                 |> Repo.update() do
            mv
          else
            {:error, cs} -> Repo.rollback(cs)
          end
        end)
    end
  end

  # ── Commit helpers ───────────────────────────────────────────────

  # Runs one row's commit body in isolation: any raise (e.g. an
  # unexpected `Repo.insert!` failure) is captured as a per-row error
  # rather than poisoning the surrounding loop. Each call already opens
  # its own inner transaction in the underlying context module.
  defp run_row(acc, row, fun) do
    case fun.() do
      {:ok, _} -> %{acc | ok: acc.ok + 1}
      {:ok, _, _} -> %{acc | ok: acc.ok + 1}
      :ok -> %{acc | ok: acc.ok + 1}
      {:error, reason} -> row_failed(acc, row, humanize_error(reason))
      other -> row_failed(acc, row, "unexpected: #{inspect(other)}")
    end
  rescue
    e -> row_failed(acc, row, Exception.message(e))
  end

  defp row_failed(acc, row, reason) do
    %{
      acc
      | failed: acc.failed + 1,
        errors: [%{line: row[:line], reason: reason} | acc.errors]
    }
  end

  defp generate_run_id do
    "#{System.system_time(:second)}-#{:crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)}"
  end

  defp lookup_boar_id(scope, tag) when is_binary(tag) do
    case Animals.find_by_ear_tag(scope, tag) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp lookup_boar_id(_scope, _), do: nil

  defp drop_nils(map),
    do: Map.reject(map, fn {_k, v} -> is_nil(v) end)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp derive_served_at(farrowed_at_str) do
    case parse_date(farrowed_at_str) do
      {:ok, %Date{} = d} -> Date.add(d, -114) |> Date.to_iso8601()
      _ -> nil
    end
  end

  defp format_changeset(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {f, {m, _}} -> "#{f} #{m}" end)
    |> Enum.join(", ")
  end

  defp format_changeset(other), do: inspect(other)

  defp humanize_error(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp humanize_error(%Ecto.Changeset{} = cs), do: format_changeset(cs)
  defp humanize_error({tag, %Ecto.Changeset{} = cs}), do: "#{tag}: #{format_changeset(cs)}"
  defp humanize_error(other), do: inspect(other)

  # ── Rollback ──────────────────────────────────────────────────────

  @doc """
  Lists past import runs for the farm, newest first. Each entry is a
  map with `:run_id`, `:inserted_at`, `:actor_email`, and the per-file
  counts pulled from the `import.run` audit row.
  """
  def list_runs(%Scope{farm: farm}) do
    rolled_back =
      AuditLog
      |> where([a], a.farm_id == ^farm.id and a.action == "import.rollback")
      |> select([a], a.entity_id)

    AuditLog
    |> where([a], a.farm_id == ^farm.id and a.action == "import.run")
    |> where([a], a.entity_id not in subquery(rolled_back))
    |> order_by([a], desc: a.inserted_at, desc: a.id)
    |> preload(:actor_user)
    |> Repo.all()
    |> Enum.map(fn audit ->
      %{
        run_id: audit.entity_id,
        inserted_at: audit.inserted_at,
        actor_email: audit.actor_user && audit.actor_user.email,
        counts: %{
          locations: audit.changes["locations_ok"] || 0,
          sows: audit.changes["sows_ok"] || 0,
          services: audit.changes["services_ok"] || 0,
          farrowings: audit.changes["farrowings_ok"] || 0,
          weanings: audit.changes["weanings_ok"] || 0,
          movements: audit.changes["movements_ok"] || 0
        }
      }
    end)
  end

  @doc """
  Deletes every row tagged `created_via: "csv_import:<run_id>"` for
  this farm, in dependency-safe order (weanings → farrowings →
  services → animals). Houses and pens aren't tagged on insert (their
  schemas don't carry `created_via`), so location rows stay; surface
  that in the UI rather than silently leaving orphan pens.

  Returns:

      {:ok, %{
        weanings:   deleted_count,
        farrowings: deleted_count,
        services:   deleted_count,
        animals:    deleted_count
      }}

  Or `{:error, reason}` if a delete fails (typically because the row
  has post-import dependencies — e.g. a farrowing recorded by hand
  against an imported sow blocks the sow from being deleted). On
  failure the whole rollback rolls back; nothing is partially undone.
  """
  def rollback(%Scope{farm: farm} = scope, run_id) when is_binary(run_id) do
    via = "csv_import:#{run_id}"

    Repo.transaction(
      fn ->
        try do
          # Animals tagged with this run. Anything attached to one of these
          # sows (services, farrowings, weanings) belongs to the import even
          # if Breeding's backfill paths tagged it `farrowing_backfill` /
          # `weaning_backfill` / `back_fill_from_service` instead.
          animal_ids =
            Repo.all(
              from a in Animal,
                where: a.farm_id == ^farm.id and a.created_via == ^via,
                select: a.id
            )

          weanings = delete_weanings_for_rollback(farm.id, via, animal_ids)
          farrowings = delete_farrowings_for_rollback(farm.id, via, animal_ids)
          services = delete_services_for_rollback(farm.id, via, animal_ids)
          # Movements: deleted by animal_id since the schema doesn't carry
          # `created_via`. Any movement attached to one of the imported
          # sows is part of the import (legacy history).
          movements = delete_movements_for_rollback(farm.id, animal_ids)
          animals = delete_tagged(Animal, farm.id, via)

          Audit.log_now!(scope, "import.rollback",
            entity_type: :import,
            entity_id: run_id,
            changes: %{
              "run_id" => run_id,
              "weanings" => weanings,
              "farrowings" => farrowings,
              "services" => services,
              "movements" => movements,
              "animals" => animals
            }
          )

          %{
            weanings: weanings,
            farrowings: farrowings,
            services: services,
            movements: movements,
            animals: animals
          }
        rescue
          e in Postgrex.Error ->
            require Logger

            Logger.error("""
            Import rollback FK violation for run #{run_id}:
              #{e.postgres.message}
              #{e.postgres[:detail] || ""}
              constraint: #{e.postgres[:constraint] || "?"} on table #{e.postgres[:table] || "?"}
            """)

            Repo.rollback({:fk_violation, e.postgres.message})

          e ->
            Repo.rollback(Exception.message(e))
        end
      end,
      timeout: :infinity
    )
  end

  defp delete_tagged(schema, farm_id, via) do
    {n, _} =
      from(r in schema, where: r.farm_id == ^farm_id and r.created_via == ^via)
      |> Repo.delete_all()

    n
  end

  # Weanings: tagged with this run, OR linked to a farrowing whose sow
  # is one of the imported animals. The farrowing-id path covers
  # weanings auto-created via `weaning_backfill`.
  defp delete_weanings_for_rollback(farm_id, via, animal_ids) do
    farrowing_ids =
      from(f in Farrowing,
        where: f.farm_id == ^farm_id and f.sow_id in ^animal_ids,
        select: f.id
      )
      |> Repo.all()

    {n, _} =
      from(w in Weaning,
        where:
          w.farm_id == ^farm_id and
            (w.created_via == ^via or w.farrowing_id in ^farrowing_ids)
      )
      |> Repo.delete_all()

    n
  end

  # Farrowings: tagged with this run, OR whose sow is one of the
  # imported animals (covers `farrowing_backfill`-tagged rows).
  defp delete_farrowings_for_rollback(farm_id, via, animal_ids) do
    {n, _} =
      from(f in Farrowing,
        where:
          f.farm_id == ^farm_id and
            (f.created_via == ^via or f.sow_id in ^animal_ids)
      )
      |> Repo.delete_all()

    n
  end

  # Services: tagged with this run, OR whose sow is one of the imported
  # animals. Covers `farrowing_backfill` and `back_fill_from_service`.
  # `boar_id` is intentionally not in the predicate — the import doesn't
  # create boars, so any boar referenced here was pre-existing.
  defp delete_services_for_rollback(farm_id, via, animal_ids) do
    {n, _} =
      from(s in Service,
        where:
          s.farm_id == ^farm_id and
            (s.created_via == ^via or s.sow_id in ^animal_ids)
      )
      |> Repo.delete_all()

    n
  end

  # Movements: schema has no `created_via`, so we scope strictly by
  # animal_id — every movement attached to an imported sow is part of
  # the run's legacy history.
  defp delete_movements_for_rollback(farm_id, animal_ids) do
    {n, _} =
      from(m in Movement,
        where: m.farm_id == ^farm_id and m.animal_id in ^animal_ids
      )
      |> Repo.delete_all()

    n
  end
end
