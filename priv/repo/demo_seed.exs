# Demo seed — populates a realistic-scale farm for UI / reports testing.
#
#   mix run priv/repo/demo_seed.exs
#
# Creates:
#   * demo user (demo@peggy.local) + farm (slug "demo")
#   * houses & pens with enough capacity for the herd
#   * ~20 boars
#   * 2000 sows in mixed breeding states (active / served / lactating / open)
#   * current-cycle services & farrowings auto-created by `import_herd/2`
#   * weanings for older lactations (→ dry sows + piglet batches)
#   * weaner / grower / finisher batches
#
# Idempotent guard: aborts if the demo farm already exists.

alias Peggy.{Accounts, Animals, Breeding, Farms, Repo}
alias Peggy.Accounts.Scope

require Logger
import Ecto.Query

:rand.seed(:exsss, {1, 2, 3})

demo_email = "demo@peggy.local"
farm_slug = "demo"

if Farms.get_farm_by_slug(farm_slug) do
  Logger.info("Demo farm '#{farm_slug}' already exists; aborting. `mix ecto.reset` to re-seed.")
  System.halt(0)
end

Logger.info("Creating demo user + farm…")

user =
  Accounts.get_user_by_email(demo_email) ||
    (
      {:ok, u} = Accounts.register_user(%{email: demo_email})
      u
    )

{:ok, farm} =
  Farms.create_farm(user, %{
    name: "Demo Farm",
    slug: farm_slug,
    timezone: "Asia/Kuala_Lumpur",
    unit_system: "metric"
  })

membership = Farms.get_membership(user, farm)
scope = Scope.put_farm(Scope.for_user(user), farm, membership)

# ── Houses & pens ─────────────────────────────────────────────────────
Logger.info("Creating houses & pens…")

defmodule DemoSeed do
  def make_pens(scope, house, prefix, count, capacity) do
    Enum.map(1..count, fn n ->
      {:ok, p} =
        Peggy.Locations.create_pen(scope, house, %{
          code: "#{prefix}-#{String.pad_leading(Integer.to_string(n), 2, "0")}",
          capacity: capacity,
          status: "active"
        })

      p
    end)
  end

  def make_house(scope, code, purpose) do
    {:ok, h} = Peggy.Locations.create_house(scope, %{code: code, purpose: purpose})
    h
  end

  def pick(list), do: Enum.random(list)

  def days_ago(n), do: Date.add(Date.utc_today(), -n)
end

breeding_house = DemoSeed.make_house(scope, "BR1", "breeding")
boar_pens = DemoSeed.make_pens(scope, breeding_house, "BR", 10, 2)

gest_house = DemoSeed.make_house(scope, "GST1", "gestation")
gestation_pens = DemoSeed.make_pens(scope, gest_house, "GST", 60, 20)

farrow_house = DemoSeed.make_house(scope, "FAR1", "farrowing")
farrowing_pens = DemoSeed.make_pens(scope, farrow_house, "FAR", 80, 1)

nursery_house = DemoSeed.make_house(scope, "NUR1", "nursery")
nursery_pens = DemoSeed.make_pens(scope, nursery_house, "NUR", 20, 60)

grower_house = DemoSeed.make_house(scope, "GRW1", "grower")
grower_pens = DemoSeed.make_pens(scope, grower_house, "GRW", 30, 50)

finisher_house = DemoSeed.make_house(scope, "FIN1", "finisher")
finisher_pens = DemoSeed.make_pens(scope, finisher_house, "FIN", 30, 40)

# ── Boars ─────────────────────────────────────────────────────────────
Logger.info("Creating boars…")

boars =
  Enum.map(1..20, fn i ->
    pen = DemoSeed.pick(boar_pens)

    {:ok, b} =
      Animals.create_animal(scope, %{
        tracking_type: "individual",
        ear_tag: "B#{String.pad_leading(Integer.to_string(i), 3, "0")}",
        stage: "boar",
        sex: "male",
        status: "active",
        breed: DemoSeed.pick(["Duroc", "Pietrain", "Landrace"]),
        dob: DemoSeed.days_ago(300 + :rand.uniform(300)),
        current_pen_id: pen.id
      })

    b
  end)

boar_ids = Enum.map(boars, & &1.id)

# ── Sow rows (2000) ───────────────────────────────────────────────────
# Distribution tuned for a steady-state herd:
#   1200 lactating (farrowed 0–35d ago)  — 500-600 will become dry post-wean
#   600  served    (served 1–110d ago)
#   150  open      (failed preg check)
#   50   active    (newly arrived, no cycle yet)
Logger.info("Building 2000 sow rows…")

breed_pick = fn -> DemoSeed.pick(["Landrace", "Large White", "Yorkshire", "Duroc Cross"]) end
service_type_pick = fn -> DemoSeed.pick(["ai", "ai", "ai", "natural"]) end

next_tag = fn n -> "S" <> String.pad_leading(Integer.to_string(n), 4, "0") end

lactating_rows =
  Enum.map(1..1200, fn i ->
    farrowed_days = :rand.uniform(35)
    served_days = farrowed_days + 114
    pen = DemoSeed.pick(farrowing_pens)
    stype = service_type_pick.()
    boar_id = if stype == "natural", do: DemoSeed.pick(boar_ids), else: nil

    %{
      "ear_tag" => next_tag.(i),
      "stage" => "sow",
      "sex" => "female",
      "breed" => breed_pick.(),
      "dob" => DemoSeed.days_ago(400 + :rand.uniform(600)),
      "status" => "lactating",
      "current_pen_id" => pen.id,
      "last_served_at" => DemoSeed.days_ago(served_days),
      "last_farrowed_at" => DemoSeed.days_ago(farrowed_days),
      "born_alive" => 9 + :rand.uniform(6),
      "service_type" => stype,
      "boar_id" => boar_id
    }
  end)

