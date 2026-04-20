defmodule Peggy.Breeding do
  @moduledoc """
  Breeding & reproduction: services, farrowings, weanings.

  Every function takes a `%Scope{}` and enforces `farm_id` isolation.
  Mutations write `audit_logs` rows in the same transaction.

  ## Service result lifecycle

  A service starts with `result = nil` (open — sow is gestating).
  The result is set when the outcome is known:

  * `farrowing` — sow gave birth (set by `record_farrowing/3`)
  * `re_service` — sow returned to heat (auto-set when a new service
    is recorded for the same sow)
  * `abortion` — pregnancy terminated early
  * `death` — sow died during gestation
  * `cull` — sow culled during gestation

  When `result IS NULL`, the sow is considered currently gestating.
  Expected farrowing date is computed as `served_at + 114 days`.
  """

  import Ecto.Query
  alias Ecto.Multi
  alias Peggy.{Animals, Repo, Audit}
  alias Peggy.Accounts.Scope
  alias Peggy.Animals.Animal
  alias Peggy.Audit.AuditLog
  alias Peggy.Breeding.{Service, Farrowing, Weaning}
  alias Peggy.Animals.{Movement, Placement}

  @gestation_days 114
  @lactation_days 24
  @minimum_sow_age_days 365

  def gestation_days, do: @gestation_days
  def lactation_days, do: @lactation_days
  def minimum_sow_age_days, do: @minimum_sow_age_days

  # ── Services ──────────────────────────────────────────────────────

  @doc """
  Records a breeding service for a sow.

  If the sow already has an open service (result IS NULL), the previous
  one is auto-closed with `result = re_service`.
  """
  def record_service(%Scope{} = scope, attrs) do
    farm = scope.farm
    attrs = Map.put(attrs, "farm_id", farm.id) |> stringify_keys()

    multi =
      Multi.new()
      |> ensure_sow_serviceable(scope, attrs)
      |> auto_close_prior_service(scope, attrs)
      |> Multi.insert(:service, Service.changeset(%Service{}, attrs))
      |> update_sow_status(attrs["sow_id"], "served")
      |> audit_after(scope, "service.created", :service)

    case Repo.transaction(multi) do
      {:ok, %{service: service}} -> {:ok, service}
      {:error, :service, cs, _} -> {:error, cs}
      {:error, :ensure_serviceable, cs, _} -> {:error, cs}
      {:error, step, cs, _} -> {:error, {step, cs}}
    end
  end

  @doc """
  Records multiple services atomically (batch entry from spreadsheet grid).

  Each entry is a map with `:sow_id`, `:boar_id`, `:service_type`,
  `:served_at`, `:notes`. Keys may be atoms or strings.

  Returns `{:ok, [service, ...]}` on success,
  `{:error, {row_index, changeset}}` on failure.
  Any failure rolls back the entire batch.
  """
  def record_batch_services(%Scope{} = scope, entries)
      when is_list(entries) and entries != [] do
    farm = scope.farm

    multi =
      entries
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {entry, i}, m ->
        attrs =
          entry
          |> stringify_keys()
          |> Map.put("farm_id", farm.id)

        m
        |> ensure_sow_serviceable_keyed(scope, attrs, i)
        |> auto_close_prior_service_keyed(scope, attrs, i)
        |> Multi.insert({:service, i}, Service.changeset(%Service{}, attrs))
        |> update_sow_status_keyed(attrs["sow_id"], "served", i)
        |> audit_after_keyed(scope, "service.created", {:service, i}, i)
      end)

    case Repo.transaction(multi) do
      {:ok, changes} ->
        services =
          0..(length(entries) - 1)
          |> Enum.map(&Map.fetch!(changes, {:service, &1}))

        {:ok, services}

      {:error, {:service, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, {:ensure_serviceable, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, _op, reason, _} ->
        {:error, reason}
    end
  end

  def record_batch_services(_scope, []), do: {:error, :no_entries}

  @doc """
  Records a service, optionally back-filling the sow when no animal
  with the given ear tag exists on the farm. First hop of the PR 5
  back-fill cascade; see design notes.

  Routing:

    * `:sow_id` set, or `:sow_ear_tag` resolves to a present animal →
      delegates to `record_service/2`.
    * `:sow_ear_tag` missing, no `:backfill_sow` map → returns
      `{:error, :sow_not_found}`.
    * Tag does not match any present animal but a similar tag exists
      (Levenshtein ≤ 2) → hard-blocks with
      `{:error, {:similar_tag, [tag, ...]}}`. Caller must pick one of
      the suggested tags or set `force_create: true` inside the
      `:backfill_sow` map to override.
    * Otherwise creates sow + service atomically. The inferred sow is
      marked `inferred: true`, `needs_review: true`,
      `created_via: "back_fill_from_service"` and has `origin_audit_id`
      pointing at its `animal.created.inferred` audit row.

  Returns `{:ok, %{sow: sow, service: service, inferred?: bool}}` on
  success, `{:error, reason}` otherwise.
  """
  def record_service_with_backfill(%Scope{} = scope, attrs) do
    attrs = stringify_keys(attrs)
    ear_tag = attrs["sow_ear_tag"]
    has_sow_id? = not is_nil(to_int(attrs["sow_id"]))

    cond do
      has_sow_id? -> delegate_to_record_service(scope, attrs)
      is_nil(ear_tag) or ear_tag == "" -> delegate_to_record_service(scope, attrs)
      true -> resolve_sow_for_backfill(scope, ear_tag, attrs)
    end
  end

  defp delegate_to_record_service(scope, attrs) do
    pen_id = to_int(attrs["pen_id"])

    cleaned =
      attrs
      |> Map.delete("sow_ear_tag")
      |> Map.delete("backfill_sow")
      |> Map.delete("pen_id")

    Repo.transaction(fn ->
      case record_service(scope, cleaned) do
        {:ok, service} ->
          sow = Repo.get!(Animal, service.sow_id)

          case move_existing_sow_for_service(scope.farm.id, sow, pen_id, service.served_at) do
            {:ok, sow} -> %{sow: sow, service: service, inferred?: false}
            {:error, cs} -> Repo.rollback(cs)
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  defp move_existing_sow_for_service(_farm_id, sow, nil, _date), do: {:ok, sow}

  defp move_existing_sow_for_service(_farm_id, %{current_pen_id: cur} = sow, pen_id, _date)
       when cur == pen_id,
       do: {:ok, sow}

  defp move_existing_sow_for_service(farm_id, sow, pen_id, served_at) do
    reason = if is_nil(sow.current_pen_id), do: "placement", else: "pen_transfer"
    moved_at = served_at || Date.utc_today()

    multi =
      Multi.new()
      |> Multi.insert(
        :sow_movement,
        Movement.changeset(%Movement{}, %{
          "farm_id" => farm_id,
          "animal_id" => sow.id,
          "from_pen_id" => sow.current_pen_id,
          "to_pen_id" => pen_id,
          "reason" => reason,
          "quantity" => 1,
          "moved_at" => moved_at
        })
      )
      |> Multi.update(:sow_pen, Ecto.Changeset.change(sow, %{current_pen_id: pen_id}))

    case Repo.transaction(multi) do
      {:ok, %{sow_pen: sow}} -> {:ok, sow}
      {:error, _step, cs, _} -> {:error, cs}
    end
  end

  defp resolve_sow_for_backfill(scope, ear_tag, attrs) do
    case Animals.find_by_ear_tag(scope, ear_tag) do
      %Animal{id: id} ->
        attrs
        |> Map.put("sow_id", id)
        |> Map.delete("sow_ear_tag")
        |> then(&delegate_to_record_service(scope, &1))

      nil ->
        backfill = Map.get(attrs, "backfill_sow")
        similars = Animals.similar_ear_tags(scope, ear_tag)

        force? =
          truthy?(
            backfill && (Map.get(backfill, :force_create) || Map.get(backfill, "force_create"))
          )

        cond do
          similars != [] and not force? -> {:error, {:similar_tag, similars}}
          is_nil(backfill) -> {:error, :sow_not_found}
          true -> do_inferred_sow_and_service(scope, ear_tag, backfill, attrs)
        end
    end
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?(_), do: false

  defp do_inferred_sow_and_service(%Scope{} = scope, ear_tag, backfill_attrs, service_attrs) do
    farm = scope.farm
    pen_id = to_int(service_attrs["pen_id"])

    service_attrs =
      service_attrs
      |> Map.delete("sow_ear_tag")
      |> Map.delete("backfill_sow")
      |> Map.delete("pen_id")
      |> Map.put("farm_id", farm.id)

    served_at = parse_date(service_attrs["served_at"]) || Date.utc_today()

    sow_changeset = build_inferred_sow_changeset(farm, ear_tag, backfill_attrs, service_attrs)

    multi =
      Multi.new()
      |> Multi.insert(:sow, sow_changeset)
      |> Multi.insert(:sow_audit, fn %{sow: sow} -> inferred_sow_audit(scope, sow) end)
      |> Multi.update(:sow_with_origin, fn %{sow: sow, sow_audit: audit} ->
        Ecto.Changeset.change(sow, origin_audit_id: audit.id)
      end)
      |> Multi.insert(:service, fn %{sow_with_origin: sow} ->
        Service.changeset(%Service{}, Map.put(service_attrs, "sow_id", sow.id))
      end)
      |> Multi.run(:sow_served, fn _repo, %{sow_with_origin: sow} ->
        changes = %{status: "served"}
        changes = if pen_id, do: Map.put(changes, :current_pen_id, pen_id), else: changes
        sow |> Ecto.Changeset.change(changes) |> Repo.update()
      end)
      |> maybe_insert_inferred_sow_placement(farm.id, pen_id, served_at)
      |> audit_after(scope, "service.created", :service)

    case Repo.transaction(multi) do
      {:ok, %{service: service, sow_served: sow}} ->
        {:ok, %{sow: sow, service: service, inferred?: true}}

      {:error, :sow, cs, _} ->
        {:error, cs}

      {:error, :service, cs, _} ->
        {:error, cs}

      {:error, step, cs, _} ->
        {:error, {step, cs}}
    end
  end

  defp maybe_insert_inferred_sow_placement(multi, _farm_id, nil, _moved_at), do: multi

  defp maybe_insert_inferred_sow_placement(multi, farm_id, pen_id, moved_at) do
    Multi.insert(multi, :sow_placement, fn %{sow_with_origin: sow} ->
      Movement.changeset(%Movement{}, %{
        "farm_id" => farm_id,
        "animal_id" => sow.id,
        "from_pen_id" => nil,
        "to_pen_id" => pen_id,
        "reason" => "placement",
        "quantity" => 1,
        "moved_at" => moved_at
      })
    end)
  end

  defp build_inferred_sow_changeset(farm, ear_tag, backfill_attrs, service_attrs) do
    backfill_attrs = stringify_keys(backfill_attrs || %{})
    served_at = parse_date(service_attrs["served_at"]) || Date.utc_today()
    default_dob = Date.add(served_at, -@minimum_sow_age_days)

    Animal.changeset(%Animal{}, %{
      "tracking_type" => "individual",
      "ear_tag" => ear_tag,
      "sex" => "female",
      "stage" => "sow",
      "status" => "open",
      "dob" => backfill_attrs["dob"] || default_dob,
      "breed" => backfill_attrs["breed"],
      "notes" => backfill_attrs["notes"],
      "inferred" => true,
      "needs_review" => true,
      "created_via" => "back_fill_from_service",
      "farm_id" => farm.id
    })
  end

  defp inferred_sow_audit(scope, %Animal{} = sow) do
    %AuditLog{
      farm_id: scope.farm.id,
      actor_user_id: scope.user && scope.user.id,
      action: "animal.created.inferred",
      entity_type: "animal",
      entity_id: to_string(sow.id),
      changes: %{"ear_tag" => sow.ear_tag, "created_via" => sow.created_via},
      inserted_at: DateTime.utc_now(:second)
    }
  end

  defp parse_date(%Date{} = d), do: d

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  # Reject services for sows that aren't biologically eligible:
  # only `active`, `open`, `dry`, or `served` (re-service via auto-close)
  # are allowed. `lactating`, `culled`, and departed statuses error out
  # with a changeset error rather than silently moving the sow to "served".
  @serviceable_for_new_service ~w(active open dry served)

  defp ensure_sow_serviceable(multi, scope, attrs) do
    sow_id = to_int(attrs["sow_id"])

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, :ensure_serviceable, fn repo, _ ->
        check_sow_serviceable(repo, scope, sow_id, attrs)
      end)
    end
  end

  defp ensure_sow_serviceable_keyed(multi, scope, attrs, i) do
    sow_id = to_int(attrs["sow_id"])

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, {:ensure_serviceable, i}, fn repo, _ ->
        check_sow_serviceable(repo, scope, sow_id, attrs)
      end)
    end
  end

  defp check_sow_serviceable(repo, scope, sow_id, attrs) do
    case repo.get(Animal, sow_id) do
      nil ->
        cs =
          %Service{}
          |> Service.changeset(attrs)
          |> Ecto.Changeset.add_error(:sow_id, "does not exist")

        {:error, cs}

      %Animal{farm_id: fid} when fid != scope.farm.id ->
        cs =
          %Service{}
          |> Service.changeset(attrs)
          |> Ecto.Changeset.add_error(:sow_id, "does not exist")

        {:error, cs}

      %Animal{status: status} = sow when status in @serviceable_for_new_service ->
        {:ok, sow}

      %Animal{status: status} ->
        cs =
          %Service{}
          |> Service.changeset(attrs)
          |> Ecto.Changeset.add_error(
            :sow_id,
            "cannot service a sow with status \"#{status}\""
          )

        {:error, cs}
    end
  end

  # Keyed variant of auto_close_prior_service for batch entry
  defp auto_close_prior_service_keyed(multi, scope, attrs, i) do
    sow_id = to_int(attrs["sow_id"])

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, {:close_prior, i}, fn repo, _ ->
        case repo.one(
               from(s in Service,
                 where:
                   s.farm_id == ^scope.farm.id and
                     s.sow_id == ^sow_id and
                     is_nil(s.result) and
                     is_nil(s.deleted_at),
                 lock: "FOR UPDATE"
               )
             ) do
          nil ->
            {:ok, nil}

          prior ->
            result_at = attrs["served_at"] || to_string(Date.utc_today())

            prior
            |> Service.close_changeset(%{"result" => "re_service", "result_at" => result_at})
            |> repo.update()
        end
      end)
      |> Multi.run({:audit_close_prior, i}, fn _repo, changes ->
        prior = Map.get(changes, {:close_prior, i})

        if prior do
          Audit.log_now!(scope, "service.closed",
            entity_type: :service,
            entity_id: prior.id
          )
        end

        {:ok, nil}
      end)
    end
  end

  defp audit_after_keyed(multi, scope, action, key, i) do
    Multi.run(multi, {:audit, action, i}, fn _repo, changes ->
      row = Map.fetch!(changes, key)

      Audit.log_now!(scope, action,
        entity_type: :service,
        entity_id: row.id
      )

      {:ok, :logged}
    end)
  end

  # Auto-close any prior open service for the same sow.
  defp auto_close_prior_service(multi, scope, attrs) do
    sow_id = to_int(attrs["sow_id"])

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, :close_prior, fn repo, _ ->
        case repo.one(
               from(s in Service,
                 where:
                   s.farm_id == ^scope.farm.id and
                     s.sow_id == ^sow_id and
                     is_nil(s.result) and
                     is_nil(s.deleted_at),
                 lock: "FOR UPDATE"
               )
             ) do
          nil ->
            {:ok, nil}

          prior ->
            result_at = attrs["served_at"] || to_string(Date.utc_today())

            prior
            |> Service.close_changeset(%{"result" => "re_service", "result_at" => result_at})
            |> repo.update()
        end
      end)
      |> Multi.run(:audit_close_prior, fn _repo, %{close_prior: prior} ->
        if prior do
          Audit.log_now!(scope, "service.closed",
            entity_type: :service,
            entity_id: prior.id
          )
        end

        {:ok, nil}
      end)
    end
  end

  @doc """
  Closes an open service with a result (abortion, death, cull).

  Use `record_farrowing/3` instead when the result is a farrowing.

  For death/cull, a departure movement is recorded and the sow's status
  is set via the movement system (deceased/sold). For abortion, the sow
  returns to `active`.
  """
  @sow_departure_statuses %{
    "death" => "deceased",
    "cull" => "sold"
  }

  @sow_departure_reasons %{
    "death" => "death",
    "cull" => "sale"
  }

  def close_service(%Scope{} = scope, %Service{} = service, result, attrs \\ %{}) do
    if service.result do
      {:error, :already_closed}
    else
      attrs =
        attrs
        |> stringify_keys()
        |> Map.merge(%{"result" => result})

      multi =
        Multi.new()
        |> Multi.update(:service, Service.close_changeset(service, attrs))
        |> handle_sow_after_close(scope, service.sow_id, result, attrs)
        |> audit_after(scope, "service.closed", :service)

      case Repo.transaction(multi) do
        {:ok, %{service: service}} -> {:ok, service}
        {:error, :service, cs, _} -> {:error, cs}
      end
    end
  end

  # Sow becomes "open" after abortion — ready to be re-served
  defp handle_sow_after_close(multi, _scope, sow_id, "abortion", _attrs) do
    Multi.run(multi, :update_sow, fn _repo, _ ->
      sow = Repo.get!(Animal, sow_id)
      sow |> Ecto.Changeset.change(%{status: "open"}) |> Repo.update()
    end)
  end

  # Sow departs via death or cull — record departure movement
  defp handle_sow_after_close(multi, scope, sow_id, result, attrs)
       when result in ["death", "cull"] do
    Multi.run(multi, :depart_sow, fn _repo, _ ->
      sow = Repo.get!(Animal, sow_id)
      reason = Map.fetch!(@sow_departure_reasons, result)
      moved_at = attrs["result_at"] || to_string(Date.utc_today())

      with {:ok, _movement} <-
             Repo.insert(
               Movement.changeset(%Movement{}, %{
                 "farm_id" => scope.farm.id,
                 "animal_id" => sow.id,
                 "from_pen_id" => sow.current_pen_id,
                 "reason" => reason,
                 "quantity" => 1,
                 "moved_at" => moved_at,
                 "previous_status" => sow.status
               })
             ) do
        status = Map.fetch!(@sow_departure_statuses, result)
        sow |> Ecto.Changeset.change(%{status: status, current_pen_id: nil}) |> Repo.update()
      end
    end)
  end

  defp handle_sow_after_close(multi, _scope, _sow_id, _result, _attrs), do: multi

  @doc """
  Returns the current open service for a sow, or nil.
  """
  def current_service(%Scope{farm: farm}, sow_id) do
    Repo.one(
      from(s in Service,
        where:
          s.farm_id == ^farm.id and s.sow_id == ^sow_id and
            is_nil(s.result) and is_nil(s.deleted_at),
        order_by: [desc: s.served_at, desc: s.id],
        limit: 1,
        preload: [:sow, :boar]
      )
    )
  end

  @doc """
  Lists all services for a farm, newest first.
  Supports optional filters: `sow_id`, `result`.
  """
  def list_services(%Scope{farm: farm}, opts \\ []) do
    from(s in Service,
      where: s.farm_id == ^farm.id and is_nil(s.deleted_at),
      order_by: [desc: s.served_at, desc: s.id],
      preload: [:sow, :boar]
    )
    |> maybe_filter_service(:sow_id, Keyword.get(opts, :sow_id))
    |> maybe_filter_service(:result, Keyword.get(opts, :result))
    |> Repo.all()
  end

  @doc """
  Lists services for a specific sow, newest first.
  """
  def list_services_for_sow(%Scope{} = scope, sow_id) do
    list_services(scope, sow_id: sow_id)
  end

  @doc """
  Gets a service by id, scoped to the farm.
  """
  def get_service!(%Scope{farm: farm}, id) do
    Repo.one!(
      from(s in Service,
        where: s.id == ^id and s.farm_id == ^farm.id and is_nil(s.deleted_at)
      )
    )
    |> Repo.preload([:sow, :boar, farrowing: [:weaning]])
  end

  @doc """
  Returns a changeset for tracking service form changes.
  """
  def change_service(%Service{} = service, attrs \\ %{}) do
    Service.changeset(service, attrs)
  end

  # ── Service soft-delete ────────────────────────────────────────────

  @doc """
  Returns `true` if the service may be soft-deleted.

  Allowed when the service is still open (`result IS NULL`) or was
  superseded by a later service (`result = "re_service"`). Services that
  closed with a meaningful outcome (`farrowing`, `abortion`, `death`,
  `cull`) are locked — their side effects on sow state make rewind
  unsafe.
  """
  def service_deletable?(%Scope{}, %Service{deleted_at: %_{}}), do: false
  def service_deletable?(%Scope{}, %Service{result: nil}), do: true
  def service_deletable?(%Scope{}, %Service{result: "re_service"}), do: true
  def service_deletable?(%Scope{}, %Service{}), do: false

  @doc """
  Soft-deletes a service.

  Preconditions: see `service_deletable?/2`.

  State rewind: if the service was open (`result IS NULL`) and the sow's
  current status is `"served"`, the sow is reverted to `"open"` (ready
  to be serviced again).

  Returns `{:ok, service}` or `{:error, reason}` where reason is one of:

    * `:already_deleted`
    * `:service_has_closed_outcome`
  """
  def delete_service(%Scope{} = scope, %Service{} = service) do
    cond do
      not is_nil(service.deleted_at) ->
        {:error, :already_deleted}

      not service_deletable?(scope, service) ->
        {:error, :service_has_closed_outcome}

      true ->
        do_delete_service(scope, service)
    end
  end

  defp do_delete_service(scope, service) do
    now = DateTime.utc_now(:second)
    user_id = scope.user && scope.user.id

    multi =
      Multi.new()
      |> Multi.update(
        :service,
        Ecto.Changeset.change(service, %{deleted_at: now, deleted_by_id: user_id})
      )
      |> maybe_revert_sow_to_dry(service)
      |> Audit.log!(scope, "service.deleted",
        entity_type: :service,
        entity_id: service.id,
        changes: %{snapshot: service_snapshot(service)}
      )

    case Repo.transaction(multi) do
      {:ok, %{service: s}} -> {:ok, s}
      {:error, step, reason, _} -> {:error, {step, reason}}
    end
  end

  defp maybe_revert_sow_to_dry(multi, %Service{result: nil, sow_id: sow_id}) do
    Multi.run(multi, :revert_sow, fn repo, _ ->
      sow = repo.get!(Animal, sow_id)

      if sow.status == "served" do
        sow |> Ecto.Changeset.change(%{status: "open"}) |> repo.update()
      else
        {:ok, sow}
      end
    end)
  end

  defp maybe_revert_sow_to_dry(multi, _service), do: multi

  @doc """
  Restores a soft-deleted service.

  Rejects if another open service already exists for the sow (would
  create two concurrent pregnancies). Reapplies sow state if the
  restored service was open.

  Error reasons:

    * `:not_deleted`
    * `:conflicting_open_service`
  """
  def restore_service(%Scope{} = scope, %Service{} = service) do
    cond do
      is_nil(service.deleted_at) ->
        {:error, :not_deleted}

      is_nil(service.result) and open_service_exists?(scope, service.sow_id, service.id) ->
        {:error, :conflicting_open_service}

      true ->
        do_restore_service(scope, service)
    end
  end

  defp do_restore_service(scope, service) do
    multi =
      Multi.new()
      |> Multi.update(
        :service,
        Ecto.Changeset.change(service, %{deleted_at: nil, deleted_by_id: nil})
      )
      |> maybe_reapply_sow_served(service)
      |> Audit.log!(scope, "service.restored",
        entity_type: :service,
        entity_id: service.id,
        changes: %{}
      )

    case Repo.transaction(multi) do
      {:ok, %{service: s}} -> {:ok, s}
      {:error, step, reason, _} -> {:error, {step, reason}}
    end
  end

  defp maybe_reapply_sow_served(multi, %Service{result: nil, sow_id: sow_id}) do
    Multi.run(multi, :reapply_sow, fn repo, _ ->
      sow = repo.get!(Animal, sow_id)

      if sow.status in ["open", "dry"] do
        sow |> Ecto.Changeset.change(%{status: "served"}) |> repo.update()
      else
        {:ok, sow}
      end
    end)
  end

  defp maybe_reapply_sow_served(multi, _service), do: multi

  defp open_service_exists?(%Scope{farm: farm}, sow_id, except_id) do
    Repo.exists?(
      from(s in Service,
        where:
          s.farm_id == ^farm.id and s.sow_id == ^sow_id and
            is_nil(s.result) and is_nil(s.deleted_at) and
            s.id != ^except_id
      )
    )
  end

  @doc """
  Lists soft-deleted services for the farm, newest first.

  Options: `:limit` (default 50).
  """
  def list_deleted_services(%Scope{farm: farm}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(s in Service,
      where: s.farm_id == ^farm.id and not is_nil(s.deleted_at),
      order_by: [desc: s.deleted_at, desc: s.id],
      limit: ^limit,
      preload: [:sow, :boar, :deleted_by]
    )
    |> Repo.all()
  end

  @doc """
  Fetches a soft-deleted service by id, scoped to the farm. Raises if
  the row does not exist or is not deleted.
  """
  def get_deleted_service!(%Scope{farm: farm}, id) do
    Repo.one!(
      from(s in Service,
        where: s.id == ^id and s.farm_id == ^farm.id and not is_nil(s.deleted_at),
        preload: [:sow, :boar, :deleted_by]
      )
    )
  end

  defp service_snapshot(%Service{} = s) do
    %{
      id: s.id,
      sow_id: s.sow_id,
      boar_id: s.boar_id,
      service_type: s.service_type,
      served_at: s.served_at && Date.to_iso8601(s.served_at),
      result: s.result,
      result_at: s.result_at && Date.to_iso8601(s.result_at),
      notes: s.notes
    }
  end

  # ── Gestating sows (read helpers) ──────────────────────────────────

  @doc """
  Lists sows currently gestating (services with `result IS NULL`).

  Options:
    * `:search` — case-insensitive ear-tag prefix (matches sow ear tag)
    * `:due_window` — `"all"` (default) | `"7"` | `"14"` | `"overdue"`
    * `:service_type` — `"all"` (default) | `"natural"` | `"ai"`
    * `:limit` — defaults to 25; pass `:all` to disable pagination
    * `:offset` — defaults to 0

  Returns a list of maps shaped `%{service: s, expected_farrow_date: d}`.
  """
  def list_gestating_sows(scope, opts \\ [])

  def list_gestating_sows(%Scope{farm: farm}, opts) do
    farm
    |> gestating_query(opts)
    |> apply_pagination(opts)
    |> Repo.all()
    |> Enum.map(&with_expected_farrow_date/1)
  end

  @doc """
  Counts gestating sows matching the same filter opts as
  `list_gestating_sows/2` (ignores `:limit`/`:offset`).
  """
  def count_gestating_sows(%Scope{farm: farm}, opts \\ []) do
    farm |> gestating_query(opts) |> exclude(:order_by) |> Repo.aggregate(:count, :id)
  end

  defp gestating_query(farm, opts) do
    today = Date.utc_today()
    search = opts |> Keyword.get(:search) |> normalize_search()
    service_type = Keyword.get(opts, :service_type, "all")
    due_window = Keyword.get(opts, :due_window, "all")

    q =
      from(s in Service,
        join: sow in assoc(s, :sow),
        where: s.farm_id == ^farm.id and is_nil(s.result) and is_nil(s.deleted_at),
        order_by: [asc: s.served_at],
        preload: [:sow, :boar]
      )

    q =
      if search do
        like = "#{search}%"
        from [s, sow] in q, where: ilike(sow.ear_tag, ^like)
      else
        q
      end

    q =
      case service_type do
        t when t in ["natural", "ai"] -> from s in q, where: s.service_type == ^t
        _ -> q
      end

    case due_window do
      "7" ->
        cutoff = Date.add(today, 7 - @gestation_days)
        from s in q, where: s.served_at <= ^cutoff

      "14" ->
        cutoff = Date.add(today, 14 - @gestation_days)
        from s in q, where: s.served_at <= ^cutoff

      "overdue" ->
        cutoff = Date.add(today, -@gestation_days)
        from s in q, where: s.served_at <= ^cutoff

      _ ->
        q
    end
  end

  @doc """
  Lists gestating sows due to farrow within `days_ahead` days.
  """
  def list_due_farrowings(%Scope{farm: farm}, days_ahead \\ 7) do
    # Services served before this date have expected farrowing within the window
    served_before = Date.add(Date.utc_today(), days_ahead - @gestation_days)

    from(s in Service,
      where:
        s.farm_id == ^farm.id and
          is_nil(s.result) and
          is_nil(s.deleted_at) and
          s.served_at <= ^served_before,
      order_by: [asc: s.served_at],
      preload: [:sow, :boar]
    )
    |> Repo.all()
    |> Enum.map(&with_expected_farrow_date/1)
  end

  @doc """
  Computes the expected farrowing date for a service.
  """
  def expected_farrow_date(%Service{served_at: served_at}) do
    Date.add(served_at, @gestation_days)
  end

  defp with_expected_farrow_date(%Service{} = s) do
    %{service: s, expected_farrow_date: expected_farrow_date(s)}
  end

  # ── Farrowings ──────────────────────────────────────────────────────

  @doc """
  Records a farrowing event for a gestating sow.

  In one atomic transaction:
  1. Inserts the farrowing row
  2. Closes the service with `result = "farrowing"`
  3. Creates `born_alive` piglet animals with `stage=piglet`, `sex=unknown`,
     `dam_id=sow`, `sire_id=service.boar_id`, `dob=farrowed_at`
  4. Sets piglets' `current_pen_id` to `farrowing.pen_id || sow.current_pen_id`
  5. Auto-promotes sow stage to `"sow"` if not already
  6. Audits the farrowing

  If the sow has no `current_pen_id` and no `pen_id` is given in attrs,
  piglets are created unplaced (`current_pen_id = nil`).
  """
  def record_farrowing(%Scope{} = scope, %Service{} = service, attrs) do
    if service.result do
      {:error, :service_already_closed}
    else
      do_record_farrowing(scope, service, stringify_keys(attrs))
    end
  end

  defp do_record_farrowing(scope, service, attrs) do
    farm = scope.farm
    sow = Repo.get!(Animal, service.sow_id)
    pen_id = to_int(attrs["pen_id"]) || sow.current_pen_id
    born_alive = to_int(attrs["born_alive"]) || 0
    farrowed_at = attrs["farrowed_at"]

    farrowing_attrs =
      attrs
      |> Map.merge(%{
        "farm_id" => farm.id,
        "service_id" => service.id,
        "sow_id" => sow.id,
        "pen_id" => pen_id
      })

    multi =
      Multi.new()
      |> Multi.insert(:farrowing, Farrowing.changeset(%Farrowing{}, farrowing_attrs))
      |> Multi.update(
        :close_service,
        Service.close_changeset(service, %{
          "result" => "farrowing",
          "result_at" => farrowed_at
        })
      )
      |> insert_piglets(farm.id, sow, service.boar_id, pen_id, born_alive, farrowed_at)
      |> maybe_move_sow(farm.id, sow, pen_id, farrowed_at)
      |> update_sow_for_farrowing(sow, pen_id)
      |> audit_after(scope, "farrowing.created", :farrowing)

    case Repo.transaction(multi) do
      {:ok, %{farrowing: farrowing} = results} ->
        litter = Map.get(results, :litter_batch)
        {:ok, farrowing, litter}

      {:error, :farrowing, cs, _} ->
        {:error, cs}

      {:error, step, cs, _} ->
        {:error, {step, cs}}
    end
  end

  @doc """
  Records multiple farrowings atomically (batch entry from spreadsheet grid).

  Each entry is a map with `:service_id` plus the same farrowing attrs
  accepted by `record_farrowing/3` (`:farrowed_at`, `:born_alive`,
  `:stillborn`, `:mummified`, `:total_birth_weight_g`, `:pen_id`,
  `:notes`). Keys may be atoms or strings.

  Returns `{:ok, [farrowing, ...]}` on success,
  `{:error, {row_index, changeset_or_reason}}` on failure.
  Any failure rolls back the entire batch.
  """
  def record_batch_farrowings(%Scope{} = scope, entries)
      when is_list(entries) and entries != [] do
    Repo.transaction(fn ->
      entries
      |> Enum.with_index()
      |> Enum.reduce([], fn {entry, i}, acc ->
        attrs = stringify_keys(entry)
        service_id = to_int(attrs["service_id"])
        attrs = Map.delete(attrs, "service_id")

        service =
          case service_id && Repo.get(Service, service_id) do
            %Service{farm_id: fid} = s when fid == scope.farm.id -> s
            _ -> nil
          end

        cond do
          is_nil(service) ->
            Repo.rollback({i, :service_not_found})

          true ->
            case record_farrowing(scope, service, attrs) do
              {:ok, farrowing, _piglets} -> [farrowing | acc]
              {:error, reason} -> Repo.rollback({i, reason})
            end
        end
      end)
      |> Enum.reverse()
    end)
  end

  def record_batch_farrowings(_scope, []), do: {:error, :no_entries}

  defp insert_piglets(multi, _farm_id, _sow, _boar_id, _pen_id, 0, _farrowed_at), do: multi

  defp insert_piglets(multi, farm_id, sow, boar_id, pen_id, count, farrowed_at) do
    multi
    |> Multi.run(:litter_batch, fn _repo, %{farrowing: farrowing} ->
      Repo.insert(
        Animal.piglet_changeset(%Animal{}, %{
          "tracking_type" => "batch",
          "stage" => "piglet",
          "status" => "active",
          "quantity" => count,
          "dob" => farrowed_at,
          "dam_id" => sow.id,
          "sire_id" => boar_id,
          "farrowing_id" => farrowing.id,
          "farm_id" => farm_id
        })
      )
    end)
    |> maybe_place_litter_batch(farm_id, pen_id, farrowed_at)
  end

  defp maybe_place_litter_batch(multi, _farm_id, nil, _date), do: multi

  defp maybe_place_litter_batch(multi, farm_id, pen_id, farrowed_at) do
    placed_at = farrowed_at || Date.utc_today()

    multi
    |> Multi.run(:litter_placement, fn _repo, %{litter_batch: batch} ->
      Repo.insert(
        Placement.changeset(%Placement{}, %{
          animal_id: batch.id,
          pen_id: pen_id,
          quantity: batch.quantity,
          placed_at: placed_at
        })
      )
    end)
    |> Multi.run(:litter_movement, fn _repo, %{litter_batch: batch} ->
      Repo.insert(
        Movement.changeset(%Movement{}, %{
          "farm_id" => farm_id,
          "animal_id" => batch.id,
          "to_pen_id" => pen_id,
          "reason" => "placement",
          "quantity" => batch.quantity,
          "moved_at" => placed_at
        })
      )
    end)
  end

  defp update_sow_for_farrowing(multi, sow, pen_id) do
    changes = %{status: "lactating"}
    changes = if sow.stage != "sow", do: Map.put(changes, :stage, "sow"), else: changes

    changes =
      if pen_id && pen_id != sow.current_pen_id,
        do: Map.put(changes, :current_pen_id, pen_id),
        else: changes

    Multi.update(multi, :update_sow, Ecto.Changeset.change(sow, changes))
  end

  defp maybe_move_sow(multi, _farm_id, _sow, nil, _date), do: multi

  defp maybe_move_sow(multi, _farm_id, %{current_pen_id: cur}, pen_id, _date)
       when cur == pen_id,
       do: multi

  defp maybe_move_sow(multi, farm_id, sow, pen_id, farrowed_at) do
    reason = if is_nil(sow.current_pen_id), do: "placement", else: "pen_transfer"
    moved_at = farrowed_at || Date.utc_today()

    Multi.insert(
      multi,
      :sow_movement,
      Movement.changeset(%Movement{}, %{
        "farm_id" => farm_id,
        "animal_id" => sow.id,
        "from_pen_id" => sow.current_pen_id,
        "to_pen_id" => pen_id,
        "reason" => reason,
        "quantity" => 1,
        "moved_at" => moved_at
      })
    )
  end

  @doc """
  Lists farrowings for a farm, newest first.
  Supports optional filter: `sow_id`.
  """
  def list_farrowings(%Scope{farm: farm}, opts \\ []) do
    q =
      from(f in Farrowing,
        where: f.farm_id == ^farm.id and is_nil(f.deleted_at),
        order_by: [desc: f.farrowed_at, desc: f.id],
        preload: [:sow, [pen: :house], service: [:boar]]
      )

    q =
      case Keyword.get(opts, :sow_id) do
        nil -> q
        sow_id -> where(q, [f], f.sow_id == ^sow_id)
      end

    Repo.all(q)
  end

  @doc """
  Gets a farrowing by id, scoped to the farm.
  """
  def get_farrowing!(%Scope{farm: farm}, id) do
    Repo.one!(
      from(f in Farrowing,
        where: f.id == ^id and f.farm_id == ^farm.id and is_nil(f.deleted_at)
      )
    )
    |> Repo.preload([:sow, :pen, :weaning, :piglets, service: [:boar]])
  end

  @doc """
  Returns a changeset for tracking farrowing form changes.
  """
  def change_farrowing(%Farrowing{} = farrowing, attrs \\ %{}) do
    Farrowing.changeset(farrowing, attrs)
  end

  # ── Farrowing soft-delete ──────────────────────────────────────────

  @doc """
  Returns `true` if the farrowing may be soft-deleted.

  Blocked when:
    * already soft-deleted
    * a weaning row exists for the farrowing
    * the litter batch has downstream activity (piglets fostered,
      died, or transferred — detected by extra movement rows or a
      quantity change)
  """
  def farrowing_deletable?(%Scope{} = scope, %Farrowing{} = farrowing) do
    cond do
      not is_nil(farrowing.deleted_at) -> false
      weaning_exists?(farrowing) -> false
      not litter_activity_clean?(scope, farrowing) -> false
      true -> true
    end
  end

  defp weaning_exists?(%Farrowing{id: id}) do
    Repo.exists?(from w in Weaning, where: w.farrowing_id == ^id and is_nil(w.deleted_at))
  end

  # The litter is "clean" if:
  #   * no batch exists (born_alive was 0), OR
  #   * the batch has exactly the initial placement, its quantity still
  #     matches `born_alive`, and it has at most 1 movement row.
  defp litter_activity_clean?(%Scope{farm: farm}, %Farrowing{} = farrowing) do
    case Repo.one(
           from(a in Animal,
             where:
               a.farm_id == ^farm.id and
                 a.farrowing_id == ^farrowing.id and
                 a.tracking_type == "batch"
           )
         ) do
      nil ->
        true

      batch ->
        placement_count =
          Repo.aggregate(
            from(p in Placement, where: p.animal_id == ^batch.id),
            :count,
            :id
          )

        movement_count =
          Repo.aggregate(
            from(m in Movement, where: m.animal_id == ^batch.id),
            :count,
            :id
          )

        batch.quantity == farrowing.born_alive and
          batch.status == "active" and
          placement_count <= 1 and
          movement_count <= 1
    end
  end

  @doc """
  Soft-deletes a farrowing and reverses its side-effects atomically.

  Preconditions: see `farrowing_deletable?/2`.

  Cascade (in one transaction):
    * hard-delete the litter batch (animal), its placement, its
      placement-movement, and the sow's farrowing pen-transfer movement
    * revert `sow.current_pen_id` to the pre-farrowing pen (read from
      the sow movement's `from_pen_id`); revert `sow.status` to
      `"served"`
    * reopen the service: `result = nil`, `result_at = nil`
    * stamp `deleted_at` / `deleted_by_id` on the farrowing row
    * write `farrowing.deleted` audit with a row snapshot

  Error reasons: `:already_deleted`, `:farrowing_has_weaning`,
  `:farrowing_has_activity`.
  """
  def delete_farrowing(%Scope{} = scope, %Farrowing{} = farrowing) do
    cond do
      not is_nil(farrowing.deleted_at) ->
        {:error, :already_deleted}

      weaning_exists?(farrowing) ->
        {:error, :farrowing_has_weaning}

      not litter_activity_clean?(scope, farrowing) ->
        {:error, :farrowing_has_activity}

      true ->
        do_delete_farrowing(scope, farrowing)
    end
  end

  defp do_delete_farrowing(scope, farrowing) do
    now = DateTime.utc_now(:second)
    user_id = scope.user && scope.user.id

    multi =
      Multi.new()
      |> Multi.run(:load, fn repo, _ ->
        batch =
          repo.one(
            from(a in Animal,
              where:
                a.farm_id == ^scope.farm.id and
                  a.farrowing_id == ^farrowing.id and
                  a.tracking_type == "batch"
            )
          )

        sow_move =
          repo.one(
            from(m in Movement,
              where:
                m.farm_id == ^scope.farm.id and
                  m.animal_id == ^farrowing.sow_id and
                  m.to_pen_id == ^farrowing.pen_id and
                  m.moved_at == ^farrowing.farrowed_at and
                  m.reason in ["pen_transfer", "placement"],
              order_by: [desc: m.id],
              limit: 1
            )
          )

        {:ok, %{batch: batch, sow_move: sow_move}}
      end)
      |> Multi.run(:delete_placement, fn repo, %{load: %{batch: batch}} ->
        if batch do
          {count, _} =
            repo.delete_all(from p in Placement, where: p.animal_id == ^batch.id)

          {:ok, count}
        else
          {:ok, 0}
        end
      end)
      |> Multi.run(:delete_batch_movements, fn repo, %{load: %{batch: batch}} ->
        if batch do
          {count, _} =
            repo.delete_all(from m in Movement, where: m.animal_id == ^batch.id)

          {:ok, count}
        else
          {:ok, 0}
        end
      end)
      |> Multi.run(:delete_batch, fn repo, %{load: %{batch: batch}} ->
        if batch, do: repo.delete(batch), else: {:ok, nil}
      end)
      |> Multi.run(:delete_sow_movement, fn repo, %{load: %{sow_move: m}} ->
        if m, do: repo.delete(m), else: {:ok, nil}
      end)
      |> Multi.run(:revert_sow, fn repo, %{load: %{sow_move: sow_move}} ->
        sow = repo.get!(Animal, farrowing.sow_id)
        prior_pen_id = if sow_move, do: sow_move.from_pen_id, else: sow.current_pen_id

        changes = %{current_pen_id: prior_pen_id}

        changes =
          if sow.status == "lactating",
            do: Map.put(changes, :status, "served"),
            else: changes

        sow |> Ecto.Changeset.change(changes) |> repo.update()
      end)
      |> Multi.run(:reopen_service, fn repo, _ ->
        service = repo.get!(Service, farrowing.service_id)
        service |> Service.reopen_changeset() |> repo.update()
      end)
      |> Multi.update(
        :farrowing,
        Ecto.Changeset.change(farrowing, %{deleted_at: now, deleted_by_id: user_id})
      )
      |> Audit.log!(scope, "farrowing.deleted",
        entity_type: :farrowing,
        entity_id: farrowing.id,
        changes: %{snapshot: farrowing_snapshot(farrowing)}
      )

    case Repo.transaction(multi) do
      {:ok, %{farrowing: f}} -> {:ok, f}
      {:error, step, reason, _} -> {:error, {step, reason}}
    end
  end

  @doc """
  Restores a soft-deleted farrowing, re-running its side effects.

  Rejects if the service has been closed with a different result since
  the delete, or a weaning somehow exists. Re-creates the litter batch,
  placement, movements, re-closes the service with `farrowing`, and
  reapplies sow status/pen.

  Error reasons: `:not_deleted`, `:service_reclosed`,
  `:conflicting_weaning`.
  """
  def restore_farrowing(%Scope{} = scope, %Farrowing{} = farrowing) do
    cond do
      is_nil(farrowing.deleted_at) ->
        {:error, :not_deleted}

      true ->
        service = Repo.get!(Service, farrowing.service_id)

        cond do
          not is_nil(service.result) -> {:error, :service_reclosed}
          weaning_exists?(farrowing) -> {:error, :conflicting_weaning}
          true -> do_restore_farrowing(scope, farrowing, service)
        end
    end
  end

  defp do_restore_farrowing(scope, farrowing, service) do
    farm = scope.farm
    sow = Repo.get!(Animal, farrowing.sow_id)
    born_alive = farrowing.born_alive || 0

    multi =
      Multi.new()
      |> Multi.update(
        :farrowing,
        Ecto.Changeset.change(farrowing, %{deleted_at: nil, deleted_by_id: nil})
      )
      |> Multi.update(
        :close_service,
        Service.close_changeset(service, %{
          "result" => "farrowing",
          "result_at" => farrowing.farrowed_at
        })
      )
      |> insert_piglets(
        farm.id,
        sow,
        service.boar_id,
        farrowing.pen_id,
        born_alive,
        farrowing.farrowed_at
      )
      |> maybe_move_sow(farm.id, sow, farrowing.pen_id, farrowing.farrowed_at)
      |> update_sow_for_farrowing(sow, farrowing.pen_id)
      |> Audit.log!(scope, "farrowing.restored",
        entity_type: :farrowing,
        entity_id: farrowing.id,
        changes: %{}
      )

    case Repo.transaction(multi) do
      {:ok, %{farrowing: f}} -> {:ok, f}
      {:error, step, reason, _} -> {:error, {step, reason}}
    end
  end

  @doc """
  Lists soft-deleted farrowings for the farm, newest-deleted first.

  Options: `:limit` (default 50).
  """
  def list_deleted_farrowings(%Scope{farm: farm}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(f in Farrowing,
      where: f.farm_id == ^farm.id and not is_nil(f.deleted_at),
      order_by: [desc: f.deleted_at, desc: f.id],
      limit: ^limit,
      preload: [:sow, [pen: :house], :deleted_by, service: [:boar]]
    )
    |> Repo.all()
  end

  @doc """
  Fetches a soft-deleted farrowing by id. Raises if not found or not
  deleted.
  """
  def get_deleted_farrowing!(%Scope{farm: farm}, id) do
    Repo.one!(
      from(f in Farrowing,
        where: f.id == ^id and f.farm_id == ^farm.id and not is_nil(f.deleted_at),
        preload: [:sow, [pen: :house], :deleted_by, service: [:boar]]
      )
    )
  end

  defp farrowing_snapshot(%Farrowing{} = f) do
    %{
      id: f.id,
      service_id: f.service_id,
      sow_id: f.sow_id,
      pen_id: f.pen_id,
      farrowed_at: f.farrowed_at && Date.to_iso8601(f.farrowed_at),
      born_alive: f.born_alive,
      stillborn: f.stillborn,
      mummified: f.mummified,
      total_birth_weight_g: f.total_birth_weight_g,
      notes: f.notes
    }
  end

  @doc """
  Returns the parity (number of farrowings) for a sow.
  """
  def parity(%Scope{farm: farm}, sow_id) do
    Repo.aggregate(
      from(f in Farrowing,
        where: f.farm_id == ^farm.id and f.sow_id == ^sow_id and is_nil(f.deleted_at)
      ),
      :count
    )
  end

  @doc """
  Lists farrowings that have not yet been weaned (sow is lactating).

  Options:
    * `:search` — case-insensitive ear-tag prefix (matches sow ear tag)
    * `:age_bucket` — `"all"` (default) | `"week1"` (0-6d) |
      `"week2"` (7-13d) | `"week3"` (14-20d) | `"wean_due"` (21d+)
    * `:pen_id` — restrict to farrowings in a single pen
    * `:limit` — defaults to 25; pass `:all` to disable pagination
    * `:offset` — defaults to 0
  """
  def list_lactating_sows(scope, opts \\ [])

  def list_lactating_sows(%Scope{farm: farm}, opts) do
    farm
    |> lactating_query(opts)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc """
  Counts lactating farrowings matching the same filter opts as
  `list_lactating_sows/2` (ignores `:limit`/`:offset`).
  """
  def count_lactating_sows(%Scope{farm: farm}, opts \\ []) do
    farm |> lactating_query(opts) |> exclude(:order_by) |> Repo.aggregate(:count, :id)
  end

  defp lactating_query(farm, opts) do
    today = Date.utc_today()
    search = opts |> Keyword.get(:search) |> normalize_search()
    age_bucket = Keyword.get(opts, :age_bucket, "all")
    pen_id = Keyword.get(opts, :pen_id)

    q =
      from(f in Farrowing,
        join: sow in assoc(f, :sow),
        left_join: w in Weaning,
        on: w.farrowing_id == f.id and is_nil(w.deleted_at),
        where: f.farm_id == ^farm.id and is_nil(w.id) and is_nil(f.deleted_at),
        order_by: [asc: f.farrowed_at],
        preload: [:sow, [pen: :house], service: [:boar]]
      )

    q =
      if search do
        like = "#{search}%"
        from [f, sow, w] in q, where: ilike(sow.ear_tag, ^like)
      else
        q
      end

    q =
      case parse_pen_id(pen_id) do
        nil -> q
        id -> from f in q, where: f.pen_id == ^id
      end

    case age_bucket do
      "week1" ->
        from f in q, where: f.farrowed_at > ^Date.add(today, -7)

      "week2" ->
        from f in q,
          where: f.farrowed_at <= ^Date.add(today, -7) and f.farrowed_at > ^Date.add(today, -14)

      "week3" ->
        from f in q,
          where: f.farrowed_at <= ^Date.add(today, -14) and f.farrowed_at > ^Date.add(today, -21)

      "wean_due" ->
        from f in q, where: f.farrowed_at <= ^Date.add(today, -21)

      _ ->
        q
    end
  end

  defp apply_pagination(query, opts) do
    case Keyword.get(opts, :limit, 25) do
      :all ->
        query

      limit when is_integer(limit) and limit > 0 ->
        offset = Keyword.get(opts, :offset, 0)
        from q in query, limit: ^limit, offset: ^offset

      _ ->
        query
    end
  end

  defp normalize_search(nil), do: nil

  defp normalize_search(term) when is_binary(term) do
    case String.trim(term) do
      "" -> nil
      t -> t
    end
  end

  defp normalize_search(_), do: nil

  defp parse_pen_id(nil), do: nil
  defp parse_pen_id(""), do: nil
  defp parse_pen_id(id) when is_integer(id), do: id

  defp parse_pen_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  # ── Weanings ──────────────────────────────────────────────────────

  @doc """
  Records a weaning event for a farrowed litter.

  In one atomic transaction:
  1. Inserts the weaning row
  2. For `weaned_count >= 1`:
     - Updates the litter batch: `stage → "weaner"`, `quantity → weaned_count`
     - If `destination_pen_id` is given, closes old placement and moves batch
  3. For `weaned_count == 0`:
     - Marks the litter batch as `status = "deceased"`, `quantity = 0`
  4. Audits the weaning

  Returns `{:ok, weaning, batch}` on success.
  The third element is the updated batch animal, or nil if no litter exists.
  """
  def record_weaning(%Scope{} = scope, %Farrowing{} = farrowing, attrs) do
    if Repo.one(
         from w in Weaning,
           where: w.farrowing_id == ^farrowing.id and is_nil(w.deleted_at),
           limit: 1
       ) do
      {:error, :already_weaned}
    else
      do_record_weaning(scope, farrowing, stringify_keys(attrs))
    end
  end

  defp do_record_weaning(scope, farrowing, attrs) do
    farm = scope.farm
    weaned_count = to_int(attrs["weaned_count"]) || 0
    dest_pen_id = to_int(attrs["destination_pen_id"])
    weaned_at = attrs["weaned_at"]
    sow = Repo.get!(Animal, farrowing.sow_id)

    weaning_attrs =
      attrs
      |> Map.merge(%{
        "farm_id" => farm.id,
        "farrowing_id" => farrowing.id
      })

    multi =
      Multi.new()
      |> Multi.insert(:weaning, Weaning.changeset(%Weaning{}, weaning_attrs))
      |> consolidate_piglets(farm.id, farrowing, sow, weaned_count, dest_pen_id, weaned_at)
      |> update_sow_after_weaning(sow)
      |> audit_after(scope, "weaning.created", :weaning)

    case Repo.transaction(multi) do
      {:ok, %{weaning: weaning} = results} ->
        batch = Map.get(results, :batch)
        {:ok, weaning, batch}

      {:error, :weaning, cs, _} ->
        {:error, cs}

      {:error, step, cs, _} ->
        {:error, {step, cs}}
    end
  end

  # weaned_count >= 1: promote litter batch to weaner, update quantity
  defp consolidate_piglets(multi, farm_id, farrowing, _sow, count, dest_pen_id, weaned_at)
       when count >= 1 do
    multi
    |> Multi.run(:batch, fn repo, _ ->
      case repo.one(
             from(a in Animal,
               where:
                 a.farrowing_id == ^farrowing.id and
                   a.tracking_type == "batch" and
                   a.status == "active"
             )
           ) do
        nil ->
          {:ok, nil}

        batch ->
          batch
          |> Ecto.Changeset.change(%{stage: "weaner", quantity: count})
          |> repo.update()
      end
    end)
    |> maybe_move_weaned_batch(farm_id, dest_pen_id, weaned_at)
  end

  # weaned_count == 0: all piglets died, mark batch as deceased
  defp consolidate_piglets(multi, _farm_id, farrowing, _sow, 0, _dest_pen_id, _weaned_at) do
    Multi.run(multi, :batch, fn repo, _ ->
      case repo.one(
             from(a in Animal,
               where:
                 a.farrowing_id == ^farrowing.id and
                   a.tracking_type == "batch"
             )
           ) do
        nil ->
          {:ok, nil}

        batch ->
          batch
          |> Ecto.Changeset.change(%{status: "deceased", quantity: 0})
          |> repo.update()
      end
    end)
  end

  defp maybe_move_weaned_batch(multi, _farm_id, nil, _weaned_at), do: multi

  defp maybe_move_weaned_batch(multi, farm_id, dest_pen_id, weaned_at) do
    moved = weaned_at || Date.utc_today()

    multi
    |> Multi.run(:close_old_placement, fn repo, %{batch: batch} ->
      case batch do
        nil ->
          {:ok, nil}

        batch ->
          now = DateTime.truncate(DateTime.utc_now(), :second)

          repo.update_all(
            from(p in Placement,
              where: p.animal_id == ^batch.id and is_nil(p.removed_at)
            ),
            set: [removed_at: moved, updated_at: now]
          )

          {:ok, :closed}
      end
    end)
    |> Multi.run(:wean_placement, fn repo, %{batch: batch} ->
      case batch do
        nil ->
          {:ok, nil}

        batch ->
          repo.insert(
            Placement.changeset(%Placement{}, %{
              animal_id: batch.id,
              pen_id: dest_pen_id,
              quantity: batch.quantity,
              placed_at: moved
            })
          )
      end
    end)
    |> Multi.run(:wean_movement, fn repo, %{batch: batch} ->
      case batch do
        nil ->
          {:ok, nil}

        batch ->
          repo.insert(
            Movement.changeset(%Movement{}, %{
              "farm_id" => farm_id,
              "animal_id" => batch.id,
              "to_pen_id" => dest_pen_id,
              "reason" => "pen_transfer",
              "quantity" => batch.quantity,
              "moved_at" => moved
            })
          )
      end
    end)
  end

  @doc """
  Returns a changeset for tracking weaning form changes.
  """
  def change_weaning(%Weaning{} = weaning, attrs \\ %{}) do
    Weaning.changeset(weaning, attrs)
  end

  @doc """
  Lists recent (non-deleted) weanings for the farm, newest first.

  Options: `:limit` (default 50), `:search` (sow ear tag prefix).
  """
  def list_recent_weanings(%Scope{farm: farm}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    search = opts |> Keyword.get(:search) |> normalize_search()

    q =
      from(w in Weaning,
        join: f in assoc(w, :farrowing),
        join: sow in assoc(f, :sow),
        where: w.farm_id == ^farm.id and is_nil(w.deleted_at),
        order_by: [desc: w.weaned_at, desc: w.id],
        limit: ^limit,
        preload: [[destination_pen: :house], farrowing: [:sow, [pen: :house]]]
      )

    q =
      if search do
        like = "#{search}%"
        from [w, f, sow] in q, where: ilike(sow.ear_tag, ^like)
      else
        q
      end

    Repo.all(q)
  end

  @doc """
  Gets a weaning by id, scoped to the farm. Excludes soft-deleted rows.
  """
  def get_weaning!(%Scope{farm: farm}, id) do
    Repo.one!(
      from(w in Weaning,
        where: w.id == ^id and w.farm_id == ^farm.id and is_nil(w.deleted_at),
        preload: [:destination_pen, farrowing: [:sow, :pen]]
      )
    )
  end

  # ── Weaning soft-delete ────────────────────────────────────────────

  @doc """
  Returns `true` if the weaning may be soft-deleted.

  Blocked when:
    * already soft-deleted
    * the litter batch has downstream activity after the weaning —
      i.e., extra movements after `weaned_at`, or the batch's state
      no longer matches what the weaning set it to.
  """
  def weaning_deletable?(%Scope{} = scope, %Weaning{} = w) do
    cond do
      not is_nil(w.deleted_at) -> false
      not post_weaning_clean?(scope, w) -> false
      true -> true
    end
  end

  defp post_weaning_clean?(%Scope{farm: farm}, %Weaning{} = w) do
    farrowing = Repo.get!(Farrowing, w.farrowing_id)

    case Repo.one(
           from(a in Animal,
             where:
               a.farm_id == ^farm.id and
                 a.farrowing_id == ^farrowing.id and
                 a.tracking_type == "batch"
           )
         ) do
      nil ->
        # No batch (born_alive was 0) — nothing downstream to worry about.
        true

      batch ->
        later_moves =
          Repo.aggregate(
            from(m in Movement,
              where: m.animal_id == ^batch.id and m.moved_at > ^w.weaned_at
            ),
            :count,
            :id
          )

        {expected_stage, expected_status, expected_qty} =
          if (w.weaned_count || 0) >= 1,
            do: {"weaner", "active", w.weaned_count},
            else: {batch.stage, "deceased", 0}

        later_moves == 0 and
          batch.quantity == expected_qty and
          batch.status == expected_status and
          batch.stage == expected_stage
    end
  end

  @doc """
  Soft-deletes a weaning and reverses its side-effects atomically.

  Cascade (in one transaction):
    * revert the litter batch to its pre-weaning state
      (stage: `"piglet"`, status: `"active"`, quantity: `born_alive`)
    * if a destination pen was used: delete the post-weaning
      placement + movement, and reopen the pre-weaning placement
      (clear its `removed_at`)
    * revert sow status `"dry"` → `"lactating"` (if applicable)
    * stamp `deleted_at` / `deleted_by_id` on the weaning row
    * write `weaning.deleted` audit with a row snapshot

  Error reasons: `:already_deleted`, `:weaning_has_activity`.
  """
  def delete_weaning(%Scope{} = scope, %Weaning{} = w) do
    cond do
      not is_nil(w.deleted_at) ->
        {:error, :already_deleted}

      not post_weaning_clean?(scope, w) ->
        {:error, :weaning_has_activity}

      true ->
        do_delete_weaning(scope, w)
    end
  end

  defp do_delete_weaning(scope, %Weaning{} = w) do
    now = DateTime.utc_now(:second)
    user_id = scope.user && scope.user.id
    farrowing = Repo.get!(Farrowing, w.farrowing_id)
    born_alive = farrowing.born_alive || 0

    multi =
      Multi.new()
      |> Multi.run(:load, fn repo, _ ->
        batch =
          repo.one(
            from(a in Animal,
              where:
                a.farm_id == ^scope.farm.id and
                  a.farrowing_id == ^farrowing.id and
                  a.tracking_type == "batch"
            )
          )

        {:ok, %{batch: batch}}
      end)
      |> Multi.run(:delete_wean_movement, fn repo, %{load: %{batch: batch}} ->
        if batch && w.destination_pen_id do
          {count, _} =
            repo.delete_all(
              from(m in Movement,
                where:
                  m.animal_id == ^batch.id and
                    m.moved_at == ^w.weaned_at and
                    m.to_pen_id == ^w.destination_pen_id and
                    m.reason == "pen_transfer"
              )
            )

          {:ok, count}
        else
          {:ok, 0}
        end
      end)
      |> Multi.run(:delete_wean_placement, fn repo, %{load: %{batch: batch}} ->
        if batch && w.destination_pen_id do
          {count, _} =
            repo.delete_all(
              from(p in Placement,
                where:
                  p.animal_id == ^batch.id and
                    p.pen_id == ^w.destination_pen_id and
                    p.placed_at == ^w.weaned_at
              )
            )

          {:ok, count}
        else
          {:ok, 0}
        end
      end)
      |> Multi.run(:reopen_prior_placement, fn repo, %{load: %{batch: batch}} ->
        if batch && w.destination_pen_id do
          ts = DateTime.truncate(DateTime.utc_now(), :second)

          {count, _} =
            repo.update_all(
              from(p in Placement,
                where:
                  p.animal_id == ^batch.id and
                    p.removed_at == ^w.weaned_at
              ),
              set: [removed_at: nil, updated_at: ts]
            )

          {:ok, count}
        else
          {:ok, 0}
        end
      end)
      |> Multi.run(:revert_batch, fn repo, %{load: %{batch: batch}} ->
        if batch do
          batch
          |> Ecto.Changeset.change(%{
            stage: "piglet",
            status: "active",
            quantity: born_alive
          })
          |> repo.update()
        else
          {:ok, nil}
        end
      end)
      |> Multi.run(:revert_sow, fn repo, _ ->
        sow = repo.get!(Animal, farrowing.sow_id)

        if sow.status == "dry" do
          sow |> Ecto.Changeset.change(%{status: "lactating"}) |> repo.update()
        else
          {:ok, sow}
        end
      end)
      |> Multi.update(
        :weaning,
        Ecto.Changeset.change(w, %{deleted_at: now, deleted_by_id: user_id})
      )
      |> Audit.log!(scope, "weaning.deleted",
        entity_type: :weaning,
        entity_id: w.id,
        changes: %{snapshot: weaning_snapshot(w)}
      )

    case Repo.transaction(multi) do
      {:ok, %{weaning: wn}} -> {:ok, wn}
      {:error, step, reason, _} -> {:error, {step, reason}}
    end
  end

  @doc """
  Restores a soft-deleted weaning, re-running its side effects.

  Rejects if a non-deleted weaning already exists for the same
  farrowing, or the farrowing itself has been soft-deleted.

  Error reasons: `:not_deleted`, `:conflicting_weaning`,
  `:farrowing_deleted`.
  """
  def restore_weaning(%Scope{} = scope, %Weaning{} = w) do
    cond do
      is_nil(w.deleted_at) ->
        {:error, :not_deleted}

      true ->
        farrowing = Repo.get!(Farrowing, w.farrowing_id)

        cond do
          not is_nil(farrowing.deleted_at) ->
            {:error, :farrowing_deleted}

          weaning_exists?(farrowing) ->
            {:error, :conflicting_weaning}

          true ->
            do_restore_weaning(scope, w, farrowing)
        end
    end
  end

  defp do_restore_weaning(scope, %Weaning{} = w, %Farrowing{} = farrowing) do
    farm = scope.farm
    sow = Repo.get!(Animal, farrowing.sow_id)
    weaned_count = w.weaned_count || 0

    multi =
      Multi.new()
      |> Multi.update(
        :weaning,
        Ecto.Changeset.change(w, %{deleted_at: nil, deleted_by_id: nil})
      )
      |> consolidate_piglets(
        farm.id,
        farrowing,
        sow,
        weaned_count,
        w.destination_pen_id,
        w.weaned_at
      )
      |> update_sow_after_weaning(sow)
      |> Audit.log!(scope, "weaning.restored",
        entity_type: :weaning,
        entity_id: w.id,
        changes: %{}
      )

    case Repo.transaction(multi) do
      {:ok, %{weaning: wn}} -> {:ok, wn}
      {:error, step, reason, _} -> {:error, {step, reason}}
    end
  end

  @doc """
  Lists soft-deleted weanings for the farm, newest-deleted first.
  """
  def list_deleted_weanings(%Scope{farm: farm}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(w in Weaning,
      where: w.farm_id == ^farm.id and not is_nil(w.deleted_at),
      order_by: [desc: w.deleted_at, desc: w.id],
      limit: ^limit,
      preload: [
        :deleted_by,
        [destination_pen: :house],
        farrowing: [:sow, [pen: :house]]
      ]
    )
    |> Repo.all()
  end

  @doc """
  Fetches a soft-deleted weaning by id. Raises if not found or not
  deleted.
  """
  def get_deleted_weaning!(%Scope{farm: farm}, id) do
    Repo.one!(
      from(w in Weaning,
        where: w.id == ^id and w.farm_id == ^farm.id and not is_nil(w.deleted_at),
        preload: [
          :deleted_by,
          [destination_pen: :house],
          farrowing: [:sow, [pen: :house]]
        ]
      )
    )
  end

  defp weaning_snapshot(%Weaning{} = w) do
    %{
      id: w.id,
      farrowing_id: w.farrowing_id,
      weaned_at: w.weaned_at && Date.to_iso8601(w.weaned_at),
      weaned_count: w.weaned_count,
      avg_wean_weight_g: w.avg_wean_weight_g,
      destination_pen_id: w.destination_pen_id,
      notes: w.notes
    }
  end

  @doc """
  Returns the count of surviving piglets for a farrowing.
  Reads the litter batch's current quantity.
  """
  def surviving_piglet_count(%Farrowing{} = farrowing) do
    case Repo.one(
           from(a in Animal,
             where:
               a.farrowing_id == ^farrowing.id and
                 a.tracking_type == "batch" and
                 a.status == "active"
           )
         ) do
      nil -> 0
      batch -> batch.quantity
    end
  end

  @doc """
  Lists all piglets (any status) for a farrowing.
  """
  def list_litter(%Scope{farm: farm}, %Farrowing{} = farrowing) do
    Repo.all(
      from(a in Animal,
        where: a.farm_id == ^farm.id and a.farrowing_id == ^farrowing.id,
        order_by: [asc: a.id],
        preload: [:current_pen]
      )
    )
  end

  # ── Sow status helpers ─────────────────────────────────────────────

  defp update_sow_status(multi, sow_id, new_status) do
    sow_id = to_int(sow_id)

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, :update_sow_status, fn _repo, _ ->
        sow = Repo.get!(Animal, sow_id)
        sow |> Ecto.Changeset.change(%{status: new_status}) |> Repo.update()
      end)
    end
  end

  defp update_sow_status_keyed(multi, sow_id, new_status, i) do
    sow_id = to_int(sow_id)

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, {:update_sow_status, i}, fn _repo, _ ->
        sow = Repo.get!(Animal, sow_id)
        sow |> Ecto.Changeset.change(%{status: new_status}) |> Repo.update()
      end)
    end
  end

  # After weaning piglets the sow moves to "dry" — resting before next heat.
  # Only transition from "lactating" (the expected source state); leave
  # already-departed or otherwise-transitioned sows untouched.
  defp update_sow_after_weaning(multi, sow) do
    if sow.status == "lactating" do
      Multi.update(multi, :sow_dry, Ecto.Changeset.change(sow, %{status: "dry"}))
    else
      multi
    end
  end

  # ── Private helpers ────────────────────────────────────────────────

  defp maybe_filter_service(query, :sow_id, nil), do: query
  defp maybe_filter_service(query, :sow_id, id), do: where(query, [s], s.sow_id == ^id)

  defp maybe_filter_service(query, :result, nil), do: query
  defp maybe_filter_service(query, :result, :open), do: where(query, [s], is_nil(s.result))

  defp maybe_filter_service(query, :result, val),
    do: where(query, [s], s.result == ^to_string(val))

  defp audit_after(multi, scope, action, key) do
    Multi.run(multi, {:audit, action}, fn _repo, changes ->
      row = Map.fetch!(changes, key)

      Audit.log_now!(scope, action,
        entity_type: key,
        entity_id: row.id
      )

      {:ok, :logged}
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp to_int(nil), do: nil
  defp to_int(""), do: nil
  defp to_int(i) when is_integer(i), do: i

  defp to_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, ""} -> i
      _ -> nil
    end
  end
end
