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
    # natural death, sold-as-breeder, etc. Departs the sow via a movement
    # (sale/slaughter/farm_transfer/death) which closes her last open
    # service as a side-effect. Processed AFTER the event timeline.
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

  @valid_statuses ~w(active open served lactating dry)
  # Legacy exports often carry a terminal DISPOSITION in the status column
  # (the sow has left the herd). These are not reproductive statuses — the
  # importer seeds every sow "active" and reconstructs departures from
  # culls.csv. We therefore tolerate these values (normalised to "active"
  # at commit) but emit a warning, since the status column alone never
  # culls a sow: a matching culls.csv row is what records the departure.
  @legacy_disposition_statuses ~w(culled cull sold slaughtered transferred death dead deceased)
  @valid_service_types ~w(ai natural)
  # services.csv carries only reproductive outcomes. Dispositions
  # (death / cull / sale / …) live in culls.csv and are applied as
  # movements, never as a service result.
  @valid_results ~w(farrowing abortion failed_pregnancy re_service)
  # Reasons accepted in culls.csv — the disposition file. Each row departs
  # the sow via a movement, which closes any open service as a side-effect
  # (death → service result "death", everything else → "removed"):
  #   sold        → sale movement          → status "sold"
  #   slaughtered → slaughter movement     → status "slaughtered"
  #   transferred → farm_transfer movement → status "transferred"
  #   death       → death movement         → status "deceased"
  #   cull / blank / generic → sale movement → status "sold"
  # The on-farm `marked_cull` flag is only ever set by the live action,
  # never by import.
  @valid_cull_reasons ~w(cull slaughtered sold transferred death)
  @valid_house_purposes ~w(breeding gestation farrowing nursery grower finisher quarantine hospital)
  @valid_pen_statuses ~w(active quarantine cleaning retired)

  # Operator-supplied catch-all location for legacy rows with no known
  # pen. The operator adds a `LEGACY,gestation,LEGACY` row to
  # locations.csv; the importer routes pen-less farrowings, pen-less
  # imported sows, and movements to unknown pens here. See
  # `.claude/skills/legacy-csv-import`.
  @fallback_house_code "LEGACY"
  @fallback_pen_code "LEGACY"

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

    # The LEGACY fallback pen must exist (in locations.csv or the DB)
    # whenever a run could orphan a location — sows, farrowings, or
    # movements. Block upfront with one actionable error rather than
    # letting individual rows fail cryptically at commit.
    locations =
      require_fallback_pen(locations, combined_pens, [sows, farrowings, weanings, movements])

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
            # A repeated house_code+pen_code is auto-skipped, not blocked:
            # the first occurrence imports the pen and later ones are
            # no-ops at commit (`Repo.get_by` finds the existing pen).
            [
              %{
                level: :warn,
                kind: :duplicate,
                msg: "#{h}+#{p} duplicate house_code+pen_code in this CSV — skipped"
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

  # Canonical pen-index key. Legacy exports zero-pad codes inconsistently
  # (movements.csv "AB-01" vs locations.csv "AB-1"); leading zeros are
  # stripped from purely-numeric segments so the two match. Matching is
  # case-insensitive. Used everywhere pen keys are built/looked up so the
  # index, movements, farrowing `pen`, and dedup all agree.
  defp location_key(house, pen),
    do: "#{normalize_code_segment(house)}-#{normalize_code_segment(pen)}"

  # A combined "HOUSE-PEN" code (the farrowings.csv `pen` column). Split
  # on the first hyphen; a bare code with no hyphen normalises as-is.
  defp combined_pen_key(code) do
    case String.split(to_string(code), "-", parts: 2) do
      [house, pen] -> location_key(house, pen)
      [single] -> normalize_code_segment(single)
    end
  end

  defp normalize_code_segment(s) do
    s = s |> to_string() |> String.trim() |> String.upcase()

    if s =~ ~r/^\d+$/ do
      case String.trim_leading(s, "0") do
        "" -> "0"
        stripped -> stripped
      end
    else
      s
    end
  end

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
        nil ->
          issues

        s when s in @valid_statuses ->
          issues

        s when s in @legacy_disposition_statuses ->
          [
            %{
              level: :warn,
              kind: :legacy_disposition_status,
              msg:
                "status \"#{s}\" is a disposition, not a reproductive status — " <>
                  "seeding sow \"active\"; record the departure in culls.csv"
            }
            | issues
          ]

        s ->
          [%{level: :err, kind: :bad_status, msg: "status \"#{s}\" not allowed"} | issues]
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
        key = location_key(row["house_code"], row["pen_code"])

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
    |> Map.new(fn p -> {location_key(p.house.code, p.code), p.id} end)
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

    # Any sow this run created who is still pen-less (no movement and no
    # farrowing placed her) is parked in the LEGACY fallback pen so she
    # has a location everywhere. Scoped to `via` — pre-existing sows are
    # never touched.
    place_penless_sows_in_fallback(scope, via, pens)

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

    # Per-house set of normalised pen codes already present (existing DB
    # pens + ones created earlier in this run). Lets a padded row ("01")
    # skip when the unpadded pen ("1") already exists, matching the
    # validation-level dedup and avoiding double-creates.
    seen =
      houses_by_code
      |> Map.new(fn {_k, house} ->
        codes =
          Repo.all(from(p in Pen, where: p.house_id == ^house.id, select: p.code))
          |> Enum.map(&normalize_code_segment/1)
          |> MapSet.new()

        {house.id, codes}
      end)

    {result, _seen} =
      Enum.reduce(rows, {%{ok: 0, failed: 0, errors: []}, seen}, fn row, {acc, seen} ->
        house = Map.fetch!(houses_by_code, String.upcase(row["house_code"]))
        norm = normalize_code_segment(row["pen_code"])
        house_codes = Map.fetch!(seen, house.id)

        if MapSet.member?(house_codes, norm) do
          {run_row(acc, row, fn -> :ok end), seen}
        else
          attrs = %{
            "code" => row["pen_code"],
            "capacity" => parse_int(row["capacity"]) || 0,
            "status" => row["status"] || "active",
            "house_id" => house.id,
            "created_via" => via
          }

          acc = run_row(acc, row, fn -> Locations.create_pen(scope, house, attrs) end)
          {acc, Map.put(seen, house.id, MapSet.put(house_codes, norm))}
        end
      end)

    result
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
    #
    # Status is always seeded "active" regardless of the sows.csv value.
    # The CSV carries each sow's FINAL status (lactating/served/dry/…);
    # replaying it verbatim would let `check_sow_serviceable` reject
    # every historical service against a departed/lactating sow.
    # Instead the event timeline drives status forward (service→served,
    # farrowing→lactating, weaning→dry) and culls.csv applies terminal
    # removals afterwards, so the final status is reconstructed, not
    # imposed up front.
    Enum.reduce(rows, %{ok: 0, failed: 0, errors: []}, fn row, acc ->
      attrs =
        %{
          "tracking_type" => "individual",
          "stage" => "sow",
          "ear_tag" => row["ear_tag"],
          "breed" => row["breed"],
          "dob" => row["dob"],
          "status" => "active",
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
  # participate in the chain. `abortion / failed_pregnancy` aren't
  # inferable from anything else, so we keep the pre-closed historic path.
  # Death and cull are dispositions — they live in culls.csv (applied as
  # movements), never as a service result here.
  defp process_event(scope, %{kind: :service, row: row}, via, _pens) do
    case row["result"] do
      result when result in ["abortion", "failed_pregnancy"] ->
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

    # Validate gestation with the same wide window the importer uses to
    # match the open service (below). Legacy gestation lengths drift a
    # few days off the 114-day ideal; without this the matched service
    # passes the ±14d match but the farrowing fails the narrow ±3d farm
    # validation, orphaning the service.
    opts = [gestation_tolerance: import_gestation_tolerance(scope)]

    sow = Animals.find_by_ear_tag(scope, sow_tag)

    row_pen_id =
      case row["pen"] do
        nil -> nil
        code -> Map.get(pens, combined_pen_key(code))
      end

    # Pen resolution chain: an explicit row pen wins, then the sow's pen
    # at farrowing time, then the LEGACY fallback as last resort. Passed
    # explicitly so the fallback can never override a real current_pen_id.
    pen_id = row_pen_id || (sow && sow.current_pen_id) || fallback_pen_id(pens)

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
        "served_at" => derive_served_at(scope, row["farrowed_at"])
      }
      |> drop_nils()

    case sow do
      %Animal{id: sow_id} ->
        case find_open_service_for_farrowing(scope, sow_id, farrowed_at) do
          %Service{} = service ->
            case Breeding.record_farrowing(scope, service, attrs, opts) do
              {:ok, _} -> :ok
              err -> err
            end

          nil ->
            case Breeding.record_farrowing_with_backfill(
                   scope,
                   {:existing_sow, sow_id},
                   attrs,
                   opts
                 ) do
              {:ok, _} -> :ok
              err -> err
            end
        end

      nil ->
        case Breeding.record_farrowing_with_backfill(
               scope,
               {:new_sow, %{"ear_tag" => sow_tag}},
               attrs,
               opts
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
        "batch_tag" => row["batch_tag"] || Breeding.default_wean_batch_tag(row["weaned_at"]),
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

  # Wider tolerance used only when matching imported farrowing rows to
  # an existing open service. Legacy bookkeeping often records served_at
  # a few days off the conception ideal (heat first observed vs. actual
  # mating). Without this slack, the importer synthesises a backfill
  # service that orphans the real (slightly off-window) open service.
  # 14 days is well under the 21-day estrous cycle, so it can't
  # accidentally match a service from a neighbouring cycle.
  @import_gestation_tolerance_days 14

  # The gestation tolerance the importer applies — both for matching a
  # farrowing to its open service AND for validating that farrowing —
  # so the two never disagree. Never narrower than the farm's setting.
  defp import_gestation_tolerance(%Scope{farm: farm}),
    do: max(Breeding.gestation_tolerance_days(farm), @import_gestation_tolerance_days)

  defp fallback_pen_key, do: location_key(@fallback_house_code, @fallback_pen_code)

  # The id of the LEGACY/LEGACY fallback pen, or nil if absent. The
  # validation gate (`require_fallback_pen/3`) blocks any import that
  # would need it without it, so commit-time lookups expect it present.
  defp fallback_pen_id(pens), do: Map.get(pens, fallback_pen_key())

  # Blocking gate: if any supplied file has rows that could leave an
  # animal/event without a pen, the LEGACY fallback must be resolvable
  # (locations.csv or DB). Otherwise append one actionable error to the
  # locations file so `summary.blocking_errors` stops the commit.
  defp require_fallback_pen(locations, combined_pens, files) do
    needs? = Enum.any?(files, &(&1.rows != []))
    present? = Map.has_key?(combined_pens, fallback_pen_key())

    if needs? and not present? do
      err = %{
        line: 0,
        kind: :missing_fallback_pen,
        msg:
          "legacy import needs a fallback pen: add a " <>
            "\"#{@fallback_house_code},gestation,#{@fallback_pen_code}\" row to locations.csv"
      }

      %{locations | err: locations.err ++ [err]}
    else
      locations
    end
  end

  # Park sows created in THIS run that no movement or farrowing gave a
  # pen into the LEGACY fallback. No-op when the fallback is absent (the
  # validation gate already blocks runs that would need it). Scoped to
  # `via`, so pre-existing pen-less sows are left untouched.
  defp place_penless_sows_in_fallback(scope, via, pens) do
    case fallback_pen_id(pens) do
      nil ->
        :ok

      pen_id ->
        from(a in Animal,
          where:
            a.farm_id == ^scope.farm.id and a.created_via == ^via and
              a.stage == "sow" and is_nil(a.current_pen_id)
        )
        |> Repo.update_all(set: [current_pen_id: pen_id])

        :ok
    end
  end

  # Locates an open (no result, not deleted) service for the sow whose
  # served_at is within the gestation window of farrowed_at. Returns
  # the most recent match or nil.
  defp find_open_service_for_farrowing(_scope, _sow_id, nil), do: nil

  defp find_open_service_for_farrowing(%Scope{farm: farm} = scope, sow_id, %Date{} = farrowed_at) do
    gestation = Breeding.gestation_days(farm)
    tol = import_gestation_tolerance(scope)
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
    reason = row["reason"]

    case Animals.find_by_ear_tag(scope, ear_tag) do
      nil ->
        # Skipping unknown sow is a warning at validation time; here we
        # just record it as a row-level error so the count is accurate.
        {:error, :sow_not_found}

      %Animal{} = sow ->
        Repo.transaction(fn ->
          moved_at = culled_at || Date.to_iso8601(Peggy.FarmClock.today(scope))

          # A still-lactating sow can't depart with nursing piglets, so
          # auto-wean her open litter at the cull date first. The
          # departure movement then flips her status AND closes any open
          # gestation service (death → "death", else "removed").
          with {:ok, sow} <- autowean_open_litter(scope, sow, moved_at, via),
               {:ok, _movement} <-
                 Animals.record_movement(scope, sow, %{
                   "reason" => cull_movement_reason(reason),
                   "moved_at" => moved_at,
                   "notes" => "legacy import: #{reason || "cull"}"
                 }) do
            Repo.reload!(sow)
          else
            {:error, err} -> Repo.rollback(err)
          end
        end)
    end
  end

  # `culls.csv` is the disposition file: every row departs the sow via a
  # movement (which closes any open service as a side-effect). Known
  # reasons map to their movement; a blank or generic reason ("cull",
  # "old age", …) defaults to a sale. `marked_cull` — the on-farm intent
  # flag — is never produced by import, only by the live action.
  defp cull_movement_reason("sold"), do: "sale"
  defp cull_movement_reason("slaughtered"), do: "slaughter"
  defp cull_movement_reason("transferred"), do: "farm_transfer"
  defp cull_movement_reason("death"), do: "death"
  defp cull_movement_reason(_), do: "sale"

  # When the timeline leaves a sow lactating with surviving piglets at
  # cull time, wean the open litter (count = survivors) at the cull date
  # so she can depart — pooled into a per-sow legacy weaner batch. No-op
  # for non-lactating sows or empty litters.
  defp autowean_open_litter(scope, %Animal{status: "lactating"} = sow, weaned_at, via) do
    case Breeding.latest_open_farrowing_for_sow(scope, sow.id) do
      nil ->
        {:ok, sow}

      farrowing ->
        case Breeding.surviving_piglet_count(farrowing) do
          n when n > 0 ->
            attrs = %{
              "weaned_at" => weaned_at,
              "weaned_count" => n,
              "batch_tag" => "LEGACY-WEAN-#{sow.ear_tag}",
              "created_via" => via
            }

            case Breeding.record_weaning(scope, farrowing, attrs) do
              {:ok, _weaning, _batch} -> {:ok, Repo.reload!(sow)}
              {:error, reason} -> {:error, {:autowean, reason}}
            end

          _ ->
            {:ok, sow}
        end
    end
  end

  defp autowean_open_litter(_scope, sow, _weaned_at, _via), do: {:ok, sow}

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
    pen_key = location_key(row["house_code"], row["pen_code"])
    sow_tag = row["ear_tag"]
    # A movement to a pen we don't recognise is re-homed to LEGACY rather
    # than dropped, so the audit trail keeps the move (even if the exact
    # destination is unknown).
    to_pen_id = Map.get(pens, pen_key) || fallback_pen_id(pens)
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

  defp derive_served_at(scope, farrowed_at_str) do
    case parse_date(farrowed_at_str) do
      {:ok, %Date{} = d} ->
        d |> Date.add(-Breeding.gestation_days(scope)) |> Date.to_iso8601()

      _ ->
        nil
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