served_rows =
  Enum.map(1201..1800, fn i ->
    days = :rand.uniform(110)
    pen = DemoSeed.pick(gestation_pens)
    stype = service_type_pick.()
    boar_id = if stype == "natural", do: DemoSeed.pick(boar_ids), else: nil

    %{
      "ear_tag" => next_tag.(i),
      "stage" => "sow",
      "sex" => "female",
      "breed" => breed_pick.(),
      "dob" => DemoSeed.days_ago(400 + :rand.uniform(600)),
      "status" => "served",
      "current_pen_id" => pen.id,
      "last_served_at" => DemoSeed.days_ago(days),
      "service_type" => stype,
      "boar_id" => boar_id
    }
  end)

open_rows =
  Enum.map(1801..1950, fn i ->
    pen = DemoSeed.pick(gestation_pens)

    %{
      "ear_tag" => next_tag.(i),
      "stage" => "sow",
      "sex" => "female",
      "breed" => breed_pick.(),
      "dob" => DemoSeed.days_ago(400 + :rand.uniform(600)),
      "status" => "open",
      "current_pen_id" => pen.id
    }
  end)

active_rows =
  Enum.map(1951..2000, fn i ->
    pen = DemoSeed.pick(gestation_pens)

    %{
      "ear_tag" => next_tag.(i),
      "stage" => "sow",
      "sex" => "female",
      "breed" => breed_pick.(),
      "dob" => DemoSeed.days_ago(220 + :rand.uniform(60)),
      "status" => "active",
      "current_pen_id" => pen.id
    }
  end)

all_rows = lactating_rows ++ served_rows ++ open_rows ++ active_rows

Logger.info("Importing 2000 sows in batches…")

imported =
  all_rows
  |> Enum.chunk_every(100)
  |> Enum.with_index()
  |> Enum.flat_map(fn {chunk, idx} ->
    case Animals.import_herd(scope, chunk) do
      {:ok, animals} ->
        if rem(idx, 5) == 0, do: Logger.info("  batch #{idx + 1}: +#{length(animals)}")
        animals

      {:error, reason} ->
        Logger.error("import batch #{idx} failed: #{inspect(reason)}")
        System.halt(1)
    end
  end)

Logger.info("Imported #{length(imported)} sows.")

# ── Wean older lactations → creates weanings + piglet batches ─────────
Logger.info("Weaning lactations >= 22d old…")

wean_cutoff = Date.add(Date.utc_today(), -22)

lactating_sow_ids =
  imported
  |> Enum.filter(&(&1.status == "lactating"))
  |> Enum.map(& &1.id)

farrowings_by_sow =
  from(f in Peggy.Breeding.Farrowing, where: f.sow_id in ^lactating_sow_ids)
  |> Repo.all()
  |> Enum.group_by(& &1.sow_id)

to_wean =
  for sow_id <- lactating_sow_ids,
      farrowings = Map.get(farrowings_by_sow, sow_id, []),
      farrowing = farrowings |> Enum.sort_by(& &1.farrowed_at, {:desc, Date}) |> List.first(),
      not is_nil(farrowing),
      Date.compare(farrowing.farrowed_at, wean_cutoff) in [:lt, :eq],
      do: farrowing

Logger.info("  #{length(to_wean)} litters ready to wean")

{wean_ok, wean_fail} =
  Enum.reduce(to_wean, {0, 0}, fn farrowing, {ok, fail} ->
    pen = DemoSeed.pick(nursery_pens)
    wean_age = Date.diff(Date.utc_today(), farrowing.farrowed_at)
    weaned_at = Date.add(farrowing.farrowed_at, 21 + :rand.uniform(max(wean_age - 21, 1)))
    weaned_at = if Date.compare(weaned_at, Date.utc_today()) == :gt, do: Date.utc_today(), else: weaned_at
    weaned_count = max(0, (farrowing.born_alive || 10) - :rand.uniform(2))
    tag = "W-#{farrowing.sow_id}-#{Date.to_iso8601(farrowing.farrowed_at)}"

    attrs = %{
      weaned_at: weaned_at,
      weaned_count: weaned_count,
      batch_tag: tag,
      destination_pen_id: pen.id
    }

    case Breeding.record_weaning(scope, farrowing, attrs) do
      {:ok, _w, _batch} -> {ok + 1, fail}
      {:error, _} -> {ok, fail + 1}
    end
  end)

Logger.info("  weaned: #{wean_ok}, failed: #{wean_fail}")

# ── Standalone weaner / grower / finisher batches ────────────────────
Logger.info("Creating grower & finisher batches…")

for pen <- grower_pens do
  qty = 30 + :rand.uniform(20)

  {:ok, _} =
    Animals.create_animal(scope, %{
      tracking_type: "batch",
      stage: "grower",
      sex: "unknown",
      status: "active",
      breed: breed_pick.(),
      quantity: qty,
      current_pen_id: pen.id,
      dob: DemoSeed.days_ago(60 + :rand.uniform(30))
    })
end

for pen <- finisher_pens do
  qty = 25 + :rand.uniform(15)

  {:ok, _} =
    Animals.create_animal(scope, %{
      tracking_type: "batch",
      stage: "finisher",
      sex: "unknown",
      status: "active",
      breed: breed_pick.(),
      quantity: qty,
      current_pen_id: pen.id,
      dob: DemoSeed.days_ago(130 + :rand.uniform(30))
    })
end

Logger.info("Demo seed complete.")
Logger.info("  Farm:  /farms/#{farm.slug}")
Logger.info("  Login: #{demo_email} (magic link)")
