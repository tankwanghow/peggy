defmodule Peggy.Scheduler do
  @moduledoc """
  Hourly tick that auto-enqueues farm-level tasks:

    * `wean`   — lactating sows past `lactation_days` with no weaning
    * `farrow` — open services due to farrow within 7 days

  Per-farm, idempotent: each candidate maps to a stable
  `(farm, kind, ref_entity_type, ref_entity_id)` triple, so re-running
  the tick after a row already has an open task is a no-op.

  Notifications (email + PubSub) are a follow-up; for now the tasks
  surface in the Tasks LiveView and the mobile dashboard tile.
  """
  use GenServer
  require Logger

  import Ecto.Query
  alias Peggy.{FarmClock, Repo, Tasks}
  alias Peggy.Accounts.Scope

  # 1 hour. Override in tests via `init_args[:interval]` if needed.
  @default_interval :timer.hours(1)
  # Initial wait so app start isn't blocked by a sweep over many farms.
  @initial_delay :timer.seconds(30)

  # ── GenServer ──────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    schedule_first_tick()
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:tick, state) do
    safe_tick()
    Process.send_after(self(), :tick, state.interval)
    {:noreply, state}
  end

  defp schedule_first_tick do
    Process.send_after(self(), :tick, @initial_delay)
  end

  defp safe_tick do
    try do
      tick()
    rescue
      e ->
        Logger.error("Peggy.Scheduler tick failed: #{Exception.message(e)}")
    end
  end

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Runs one sweep across every farm. Returns a per-farm summary. Pure
  enough to call from tests or `iex` — no GenServer state involved.
  """
  def tick do
    Repo.all(from(f in Peggy.Farms.Farm)) |> Enum.map(&tick_farm/1)
  end

  @doc "Runs one sweep against a single farm."
  def tick_farm(%Peggy.Farms.Farm{} = farm) do
    scope = system_scope(farm)
    today = FarmClock.today(scope)

    wean_results = enqueue_wean_tasks(scope, today)
    farrow_results = enqueue_farrow_tasks(scope, today)

    %{
      farm_id: farm.id,
      wean_created: tally(wean_results, :created),
      wean_existing: tally(wean_results, :exists),
      farrow_created: tally(farrow_results, :created),
      farrow_existing: tally(farrow_results, :exists)
    }
  end

  # ── Generators ─────────────────────────────────────────────────────

  defp enqueue_wean_tasks(%Scope{farm: farm} = scope, today) do
    cutoff = Date.add(today, -wean_due_days())

    candidates =
      from(f in Peggy.Breeding.Farrowing,
        join: sow in assoc(f, :sow),
        left_join: w in Peggy.Breeding.Weaning,
        on: w.farrowing_id == f.id and is_nil(w.deleted_at),
        where:
          f.farm_id == ^farm.id and is_nil(f.deleted_at) and is_nil(w.id) and
            f.farrowed_at <= ^cutoff,
        select: %{
          farrowing_id: f.id,
          farrowed_at: f.farrowed_at,
          sow_tag: sow.ear_tag
        }
      )
      |> Repo.all()

    Enum.map(candidates, fn c ->
      attrs = %{
        title: "Wean sow #{c.sow_tag}",
        kind: "wean",
        ref_entity_type: "farrowing",
        ref_entity_id: c.farrowing_id,
        due_at: today
      }

      Tasks.find_or_create_open_task(scope, attrs)
    end)
  end

  defp enqueue_farrow_tasks(%Scope{farm: farm} = scope, today) do
    # Services "due to farrow" within ≤7 days = served_at + gestation_days <= today + 7
    farrow_cutoff = Date.add(today, 7 - gestation_days())

    excluded = ["culled" | Peggy.Animals.Animal.departed_statuses()]

    candidates =
      from(s in Peggy.Breeding.Service,
        join: sow in assoc(s, :sow),
        where:
          s.farm_id == ^farm.id and is_nil(s.result) and is_nil(s.deleted_at) and
            s.served_at <= ^farrow_cutoff and sow.status not in ^excluded,
        select: %{
          service_id: s.id,
          served_at: s.served_at,
          sow_tag: sow.ear_tag
        }
      )
      |> Repo.all()

    Enum.map(candidates, fn c ->
      due_at = Date.add(c.served_at, gestation_days())

      attrs = %{
        title: "Farrow due — sow #{c.sow_tag}",
        kind: "farrow",
        ref_entity_type: "service",
        ref_entity_id: c.service_id,
        due_at: due_at
      }

      Tasks.find_or_create_open_task(scope, attrs)
    end)
  end

  # ── Helpers ────────────────────────────────────────────────────────

  # System scope used by the scheduler — no actor user, just farm context.
  defp system_scope(farm), do: %Scope{user: nil, farm: farm, role: nil}

  defp gestation_days, do: Peggy.Breeding.gestation_days()
  defp wean_due_days, do: 21

  defp tally(results, kind) do
    Enum.count(results, fn
      {:ok, ^kind, _} -> true
      _ -> false
    end)
  end
end
