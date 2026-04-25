# Legacy import — migrates active_sows_parity.csv from a prior swine
# management system into Peggy.
#
#   mix run priv/repo/legacy_import.exs <path-to-csv>
#
# Creates farm "legacy" with one sow row per (HERD_ID, EAR_TAG) plus the
# full breeding history (services + farrowings + weanings) reconstructed
# from per-parity rows. Pen codes are split into house/pen via the
# convention "<everything-up-to-and-including-last-letter><digits>".
#
# Idempotent: aborts if farm "legacy" already exists.
#   mix ecto.reset && mix run priv/repo/legacy_import.exs <csv>

alias Peggy.{Accounts, Farms, Repo}
alias Peggy.Animals.Animal
alias Peggy.Locations.{House, Pen}
alias Peggy.Breeding.{Service, Farrowing, Weaning}
alias Peggy.Accounts.Scope

require Logger
import Ecto.Query

# ── Helpers ───────────────────────────────────────────────────────────
defmodule LegacyImport do
  @moduledoc false

  # Schema-imposed caps. Real legacy data sometimes exceeds these
  # (rare 21+ live-born, weaned-counts >15) — we cap to keep inserts
  # valid and flag the sow with `needs_review=true`.
  @max_litter 20
  @max_weaned 15

  @columns ~w(
    HERD_ID EAR_TAG NAME BIRTH_DT ENTRY_DT STATUS STATUS_DT CUR_LOCATION
    PARITY PARITY_LABEL PARITY_BEGIN_DT PARITY_END_DT FST_SERVICE_DT
    CONCEPT_DT N_SERVICES BIRTHING_DT LIVEBORN MALELIVEBORN STILLBORN
    MUMMIES ABORTIONS BIRTHWEIGHT BIRTH_LOCATION BIRTHING_PROBLEM INDUCED
    NURSEON NURSEOFF WEAN1_DT WEAN1_NUM LWEAN_DT TOTAL_WEANED
    LITTERS_WEANED SUM_WEAN_WEIGHT LACTATION_LEN WEAN_FST_SERV OUTFARM
    BIRTHING_COMMENT
  )

  def parse_csv(path) do
    [header_line | rows] =
      path
      |> File.stream!()
      |> Stream.map(&String.trim_trailing/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.to_list()

    actual = parse_line(header_line)

    if actual != @columns do
      raise "CSV header mismatch.\nExpected: #{inspect(@columns)}\nGot: #{inspect(actual)}"
    end

    Enum.map(rows, fn line ->
      values = parse_line(line)
      Enum.zip(@columns, values) |> Map.new()
    end)
  end

  # No embedded commas inside quoted fields in this dataset (verified),
  # so plain comma split + quote strip is safe.
  defp parse_line(line) do
    line
    |> String.split(",")
    |> Enum.map(&strip_quotes/1)
    |> Enum.map(fn "" -> nil; v -> v end)
  end

  defp strip_quotes(<<?", rest::binary>>) do
    case String.last(rest) do
      "\"" -> String.slice(rest, 0, byte_size(rest) - 1)
      _ -> rest
    end
  end

  defp strip_quotes(s), do: s

  # "AB39" → {"AB", "39"}, "1G84" → {"1G", "84"}, "16I109" → {"16I", "109"}
  # "D"    → {"D", "1"}    (rare; flag for review later)
  # "4191" → :error        (no letter at all)
  def split_pen_code(code) when is_binary(code) do
    code = String.upcase(code)

    case Regex.run(~r/^(.*[A-Z])(\d+)$/, code) do
      [_, house, pen] ->
        {:ok, house, pen}

      nil ->
        if Regex.match?(~r/^[A-Z]+$/, code) do
          {:ok, code, "1"}
        else
          :error
        end
    end
  end

  def split_pen_code(_), do: :error

  def parse_int(nil), do: nil
  def parse_int(""), do: nil

  def parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  def parse_int(_), do: nil

  def parse_date(nil), do: nil
  def parse_date(""), do: nil

  def parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  def parse_date(_), do: nil

  def cap_litter(n) when is_integer(n) and n >= 0, do: min(n, @max_litter)
  def cap_litter(_), do: 0

  def cap_weaned(n) when is_integer(n) and n >= 0, do: min(n, @max_weaned)
  def cap_weaned(_), do: 0

  def overflow?(rows) do
    Enum.any?(rows, fn r ->
      (parse_int(r["LIVEBORN"]) || 0) > @max_litter or
        (parse_int(r["STILLBORN"]) || 0) > @max_litter or
        (parse_int(r["MUMMIES"]) || 0) > @max_litter or
        (parse_int(r["TOTAL_WEANED"]) || 0) > @max_weaned
    end)
  end

  # S → served, L → lactating, W → dry, N → active.
  def map_status("S"), do: "served"
  def map_status("L"), do: "lactating"
  def map_status("W"), do: "dry"
  def map_status("N"), do: "active"
  def map_status(_), do: "active"

  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end

defmodule LegacyImport.History do
  @moduledoc false
  alias Peggy.Repo
  alias Peggy.Breeding.{Service, Farrowing, Weaning}

  # Inserts every closed cycle (parity ≥ 1), the matching weaning when
  # the cycle has been weaned, and an open service for sows currently
  # in `served` status. Returns `{services, farrowings, weanings}`.
  def insert(animal, parity_rows, status, farm_id, resolve_pen, now) do
    historic = Enum.filter(parity_rows, &((LegacyImport.parse_int(&1["PARITY"]) || 0) >= 1))
    latest = List.last(parity_rows)

    {svc, far, wean} =
      Enum.reduce(historic, {0, 0, 0}, fn row, {sc, fc, wc} ->
        latest? = row == latest

        case insert_closed_cycle(animal, row, farm_id, resolve_pen, now) do
          {:ok, _svc_id, far_id} ->
            wean? =
              if latest? and status == "lactating" do
                false
              else
                insert_weaning(far_id, row, farm_id, now)
              end

            {sc + 1, fc + 1, wc + if(wean?, do: 1, else: 0)}

          :skip ->
            {sc, fc, wc}
        end
      end)

    open_svc =
      if status == "served" do
        served_at = LegacyImport.parse_date(latest["FST_SERVICE_DT"])

        if served_at do
          Repo.insert!(%Service{
            farm_id: farm_id,
            sow_id: animal.id,
            service_type: "ai",
            served_at: served_at,
            inferred: true,
            created_via: "legacy_import",
            inserted_at: now,
            updated_at: now
          })

          1
        else
          0
        end
      else
        0
      end

    %{services: svc + open_svc, farrowings: far, weanings: wean}
  end

  defp insert_closed_cycle(animal, row, farm_id, resolve_pen, now) do
    farrowed_at = LegacyImport.parse_date(row["BIRTHING_DT"])

    served_at =
      LegacyImport.parse_date(row["CONCEPT_DT"]) || farrowed_at

    pen_id = resolve_pen.(row["BIRTH_LOCATION"]) || animal.current_pen_id

    cond do
      is_nil(farrowed_at) ->
        :skip

      is_nil(pen_id) ->
        :skip

      true ->
        svc =
          Repo.insert!(%Service{
            farm_id: farm_id,
            sow_id: animal.id,
            service_type: "ai",
            served_at: served_at,
            result: "farrowing",
            result_at: farrowed_at,
            inferred: true,
            created_via: "legacy_import",
            inserted_at: now,
            updated_at: now
          })

        far =
          Repo.insert!(%Farrowing{
            farm_id: farm_id,
            sow_id: animal.id,
            service_id: svc.id,
            pen_id: pen_id,
            farrowed_at: farrowed_at,
            born_alive: LegacyImport.cap_litter(LegacyImport.parse_int(row["LIVEBORN"]) || 0),
            stillborn: LegacyImport.cap_litter(LegacyImport.parse_int(row["STILLBORN"]) || 0),
            mummified: LegacyImport.cap_litter(LegacyImport.parse_int(row["MUMMIES"]) || 0),
            inferred: true,
            created_via: "legacy_import",
            inserted_at: now,
            updated_at: now
          })

        {:ok, svc.id, far.id}
    end
  end

  defp insert_weaning(far_id, row, farm_id, now) do
    weaned_at = LegacyImport.parse_date(row["LWEAN_DT"])
    weaned_count = LegacyImport.cap_weaned(LegacyImport.parse_int(row["TOTAL_WEANED"]) || 0)

    if weaned_at do
      avg_weight_g =
        case {LegacyImport.parse_int(row["SUM_WEAN_WEIGHT"]), weaned_count} do
          {nil, _} -> nil
          {_, 0} -> nil
          {sum_kg, n} -> div(sum_kg * 1000, n)
        end

      Repo.insert!(%Weaning{
        farm_id: farm_id,
        farrowing_id: far_id,
        weaned_at: weaned_at,
        weaned_count: weaned_count,
        avg_wean_weight_g: avg_weight_g,
        inferred: true,
        created_via: "legacy_import",
        inserted_at: now,
        updated_at: now
      })

      true
    else
      false
    end
  end
end

# ── Args ──────────────────────────────────────────────────────────────
csv_path =
  case System.argv() do
    [path | _] ->
      path

    [] ->
      Logger.error("Usage: mix run priv/repo/legacy_import.exs <path-to-csv>")
      System.halt(1)
  end

unless File.exists?(csv_path) do
  Logger.error("CSV not found: #{csv_path}")
  System.halt(1)
end

farm_slug = "legacy"
owner_email = "legacy@peggy.local"

if Farms.get_farm_by_slug(farm_slug) do
  Logger.info("Farm '#{farm_slug}' already exists; aborting. Run `mix ecto.reset` to re-import.")
  System.halt(0)
end

# ── User + Farm ───────────────────────────────────────────────────────
Logger.info("Creating user + farm '#{farm_slug}'…")

user =
  Accounts.get_user_by_email(owner_email) ||
    (
      {:ok, u} = Accounts.register_user(%{email: owner_email})
      u
    )

{:ok, farm} =
  Farms.create_farm(user, %{
    name: "Legacy Farm",
    slug: farm_slug,
    timezone: "Asia/Kuala_Lumpur",
    unit_system: "metric"
  })

membership = Farms.get_membership(user, farm)
_scope = Scope.put_farm(Scope.for_user(user), farm, membership)

# ── Parse CSV ─────────────────────────────────────────────────────────
Logger.info("Parsing #{csv_path}…")
all_rows = LegacyImport.parse_csv(csv_path)
Logger.info("  #{length(all_rows)} parity rows loaded.")

# ── Build pen catalog ────────────────────────────────────────────────
Logger.info("Building pen catalog…")

pen_codes =
  all_rows
  |> Enum.flat_map(fn r -> [r["CUR_LOCATION"], r["BIRTH_LOCATION"]] end)
  |> Enum.reject(&is_nil/1)
  |> Enum.uniq()

{house_to_pens, unparseable} =
  Enum.reduce(pen_codes, {%{}, []}, fn code, {acc, bad} ->
    case LegacyImport.split_pen_code(code) do
      {:ok, house, pen} ->
        {Map.update(acc, house, MapSet.new([pen]), &MapSet.put(&1, pen)), bad}

      :error ->
        {acc, [code | bad]}
    end
  end)

if unparseable != [] do
  Logger.warning("  #{length(unparseable)} unparseable pen codes (skipped): #{inspect(Enum.take(unparseable, 10))}")
end

now = LegacyImport.now()

Logger.info("Inserting #{map_size(house_to_pens)} houses…")

houses_rows =
  for {house_code, _} <- house_to_pens do
    %{
      farm_id: farm.id,
      code: house_code,
      purpose: "gestation",
      inserted_at: now,
      updated_at: now
    }
  end

{_, _} = Repo.insert_all(House, houses_rows)

house_id_by_code =
  from(h in House, where: h.farm_id == ^farm.id, select: {h.code, h.id})
  |> Repo.all()
  |> Map.new()

Logger.info("Inserting pens…")

pen_rows =
  for {house_code, pens} <- house_to_pens,
      pen_no <- MapSet.to_list(pens) do
    %{
      farm_id: farm.id,
      house_id: Map.fetch!(house_id_by_code, house_code),
      code: pen_no,
      capacity: 0,
      status: "active",
      inserted_at: now,
      updated_at: now
    }
  end

pen_rows
|> Enum.chunk_every(1000)
|> Enum.each(&Repo.insert_all(Pen, &1))

Logger.info("  inserted #{length(pen_rows)} pens.")

pen_lookup =
  Repo.all(
    from p in Pen,
      where: p.farm_id == ^farm.id,
      select: {p.house_id, p.code, p.id}
  )
  |> Map.new(fn {hid, code, id} -> {{hid, code}, id} end)

resolve_pen = fn
  nil ->
    nil

  code ->
    case LegacyImport.split_pen_code(code) do
      {:ok, house_code, pen_no} ->
        case Map.get(house_id_by_code, house_code) do
          nil -> nil
          hid -> Map.get(pen_lookup, {hid, pen_no})
        end

      :error ->
        nil
    end
end

# ── Group rows by sow ─────────────────────────────────────────────────
Logger.info("Grouping rows by sow…")

sows_grouped =
  all_rows
  |> Enum.group_by(fn r -> r["HERD_ID"] end)
  |> Map.values()
  |> Enum.map(fn rows ->
    Enum.sort_by(rows, &(LegacyImport.parse_int(&1["PARITY"]) || 0))
  end)

Logger.info("  #{length(sows_grouped)} unique sows.")

# ── Insert sows + breeding history ────────────────────────────────────
Logger.info("Importing sows + breeding history…")

stats = %{sows: 0, services: 0, farrowings: 0, weanings: 0, skipped: 0, failed: 0}

stats =
  sows_grouped
  |> Enum.with_index()
  |> Enum.reduce(stats, fn {parity_rows, idx}, acc ->
    if rem(idx, 200) == 0 and idx > 0,
      do: Logger.info("  #{idx}/#{length(sows_grouped)} sows…")

    latest = List.last(parity_rows)
    ear_tag = latest["EAR_TAG"]

    cond do
      is_nil(ear_tag) or ear_tag == "" ->
        %{acc | skipped: acc.skipped + 1}

      true ->
        max_parity = LegacyImport.parse_int(latest["PARITY"]) || 0
        status = LegacyImport.map_status(latest["STATUS"])
        current_pen_id = resolve_pen.(latest["CUR_LOCATION"])
        needs_review = LegacyImport.overflow?(parity_rows) or is_nil(current_pen_id)

        animal_attrs = %{
          farm_id: farm.id,
          tracking_type: "individual",
          ear_tag: ear_tag,
          stage: "sow",
          status: status,
          dob: LegacyImport.parse_date(latest["BIRTH_DT"]),
          legacy_parity: max_parity,
          current_pen_id: current_pen_id,
          inferred: true,
          needs_review: needs_review,
          created_via: "legacy_import"
        }

        try do
          result =
            Repo.transaction(fn ->
              case Animal.changeset(%Animal{}, animal_attrs) |> Repo.insert() do
                {:ok, animal} ->
                  LegacyImport.History.insert(
                    animal,
                    parity_rows,
                    status,
                    farm.id,
                    resolve_pen,
                    now
                  )

                {:error, cs} ->
                  Repo.rollback({:animal, cs})
              end
            end)

          case result do
            {:ok, %{services: s, farrowings: f, weanings: w}} ->
              %{
                acc
                | sows: acc.sows + 1,
                  services: acc.services + s,
                  farrowings: acc.farrowings + f,
                  weanings: acc.weanings + w
              }

            {:error, reason} ->
              Logger.warning("  sow #{ear_tag} failed: #{inspect(reason)}")
              %{acc | failed: acc.failed + 1}
          end
        rescue
          e ->
            Logger.warning("  sow #{ear_tag} crashed: #{Exception.message(e)}")
            %{acc | failed: acc.failed + 1}
        end
    end
  end)

Logger.info("Done.")
Logger.info("  Sows imported:    #{stats.sows}")
Logger.info("  Services:         #{stats.services}")
Logger.info("  Farrowings:       #{stats.farrowings}")
Logger.info("  Weanings:         #{stats.weanings}")
Logger.info("  Skipped (no tag): #{stats.skipped}")
Logger.info("  Failed:           #{stats.failed}")
Logger.info("  Login: #{owner_email}  Farm: /farms/#{farm.slug}")
