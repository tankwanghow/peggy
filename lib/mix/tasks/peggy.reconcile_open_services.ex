defmodule Mix.Tasks.Peggy.ReconcileOpenServices do
  @moduledoc """
  One-shot reconciliation for breeding services left in inconsistent
  state by legacy import paths that bypass `resolve_service_action/3`.

  Runs two passes:

  ## Pass 1 — orphan opens

  Symptom: a sow has a service with `result IS NULL` AND a later service
  for the same sow. The auto-resolver would have closed the prior as
  `re_service`, but `insert_backfill_service/4` (farrowing-csv import)
  inserts directly via `Service.changeset` and bypasses the resolver.

  Action: close the prior with `result: "re_service"`,
  `result_at: next.served_at`. Audit: `service.closed.reconciled`.

  ## Pass 2 — backfill-synth eclipses a real open

  Symptom: a `farrowing_backfill` service (result=farrowing) and a real
  open service for the same sow exist within 14 days of each other.
  The farrowing import synthesised a service at `farrowed_at − gestation`
  because the real one fell just outside the (narrow) matching window.

  Action: re-point the farrowing record from the synth to the real
  service, close the real service with `result: "farrowing"`,
  soft-delete the synth. Audits: `service.reconciled.repointed` on the
  real service and `service.deleted.reconciled` on the synth.

      mix peggy.reconcile_open_services            # dry-run (default)
      mix peggy.reconcile_open_services --commit   # apply changes
  """

  use Mix.Task

  import Ecto.Query

  alias Peggy.Accounts.Scope
  alias Peggy.Audit
  alias Peggy.Breeding.Service
  alias Peggy.Farms.Farm
  alias Peggy.Repo

  @shortdoc "Reconcile orphan open services and backfill-synth eclipses"

  # Same window as the (widened) import matching tolerance — see
  # @import_gestation_tolerance_days in Peggy.Imports.
  @synth_match_window_days 14

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args, switches: [commit: :boolean])
    commit? = Keyword.get(opts, :commit, false)

    IO.puts("\n── Pass 1: orphan opens with a later service ──")
    orphans = find_orphans()
    Enum.each(orphans, &print_orphan/1)
    IO.puts("Found #{length(orphans)} orphan open service(s).")

    IO.puts("\n── Pass 2: backfill-synth eclipsing a real open ──")
    synths = find_synth_pairs()
    Enum.each(synths, &print_synth/1)
    IO.puts("Found #{length(synths)} backfill-synth eclipse(s).")

    total = length(orphans) + length(synths)

    cond do
      total == 0 ->
        IO.puts("\nNothing to reconcile.")

      not commit? ->
        IO.puts("\nDry-run. Re-run with --commit to apply.")

      true ->
        IO.puts("\nApplying pass 1...")
        r1 = Enum.map(orphans, &apply_close/1)
        IO.puts("Closed #{Enum.count(r1, &(&1 == :ok))} / #{length(r1)}.")

        IO.puts("Applying pass 2...")
        r2 = Enum.map(synths, &apply_repoint/1)
        IO.puts("Repointed #{Enum.count(r2, &(&1 == :ok))} / #{length(r2)}.")
    end
  end

  # ── Pass 1 ────────────────────────────────────────────────────────

  defp find_orphans do
    opens =
      Repo.all(
        from(s in Service,
          where: is_nil(s.result) and is_nil(s.deleted_at),
          order_by: [asc: s.sow_id, asc: s.served_at, asc: s.id]
        )
      )

    Enum.flat_map(opens, fn open ->
      next =
        Repo.one(
          from(s in Service,
            where:
              s.sow_id == ^open.sow_id and
                s.id != ^open.id and
                is_nil(s.deleted_at) and
                s.served_at > ^open.served_at,
            order_by: [asc: s.served_at, asc: s.id],
            limit: 1
          )
        )

      case next do
        nil -> []
        %Service{} = n -> [{open, n}]
      end
    end)
  end

  defp print_orphan({open, next}) do
    IO.puts(
      "  sow=#{open.sow_id} farm=#{open.farm_id} " <>
        "open##{open.id} served=#{open.served_at} " <>
        "→ close as re_service at #{next.served_at} (next##{next.id})"
    )
  end

  defp apply_close({open, next}) do
    scope = %Scope{farm: %Farm{id: open.farm_id}}

    Repo.transaction(fn ->
      cs =
        Service.close_changeset(open, %{
          "result" => "re_service",
          "result_at" => next.served_at
        })

      case Repo.update(cs) do
        {:ok, closed} ->
          Audit.log_now!(scope, "service.closed.reconciled",
            entity_type: :service,
            entity_id: closed.id,
            changes: %{
              "result" => "re_service",
              "result_at" => to_string(closed.result_at),
              "next_service_id" => next.id,
              "via" => "mix peggy.reconcile_open_services"
            }
          )

          :ok

        {:error, cs} ->
          IO.puts("  ERROR sow=#{open.sow_id} open##{open.id}: #{inspect(cs.errors)}")
          Repo.rollback(:invalid)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      _ -> :error
    end
  end

  # ── Pass 2 ────────────────────────────────────────────────────────

  defp find_synth_pairs do
    synths =
      Repo.all(
        from(s in Service,
          where:
            s.created_via == "farrowing_backfill" and
              s.result == "farrowing" and
              is_nil(s.deleted_at),
          order_by: [asc: s.sow_id, asc: s.served_at, asc: s.id]
        )
      )
      |> Repo.preload(:farrowing)

    Enum.flat_map(synths, fn synth ->
      earliest = Date.add(synth.served_at, -@synth_match_window_days)
      latest = Date.add(synth.served_at, @synth_match_window_days)

      real =
        Repo.one(
          from(s in Service,
            where:
              s.sow_id == ^synth.sow_id and
                s.id != ^synth.id and
                is_nil(s.deleted_at) and
                is_nil(s.result) and
                s.created_via != "farrowing_backfill" and
                s.served_at >= ^earliest and
                s.served_at <= ^latest,
            order_by: [
              asc: fragment("ABS(? - ?)", s.served_at, ^synth.served_at),
              asc: s.id
            ],
            limit: 1
          )
        )

      cond do
        is_nil(real) -> []
        is_nil(synth.farrowing) -> []
        true -> [{synth, real}]
      end
    end)
  end

  defp print_synth({synth, real}) do
    IO.puts(
      "  sow=#{synth.sow_id} farm=#{synth.farm_id} " <>
        "synth##{synth.id} served=#{synth.served_at} farrowed=#{synth.result_at} " <>
        "→ repoint farrowing##{synth.farrowing.id} to real##{real.id} (served=#{real.served_at}), " <>
        "soft-delete synth"
    )
  end

  defp apply_repoint({synth, real}) do
    scope = %Scope{farm: %Farm{id: synth.farm_id}}
    farrowed_at = synth.result_at
    now = DateTime.utc_now(:second)

    Repo.transaction(fn ->
      with {:ok, _farrowing} <-
             synth.farrowing
             |> Ecto.Changeset.change(%{service_id: real.id})
             |> Repo.update(),
           {:ok, closed_real} <-
             real
             |> Service.close_changeset(%{
               "result" => "farrowing",
               "result_at" => farrowed_at
             })
             |> Repo.update(),
           {:ok, deleted_synth} <-
             synth
             |> Ecto.Changeset.change(%{deleted_at: now})
             |> Repo.update() do
        Audit.log_now!(scope, "service.reconciled.repointed",
          entity_type: :service,
          entity_id: closed_real.id,
          changes: %{
            "via" => "mix peggy.reconcile_open_services",
            "synth_service_id" => synth.id,
            "farrowing_id" => synth.farrowing.id,
            "result" => "farrowing",
            "result_at" => to_string(farrowed_at)
          }
        )

        Audit.log_now!(scope, "service.deleted.reconciled",
          entity_type: :service,
          entity_id: deleted_synth.id,
          changes: %{
            "via" => "mix peggy.reconcile_open_services",
            "reason" => "superseded_by_real_service",
            "real_service_id" => real.id
          }
        )

        :ok
      else
        {:error, cs} ->
          IO.puts(
            "  ERROR sow=#{synth.sow_id} synth##{synth.id} real##{real.id}: #{inspect(cs.errors)}"
          )

          Repo.rollback(:invalid)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      _ -> :error
    end
  end
end
