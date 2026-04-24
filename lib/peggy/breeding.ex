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
  alias Peggy.Breeding.{Service, Farrowing, Weaning, LitterEvent}
  alias Peggy.Animals.Movement

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
      |> audit_after(scope, "service.created", :service, &service_audit_data/1)

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
        |> audit_after_keyed(scope, "service.created", {:service, i}, i, &service_audit_data/1)
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
  Batch variant of `record_service_with_backfill/2`.

  Each entry is a map like the single-row back-fill input:
    * `:sow_id` — an existing sow id, or
    * `:sow_ear_tag` + optional `:backfill_sow` map for inferred sows
    * `:service_type`, `:served_at`, `:boar_id`, `:notes`

  Each entry may carry an optional `:pen_id` — inferred sows are placed
  in that pen (Movement + `current_pen_id`); existing sows are
  transferred when the pen differs from their `current_pen_id`
  (Movement `reason: "pen_transfer"`), or placed when they have no
  current pen.

  Returns `{:ok, [service, ...]}` or
  `{:error, {row_index, reason}}` where reason can be
  `{:similar_tag, [tag, ...]}`, `:sow_not_found`, `:duplicate_ear_tag`,
  or an `Ecto.Changeset`. Any failure rolls back the entire batch.
  """
  def record_batch_services_with_backfill(%Scope{}, []), do: {:error, :no_entries}

  def record_batch_services_with_backfill(%Scope{} = scope, entries)
      when is_list(entries) do
    case classify_batch_entries(scope, entries) do
      {:ok, classified} ->
        run_batch_backfill_multi(scope, classified)

      {:error, _} = err ->
        err
    end
  end

  # Per-row classification: resolves existing sows, detects unknown tags
  # needing back-fill, blocks on similar tags, and rejects duplicate new
  # tags within the grid.
  defp classify_batch_entries(scope, entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {entry, i}, {:ok, acc, seen_new} ->
      case classify_one(scope, entry, seen_new) do
        {:ok, :existing, attrs} ->
          {:cont, {:ok, [{i, :existing, attrs} | acc], seen_new}}

        {:ok, :inferred, ear_tag, backfill, attrs} ->
          {:cont,
           {:ok, [{i, :inferred, ear_tag, backfill, attrs} | acc], MapSet.put(seen_new, ear_tag)}}

        {:error, reason} ->
          {:halt, {:error, {i, reason}}}
      end
    end)
    |> case do
      {:ok, acc, _seen} -> {:ok, Enum.reverse(acc)}
      {:error, _} = err -> err
    end
  end

  defp classify_one(scope, entry, seen_new) do
    attrs = entry |> stringify_keys() |> Map.put("farm_id", scope.farm.id)
    sow_id = to_int(attrs["sow_id"])
    ear_tag = attrs["sow_ear_tag"]

    cond do
      not is_nil(sow_id) ->
        {:ok, :existing, Map.delete(attrs, "sow_ear_tag")}

      is_nil(ear_tag) or ear_tag == "" ->
        {:error, :sow_not_found}

      true ->
        case Animals.find_by_ear_tag(scope, ear_tag) do
          %Animal{id: id} ->
            attrs =
              attrs
              |> Map.put("sow_id", id)
              |> Map.delete("sow_ear_tag")
              |> Map.delete("backfill_sow")

            {:ok, :existing, attrs}

          nil ->
            classify_new_tag(scope, ear_tag, attrs, seen_new)
        end
    end
  end

  defp classify_new_tag(scope, ear_tag, attrs, seen_new) do
    backfill = Map.get(attrs, "backfill_sow")

    force? =
      truthy?(backfill && (Map.get(backfill, :force_create) || Map.get(backfill, "force_create")))

    cond do
      MapSet.member?(seen_new, ear_tag) ->
        {:error, :duplicate_ear_tag}

      true ->
        similars = Animals.similar_ear_tags(scope, ear_tag)

        cond do
          similars != [] and not force? ->
            {:error, {:similar_tag, similars}}

          is_nil(backfill) ->
            {:error, :sow_not_found}

          true ->
            {:ok, :inferred, ear_tag, backfill,
             attrs |> Map.delete("sow_ear_tag") |> Map.delete("backfill_sow")}
        end
    end
  end

  defp run_batch_backfill_multi(scope, classified) do
    farm = scope.farm

    multi =
      Enum.reduce(classified, Multi.new(), fn row, m ->
        case row do
          {i, :existing, attrs} ->
            pen_id = to_int(attrs["pen_id"])
            attrs = Map.delete(attrs, "pen_id")
            served_at = parse_date(attrs["served_at"]) || Date.utc_today()

            m
            |> ensure_sow_serviceable_keyed(scope, attrs, i)
            |> auto_close_prior_service_keyed(scope, attrs, i)
            |> Multi.insert({:service, i}, Service.changeset(%Service{}, attrs))
            |> update_sow_status_keyed(attrs["sow_id"], "served", i)
            |> maybe_move_existing_sow_keyed(farm.id, attrs["sow_id"], pen_id, served_at, i)
            |> audit_after_keyed(
              scope,
              "service.created",
              {:service, i},
              i,
              &service_audit_data/1
            )

          {i, :inferred, ear_tag, backfill, attrs} ->
            pen_id = to_int(attrs["pen_id"])
            attrs = Map.delete(attrs, "pen_id")
            served_at = parse_date(attrs["served_at"]) || Date.utc_today()
            sow_cs = build_inferred_sow_changeset(farm, ear_tag, backfill, attrs)

            m
            |> Multi.insert({:sow, i}, sow_cs)
            |> Multi.insert({:sow_audit, i}, fn changes ->
              inferred_sow_audit(scope, Map.fetch!(changes, {:sow, i}))
            end)
            |> Multi.update({:sow_with_origin, i}, fn changes ->
              sow = Map.fetch!(changes, {:sow, i})
              audit = Map.fetch!(changes, {:sow_audit, i})
              Ecto.Changeset.change(sow, origin_audit_id: audit.id)
            end)
            |> Multi.insert({:service, i}, fn changes ->
              sow = Map.fetch!(changes, {:sow_with_origin, i})
              Service.changeset(%Service{}, Map.put(attrs, "sow_id", sow.id))
            end)
            |> Multi.run({:sow_served, i}, fn _repo, changes ->
              sow = Map.fetch!(changes, {:sow_with_origin, i})
              changes_map = %{status: "served"}

              changes_map =
                if pen_id,
                  do: Map.put(changes_map, :current_pen_id, pen_id),
                  else: changes_map

              sow |> Ecto.Changeset.change(changes_map) |> Repo.update()
            end)
            |> maybe_insert_inferred_placement_keyed(farm.id, pen_id, served_at, i)
            |> audit_after_keyed(
              scope,
              "service.created",
              {:service, i},
              i,
              &service_audit_data/1
            )
        end
      end)

    case Repo.transaction(multi) do
      {:ok, changes} ->
        services =
          0..(length(classified) - 1)
          |> Enum.map(&Map.fetch!(changes, {:service, &1}))

        {:ok, services}

      {:error, {:service, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, {:ensure_serviceable, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, {:sow, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, {:sow_movement, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, _op, reason, _} ->
        {:error, reason}
    end
  end

  defp maybe_insert_inferred_placement_keyed(multi, _farm_id, nil, _moved_at, _i), do: multi

  defp maybe_insert_inferred_placement_keyed(multi, farm_id, pen_id, moved_at, i) do
    Multi.insert(multi, {:sow_placement, i}, fn changes ->
      sow = Map.fetch!(changes, {:sow_with_origin, i})

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

  # For existing-sow rows in batch: insert Movement + update sow's
  # current_pen_id when pen_id is given and differs. No-op when
  # pen_id is nil or equals the sow's current pen.
  defp maybe_move_existing_sow_keyed(multi, _farm_id, _sow_id, nil, _moved_at, _i), do: multi

  defp maybe_move_existing_sow_keyed(multi, farm_id, sow_id, pen_id, moved_at, i)
       when is_integer(sow_id) and is_integer(pen_id) do
    multi
    |> Multi.run({:sow_move_decision, i}, fn repo, _changes ->
      case repo.get(Animal, sow_id) do
        nil -> {:ok, :skip}
        %Animal{current_pen_id: cur} when cur == pen_id -> {:ok, :skip}
        %Animal{} = sow -> {:ok, {:move, sow}}
      end
    end)
    |> Multi.run({:sow_movement, i}, fn repo, changes ->
      case Map.fetch!(changes, {:sow_move_decision, i}) do
        :skip ->
          {:ok, nil}

        {:move, sow} ->
          reason = if is_nil(sow.current_pen_id), do: "placement", else: "pen_transfer"

          %Movement{}
          |> Movement.changeset(%{
            "farm_id" => farm_id,
            "animal_id" => sow.id,
            "from_pen_id" => sow.current_pen_id,
            "to_pen_id" => pen_id,
            "reason" => reason,
            "quantity" => 1,
            "moved_at" => moved_at
          })
          |> repo.insert()
      end
    end)
    |> Multi.run({:sow_pen_updated, i}, fn repo, changes ->
      case Map.fetch!(changes, {:sow_move_decision, i}) do
        :skip ->
          {:ok, nil}

        {:move, sow} ->
          sow |> Ecto.Changeset.change(%{current_pen_id: pen_id}) |> repo.update()
      end
    end)
  end

  defp maybe_move_existing_sow_keyed(multi, _farm_id, _sow_id, _pen_id, _moved_at, _i), do: multi

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
      |> audit_after(scope, "service.created", :service, &service_audit_data/1)

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

  defp audit_after_keyed(multi, scope, action, key, i, change_fn) do
    Multi.run(multi, {:audit, action, i}, fn _repo, changes ->
      row = Map.fetch!(changes, key)

      opts = [entity_type: :service, entity_id: row.id]

      opts =
        if change_fn,
          do: Keyword.put(opts, :changes, stringify_keys(change_fn.(row))),
          else: opts

      Audit.log_now!(scope, action, opts)

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
  Returns the most recent open service for a sow (no result set, not
  deleted), preloading `:boar` for display. Returns `nil` when the sow
  has no open service.

  "Open" means the service hasn't been closed yet (no farrowing,
  abortion, re-service, death, or cull outcome recorded).
  """
  def latest_open_service_for_sow(%Scope{farm: farm}, sow_id) when is_integer(sow_id) do
    Repo.one(
      from(s in Service,
        where:
          s.farm_id == ^farm.id and
            s.sow_id == ^sow_id and
            is_nil(s.deleted_at) and
            is_nil(s.result),
        order_by: [desc: s.served_at, desc: s.id],
        limit: 1,
        preload: [:boar]
      )
    )
  end

  def latest_open_service_for_sow(_scope, _), do: nil

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
  1. Inserts the farrowing row (with `born_alive`, stillborn, mummified)
  2. Closes the service with `result = "farrowing"`
  3. Moves the sow into the farrowing pen, if specified
  4. Auto-promotes sow stage to `"sow"` and status to `"lactating"`
  5. Audits the farrowing

  Pre-wean piglets do NOT become `Animal` rows — they live as a count on
  the farrowing (plus the `LitterEvent` ledger for deaths and fostering).
  A weaner-stage batch `Animal` is created at weaning time.
  """
  def record_farrowing(%Scope{} = scope, %Service{} = service, attrs) do
    attrs = stringify_keys(attrs)

    with :ok <- ensure_service_open(service),
         :ok <- ensure_sow_served(service),
         :ok <- ensure_gestation_in_range(service, attrs) do
      do_record_farrowing(scope, service, attrs)
    end
  end

  defp ensure_service_open(%Service{result: nil}), do: :ok
  defp ensure_service_open(_), do: {:error, :service_already_closed}

  defp ensure_sow_served(%Service{sow_id: sow_id}) do
    case Repo.get(Animal, sow_id) do
      %Animal{status: "served"} -> :ok
      _ -> {:error, :sow_not_served}
    end
  end

  @gestation_tolerance_days 3

  defp ensure_gestation_in_range(%Service{served_at: served_at}, attrs) do
    case parse_date(attrs["farrowed_at"]) do
      nil ->
        :ok

      %Date{} = farrowed_at ->
        diff = abs(Date.diff(farrowed_at, served_at) - @gestation_days)

        if diff <= @gestation_tolerance_days,
          do: :ok,
          else: {:error, :gestation_out_of_range}
    end
  end

  defp do_record_farrowing(scope, service, attrs) do
    farm = scope.farm
    sow = Repo.get!(Animal, service.sow_id)
    pen_id = to_int(attrs["pen_id"]) || sow.current_pen_id
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
      |> maybe_move_sow(farm.id, sow, pen_id, farrowed_at)
      |> update_sow_for_farrowing(sow, pen_id)
      |> audit_after(scope, "farrowing.created", :farrowing, &farrowing_audit_data/1)

    case Repo.transaction(multi) do
      {:ok, %{farrowing: farrowing}} ->
        {:ok, farrowing}

      {:error, :farrowing, cs, _} ->
        {:error, cs}

      {:error, step, cs, _} ->
        {:error, {step, cs}}
    end
  end

  @doc """
  Records a farrowing for a sow who has no open service on file, creating
  a backfilled service (and optionally the sow itself) inline.

  `mode` is either:
    * `{:existing_sow, sow_id}` — sow is already registered but has no
      open service. Creates a backfill service, transitions her to
      `"served"` if needed, then records the farrowing.
    * `{:new_sow, sow_attrs}` — sow is unknown. Creates her inferred
      (with `needs_review: true`) as a sow/female, then backfills the
      service, then records the farrowing.

  `attrs` must include `:farrowed_at`, `:served_at`, and the normal
  farrowing numeric fields (`:born_alive`, etc). The service is always
  created with `service_type: "ai"` and `inferred: true`, and created
  sows/services carry `created_via: "farrowing_backfill"`.
  """
  def record_farrowing_with_backfill(%Scope{farm: farm} = scope, mode, attrs) do
    attrs = stringify_keys(attrs)
    served_at = parse_date(attrs["served_at"])
    farrowed_at = parse_date(attrs["farrowed_at"])

    cond do
      is_nil(served_at) ->
        {:error, :served_at_required}

      is_nil(farrowed_at) ->
        {:error, :farrowed_at_required}

      abs(Date.diff(farrowed_at, served_at) - @gestation_days) > @gestation_tolerance_days ->
        {:error, :gestation_out_of_range}

      true ->
        farrowing_attrs =
          Map.merge(attrs, %{
            "inferred" => true,
            "created_via" => "farrowing_backfill"
          })

        Repo.transaction(fn ->
          with {:ok, sow} <- resolve_or_create_backfill_sow(scope, mode),
               {:ok, sow} <- ensure_sow_served_for_backfill(sow),
               {:ok, service} <- insert_backfill_service(scope, farm.id, sow.id, attrs) do
            case record_farrowing(scope, service, farrowing_attrs) do
              {:ok, farrowing} -> farrowing
              {:error, reason} -> Repo.rollback(reason)
            end
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
    end
  end

  defp resolve_or_create_backfill_sow(%Scope{farm: farm}, {:existing_sow, sow_id}) do
    case Repo.get(Animal, sow_id) do
      %Animal{farm_id: fid} = sow when fid == farm.id -> {:ok, sow}
      _ -> {:error, :sow_not_found}
    end
  end

  defp resolve_or_create_backfill_sow(%Scope{farm: farm} = scope, {:new_sow, attrs}) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.merge(%{
        "tracking_type" => "individual",
        "stage" => "sow",
        "sex" => "female",
        "status" => "served",
        "farm_id" => farm.id,
        "inferred" => true,
        "needs_review" => true,
        "created_via" => "farrowing_backfill"
      })

    case Animal.changeset(%Animal{}, attrs) |> Repo.insert() do
      {:ok, sow} ->
        Audit.log_now!(scope, "animal.created.inferred",
          entity_type: :animal,
          entity_id: sow.id,
          changes: %{
            "ear_tag" => sow.ear_tag,
            "stage" => sow.stage,
            "sex" => sow.sex,
            "status" => sow.status,
            "created_via" => sow.created_via,
            "inferred" => sow.inferred,
            "needs_review" => sow.needs_review
          }
        )

        {:ok, sow}

      {:error, cs} ->
        {:error, {:sow, cs}}
    end
  end

  defp ensure_sow_served_for_backfill(%Animal{status: "served"} = sow), do: {:ok, sow}

  defp ensure_sow_served_for_backfill(%Animal{} = sow) do
    sow
    |> Ecto.Changeset.change(%{status: "served"})
    |> Repo.update()
  end

  defp insert_backfill_service(%Scope{} = scope, farm_id, sow_id, attrs) do
    service_attrs = %{
      "farm_id" => farm_id,
      "sow_id" => sow_id,
      "service_type" => "ai",
      "served_at" => attrs["served_at"],
      "boar_id" => to_int(attrs["boar_id"]),
      "notes" => attrs["service_notes"],
      "inferred" => true,
      "created_via" => "farrowing_backfill"
    }

    case Service.changeset(%Service{}, service_attrs) |> Repo.insert() do
      {:ok, service} ->
        Audit.log_now!(scope, "service.created.inferred",
          entity_type: :service,
          entity_id: service.id,
          changes: stringify_keys(service_audit_data(service))
        )

        {:ok, service}

      {:error, cs} ->
        {:error, {:service, cs}}
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
              {:ok, farrowing} -> [farrowing | acc]
              {:error, reason} -> Repo.rollback({i, reason})
            end
        end
      end)
      |> Enum.reverse()
    end)
  end

  def record_batch_farrowings(_scope, []), do: {:error, :no_entries}

  @doc """
  Batch farrowing entry with back-fill cascade.

  Each entry is a map. Sow is resolved via either `:service_id`
  (an existing open service) or `:sow_ear_tag` plus optional
  `:backfill_sow` map for the new-sow case.

  Resolution per row:

    * `:service_id` → use that open service directly.
    * `:sow_ear_tag` resolves to an existing sow with an open service
      → use that service.
    * `:sow_ear_tag` resolves to an existing sow with no open service
      → insert an inferred service (`inferred: true`,
      `created_via: "back_fill_from_farrowing"`, service_type: "ai",
      served_at = farrowed_at − gestation_days), then farrow.
    * `:sow_ear_tag` does not resolve and a similar tag exists → hard
      blocks with `{:error, {i, {:similar_tag, tags}}}` unless
      `backfill_sow.force_create` is true.
    * `:sow_ear_tag` does not resolve and no similar tag → creates
      inferred sow + inferred service + farrowing.

  Duplicate unknown ear tags within the same grid are rejected with
  `{:error, {i, :duplicate_ear_tag}}`.

  Returns `{:ok, [farrowing, ...]}` or `{:error, {row_index, reason}}`.
  Any failure rolls back the entire batch.
  """
  def record_batch_farrowings_with_backfill(%Scope{}, []), do: {:error, :no_entries}

  def record_batch_farrowings_with_backfill(%Scope{} = scope, entries)
      when is_list(entries) do
    Repo.transaction(fn ->
      with {:ok, classified} <- classify_batch_farrowing_entries(scope, entries) do
        classified
        |> Enum.with_index()
        |> Enum.reduce([], fn {row, i}, acc ->
          case process_farrowing_row(scope, row) do
            {:ok, farrowing} -> [farrowing | acc]
            {:error, reason} -> Repo.rollback({i, reason})
          end
        end)
        |> Enum.reverse()
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp classify_batch_farrowing_entries(scope, entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {entry, i}, {:ok, acc, seen_new} ->
      case classify_farrowing_one(scope, entry, seen_new) do
        {:ok, row} ->
          seen_new =
            case row do
              %{kind: :inferred_sow, ear_tag: tag} -> MapSet.put(seen_new, tag)
              _ -> seen_new
            end

          {:cont, {:ok, [row | acc], seen_new}}

        {:error, reason} ->
          {:halt, {:error, {i, reason}}}
      end
    end)
    |> case do
      {:ok, acc, _} -> {:ok, Enum.reverse(acc)}
      {:error, _} = err -> err
    end
  end

  defp classify_farrowing_one(scope, entry, seen_new) do
    attrs = stringify_keys(entry)
    service_id = to_int(attrs["service_id"])
    ear_tag = attrs["sow_ear_tag"]

    cond do
      not is_nil(service_id) ->
        {:ok, %{kind: :service_id, service_id: service_id, attrs: attrs}}

      is_nil(ear_tag) or ear_tag == "" ->
        {:error, :sow_not_found}

      true ->
        case Animals.find_by_ear_tag(scope, ear_tag) do
          %Animal{} = sow ->
            {:ok, %{kind: :existing_sow, sow: sow, attrs: attrs}}

          nil ->
            classify_new_farrowing_tag(scope, ear_tag, attrs, seen_new)
        end
    end
  end

  defp classify_new_farrowing_tag(scope, ear_tag, attrs, seen_new) do
    backfill = Map.get(attrs, "backfill_sow")

    force? =
      truthy?(backfill && (Map.get(backfill, :force_create) || Map.get(backfill, "force_create")))

    cond do
      MapSet.member?(seen_new, ear_tag) ->
        {:error, :duplicate_ear_tag}

      true ->
        similars = Animals.similar_ear_tags(scope, ear_tag)

        cond do
          similars != [] and not force? ->
            {:error, {:similar_tag, similars}}

          is_nil(backfill) ->
            {:error, :sow_not_found}

          true ->
            {:ok,
             %{
               kind: :inferred_sow,
               ear_tag: ear_tag,
               backfill: backfill,
               attrs: attrs
             }}
        end
    end
  end

  defp process_farrowing_row(scope, %{kind: :service_id, service_id: sid, attrs: attrs}) do
    case Repo.get(Service, sid) do
      %Service{farm_id: fid} = service when fid == scope.farm.id ->
        farrow_via(scope, service, attrs)

      _ ->
        {:error, :service_not_found}
    end
  end

  defp process_farrowing_row(scope, %{kind: :existing_sow, sow: sow, attrs: attrs}) do
    case current_service(scope, sow.id) do
      %Service{} = service ->
        farrow_via(scope, service, attrs)

      nil ->
        with {:ok, service} <- insert_inferred_service(scope, sow, attrs) do
          farrow_via(scope, service, attrs)
        end
    end
  end

  defp process_farrowing_row(scope, %{
         kind: :inferred_sow,
         ear_tag: tag,
         backfill: backfill,
         attrs: attrs
       }) do
    with {:ok, sow} <- insert_inferred_sow_for_farrowing(scope, tag, backfill, attrs),
         {:ok, service} <- insert_inferred_service(scope, sow, attrs) do
      farrow_via(scope, service, attrs)
    end
  end

  defp farrow_via(scope, service, attrs) do
    attrs =
      attrs
      |> Map.drop(["service_id", "sow_ear_tag", "backfill_sow"])

    record_farrowing(scope, service, attrs)
  end

  defp insert_inferred_sow_for_farrowing(scope, ear_tag, backfill, attrs) do
    farm = scope.farm
    farrowed_at = parse_date(attrs["farrowed_at"]) || Date.utc_today()
    served_at = Date.add(farrowed_at, -@gestation_days)

    # Reuse the service-flavored sow changeset but override created_via.
    service_like_attrs = Map.put(attrs, "served_at", served_at)
    sow_cs = build_inferred_sow_changeset(farm, ear_tag, backfill, service_like_attrs)

    sow_cs =
      Ecto.Changeset.put_change(sow_cs, :created_via, "back_fill_from_farrowing")

    multi =
      Multi.new()
      |> Multi.insert(:sow, sow_cs)
      |> Multi.insert(:sow_audit, fn %{sow: sow} -> inferred_sow_audit(scope, sow) end)
      |> Multi.update(:sow_with_origin, fn %{sow: sow, sow_audit: audit} ->
        Ecto.Changeset.change(sow, origin_audit_id: audit.id)
      end)

    case Repo.transaction(multi) do
      {:ok, %{sow_with_origin: sow}} -> {:ok, sow}
      {:error, :sow, cs, _} -> {:error, cs}
      {:error, step, cs, _} -> {:error, {step, cs}}
    end
  end

  defp insert_inferred_service(scope, sow, attrs) do
    farm = scope.farm
    farrowed_at = parse_date(attrs["farrowed_at"]) || Date.utc_today()
    served_at = Date.add(farrowed_at, -@gestation_days)

    service_attrs = %{
      "farm_id" => farm.id,
      "sow_id" => sow.id,
      "service_type" => "ai",
      "served_at" => served_at,
      "inferred" => true,
      "created_via" => "back_fill_from_farrowing"
    }

    multi =
      Multi.new()
      |> Multi.insert(:service, Service.changeset(%Service{}, service_attrs))
      |> Multi.insert(:service_audit, fn %{service: service} ->
        %AuditLog{
          farm_id: farm.id,
          actor_user_id: scope.user && scope.user.id,
          action: "service.created.inferred",
          entity_type: "service",
          entity_id: to_string(service.id),
          changes: %{"created_via" => service.created_via, "served_at" => to_string(served_at)},
          inserted_at: DateTime.utc_now(:second)
        }
      end)
      |> Multi.update(:service_with_origin, fn %{service: service, service_audit: audit} ->
        Ecto.Changeset.change(service, origin_audit_id: audit.id)
      end)
      |> Multi.update(:sow_served, Ecto.Changeset.change(sow, status: "served"))

    case Repo.transaction(multi) do
      {:ok, %{service_with_origin: service}} -> {:ok, service}
      {:error, :service, cs, _} -> {:error, cs}
      {:error, step, cs, _} -> {:error, {step, cs}}
    end
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
  Latest farrowing for a sow that has not yet been weaned. "Open"
  means no live (non-deleted) `Weaning` row exists for it.

  Returns the `%Farrowing{}` with `:sow`, `:pen`, and `service: [:boar]`
  preloaded, or `nil`.
  """
  def latest_open_farrowing_for_sow(%Scope{farm: farm}, sow_id) when is_integer(sow_id) do
    Repo.one(
      from(f in Farrowing,
        left_join: w in Weaning,
        on: w.farrowing_id == f.id and is_nil(w.deleted_at),
        where:
          f.farm_id == ^farm.id and
            f.sow_id == ^sow_id and
            is_nil(f.deleted_at) and
            is_nil(w.id),
        order_by: [desc: f.farrowed_at, desc: f.id],
        limit: 1
      )
    )
    |> case do
      nil -> nil
      f -> Repo.preload(f, [:sow, [pen: :house], service: [:boar]])
    end
  end

  def latest_open_farrowing_for_sow(_scope, _), do: nil

  @doc """
  Gets a farrowing by id, scoped to the farm.
  """
  def get_farrowing!(%Scope{farm: farm}, id) do
    Repo.one!(
      from(f in Farrowing,
        where: f.id == ^id and f.farm_id == ^farm.id and is_nil(f.deleted_at)
      )
    )
    |> Repo.preload([:sow, :weaning, :piglets, pen: :house, service: [:boar]])
  end

  @doc """
  Fetches multiple farrowings by id (scoped to the farm), preloading
  the sow. Used by the litter ledger UI to resolve counterpart ear tags.
  """
  def list_farrowings_by_ids(%Scope{farm: farm}, ids) when is_list(ids) do
    Repo.all(
      from(f in Farrowing,
        where: f.farm_id == ^farm.id and f.id in ^ids,
        preload: [:sow]
      )
    )
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

  # The litter is "clean" if there are no active (non-deleted) litter
  # events (deaths or fostering) recorded against the farrowing.
  defp litter_activity_clean?(%Scope{farm: farm}, %Farrowing{} = farrowing) do
    not Repo.exists?(
      from(e in LitterEvent,
        where:
          e.farm_id == ^farm.id and
            e.farrowing_id == ^farrowing.id and
            is_nil(e.deleted_at)
      )
    )
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

        {:ok, %{sow_move: sow_move}}
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

  Weaner-batch pooling (Option A): weaners are tracked as a single
  `Animal` row per free-text `ear_tag`. Every wean against that tag
  writes a `wean` `Movement` (linked via `weaning_id`) that carries the
  count, and increments the batch row's `quantity`. If no active weaner
  batch with that tag exists yet, a fresh row is inserted first with
  `quantity: 0` and `current_pen_id: nil`. `batch_tag` is required
  whenever `weaned_count >= 1`.

  In one atomic transaction:
  1. Inserts the weaning row
  2. For `weaned_count >= 1`:
     - Resolves (or inserts at quantity 0) the weaner batch keyed by `batch_tag`
     - Writes a `wean` `Movement` linked to the weaning (`weaning_id` FK)
     - Increments `batch.quantity` by the weaned count
     - Sets `weaning.batch_animal_id` to the resolved batch
  3. If `destination_pen_id` is given, moves the **sow** (not the
     batch) into that pen. Batch placement is a separate step.
  4. Transitions sow `lactating → dry` when applicable
  5. Audits the weaning

  Returns `{:ok, weaning, batch}` on success. `batch` is `nil` when
  `weaned_count == 0`.

  Error reasons include `:already_weaned`, `:batch_tag_required`.
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
    batch_tag = normalize_batch_tag(attrs["batch_tag"])
    sow = Repo.get!(Animal, farrowing.sow_id)

    cond do
      weaned_count >= 1 and is_nil(batch_tag) ->
        {:error, :batch_tag_required}

      true ->
        weaning_attrs =
          attrs
          |> Map.drop(["batch_tag"])
          |> Map.merge(%{
            "farm_id" => farm.id,
            "farrowing_id" => farrowing.id
          })

        multi =
          Multi.new()
          |> Multi.insert(:weaning, Weaning.changeset(%Weaning{}, weaning_attrs))
          |> consolidate_piglets(farm.id, farrowing, sow, weaned_count, batch_tag, weaned_at)
          |> audit_new_batch_animal(scope)
          |> audit_wean_movement(scope)
          |> link_weaning_to_batch()
          |> maybe_move_sow_on_weaning(farm.id, sow, dest_pen_id, weaned_at)
          |> update_sow_after_weaning(sow)
          |> audit_after(scope, "weaning.created", :weaning, &weaning_audit_data/1)

        case Repo.transaction(multi) do
          {:ok, results} ->
            weaning = Map.get(results, :weaning_linked) || Map.fetch!(results, :weaning)
            batch = Map.get(results, :batch_qty_updated) || Map.get(results, :batch)
            {:ok, weaning, batch}

          {:error, :weaning, cs, _} ->
            {:error, cs}

          {:error, step, cs, _} ->
            {:error, {step, cs}}
        end
    end
  end

  @doc """
  Records a weaning for a sow that has no open farrowing on file by
  cascading the backfill: creates an inferred service + farrowing
  (and optionally the sow itself) inline, then records the weaning.

  `mode` matches `record_farrowing_with_backfill/3`:

    * `{:existing_sow, sow_id}` — sow registered, but no open farrowing.
    * `{:new_sow, sow_attrs}` — sow unknown.

  `attrs` must include `:weaned_at`, `:served_at`, `:farrowed_at`, and
  the normal weaning fields (`:weaned_count`, `:batch_tag`, etc).
  Defaults applied by the caller LV: `farrowed_at = weaned_at − lactation_days`,
  `served_at = farrowed_at − gestation_days`. Created service/sow carry
  `inferred: true` and `created_via: "weaning_backfill"` (via the
  delegated `record_farrowing_with_backfill/3`).

  Returns `{:ok, weaning, batch}` on success — same shape as
  `record_weaning/3`.
  """
  def record_weaning_with_backfill(%Scope{} = scope, mode, attrs) do
    attrs = stringify_keys(attrs)
    weaned_at = parse_date(attrs["weaned_at"])

    cond do
      is_nil(weaned_at) ->
        {:error, :weaned_at_required}

      true ->
        Repo.transaction(fn ->
          case record_farrowing_with_backfill(scope, mode, attrs) do
            {:ok, farrowing} ->
              case do_record_weaning(scope, farrowing, attrs) do
                {:ok, weaning, batch} -> {weaning, batch}
                {:error, reason} -> Repo.rollback(reason)
              end

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end)
        |> case do
          {:ok, {weaning, batch}} -> {:ok, weaning, batch}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Spreadsheet-style batch weaning with per-row back-fill cascade.

  Each entry resolves one sow (via `:sow_ear_tag` or `:sow_id`) and
  then records a weaning — creating inferred service + farrowing (and
  the sow itself, if unknown) on the fly for sows without an open
  farrowing.

  Returns `{:ok, [{weaning, batch}, ...]}` on success; rolls back the
  entire batch and returns `{:error, {row_index, reason}}` on the
  first failure.
  """
  def record_batch_weanings_with_backfill(%Scope{}, []), do: {:error, :no_entries}

  def record_batch_weanings_with_backfill(%Scope{} = scope, entries)
      when is_list(entries) do
    Repo.transaction(fn ->
      with {:ok, classified} <- classify_batch_weaning_entries(scope, entries) do
        classified
        |> Enum.with_index()
        |> Enum.reduce([], fn {row, i}, acc ->
          case process_weaning_row(scope, row) do
            {:ok, weaning, batch} -> [{weaning, batch} | acc]
            {:error, reason} -> Repo.rollback({i, reason})
          end
        end)
        |> Enum.reverse()
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp classify_batch_weaning_entries(scope, entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {entry, i}, {:ok, acc, seen_new} ->
      case classify_weaning_one(scope, entry, seen_new) do
        {:ok, row} ->
          seen_new =
            case row do
              %{kind: :inferred_sow, ear_tag: tag} -> MapSet.put(seen_new, tag)
              _ -> seen_new
            end

          {:cont, {:ok, [row | acc], seen_new}}

        {:error, reason} ->
          {:halt, {:error, {i, reason}}}
      end
    end)
    |> case do
      {:ok, acc, _} -> {:ok, Enum.reverse(acc)}
      {:error, _} = err -> err
    end
  end

  defp classify_weaning_one(scope, entry, seen_new) do
    attrs = stringify_keys(entry)
    sow_id = to_int(attrs["sow_id"])
    ear_tag = attrs["sow_ear_tag"]

    cond do
      not is_nil(sow_id) ->
        {:ok, %{kind: :existing_sow_id, sow_id: sow_id, attrs: attrs}}

      is_nil(ear_tag) or ear_tag == "" ->
        {:error, :sow_not_found}

      true ->
        case Animals.find_by_ear_tag(scope, ear_tag) do
          %Animal{} = sow ->
            {:ok, %{kind: :existing_sow, sow: sow, attrs: attrs}}

          nil ->
            classify_new_weaning_tag(scope, ear_tag, attrs, seen_new)
        end
    end
  end

  defp classify_new_weaning_tag(scope, ear_tag, attrs, seen_new) do
    backfill = Map.get(attrs, "backfill_sow")

    force? =
      truthy?(backfill && (Map.get(backfill, :force_create) || Map.get(backfill, "force_create")))

    cond do
      MapSet.member?(seen_new, ear_tag) ->
        {:error, :duplicate_ear_tag}

      true ->
        similars = Animals.similar_ear_tags(scope, ear_tag)

        cond do
          similars != [] and not force? ->
            {:error, {:similar_tag, similars}}

          is_nil(backfill) ->
            {:error, :sow_not_found}

          true ->
            {:ok,
             %{
               kind: :inferred_sow,
               ear_tag: ear_tag,
               backfill: backfill,
               attrs: attrs
             }}
        end
    end
  end

  defp process_weaning_row(scope, %{kind: :existing_sow_id, sow_id: sid, attrs: attrs}) do
    case Repo.get(Animal, sid) do
      %Animal{farm_id: fid} when fid == scope.farm.id ->
        wean_for_existing_sow(scope, sid, attrs)

      _ ->
        {:error, :sow_not_found}
    end
  end

  defp process_weaning_row(scope, %{kind: :existing_sow, sow: sow, attrs: attrs}) do
    wean_for_existing_sow(scope, sow.id, attrs)
  end

  defp process_weaning_row(scope, %{
         kind: :inferred_sow,
         ear_tag: tag,
         backfill: backfill,
         attrs: attrs
       }) do
    sow_attrs =
      backfill
      |> stringify_keys()
      |> Map.put("ear_tag", tag)

    attrs = Map.drop(attrs, ["sow_id", "sow_ear_tag", "backfill_sow"])
    record_weaning_with_backfill(scope, {:new_sow, sow_attrs}, attrs)
  end

  defp wean_for_existing_sow(scope, sow_id, attrs) do
    attrs = Map.drop(attrs, ["sow_id", "sow_ear_tag", "backfill_sow"])

    case latest_open_farrowing_for_sow(scope, sow_id) do
      %Farrowing{} = farrowing ->
        record_weaning(scope, farrowing, attrs)

      nil ->
        record_weaning_with_backfill(scope, {:existing_sow, sow_id}, attrs)
    end
  end

  defp normalize_batch_tag(nil), do: nil

  defp normalize_batch_tag(tag) when is_binary(tag) do
    case String.trim(tag) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_batch_tag(_), do: nil

  # weaned_count == 0: no weaner batch created; deaths/fostering are
  # already captured in the `LitterEvent` ledger.
  defp consolidate_piglets(multi, _farm_id, _farrowing, _sow, 0, _tag, _weaned_at) do
    Multi.run(multi, :batch, fn _repo, _ -> {:ok, nil} end)
  end

  # weaned_count >= 1: every wean creates a `wean` Movement row (linked
  # to its `weaning_id`) that adds `count` to the batch's quantity. The
  # first wean against a new tag inserts the Animal batch with
  # `quantity: 0` first; subsequent weans reuse the same row. Uniform
  # write path = uniform delete path.
  defp consolidate_piglets(multi, farm_id, farrowing, sow, count, batch_tag, weaned_at)
       when count >= 1 and is_binary(batch_tag) do
    service = Repo.get!(Service, farrowing.service_id)

    multi
    |> Multi.run(:existing_batch, fn repo, _ ->
      {:ok, repo.one(active_weaner_batch_query(farm_id, batch_tag))}
    end)
    |> Multi.run(:batch, fn repo, %{existing_batch: existing} ->
      case existing do
        %Animal{} = existing ->
          {:ok, existing}

        nil ->
          Animal.piglet_changeset(%Animal{}, %{
            "tracking_type" => "batch",
            "stage" => "weaner",
            "status" => "active",
            "ear_tag" => batch_tag,
            "quantity" => 0,
            "dob" => farrowing.farrowed_at,
            "dam_id" => sow.id,
            "sire_id" => service.boar_id,
            "farrowing_id" => farrowing.id,
            "farm_id" => farm_id,
            "current_pen_id" => nil
          })
          |> repo.insert()
      end
    end)
    |> Multi.run(:wean_movement, fn repo, %{weaning: weaning, batch: batch} ->
      Movement.changeset(%Movement{}, %{
        "farm_id" => farm_id,
        "animal_id" => batch.id,
        "weaning_id" => weaning.id,
        "reason" => "wean",
        "from_pen_id" => farrowing.pen_id,
        "to_pen_id" => batch.current_pen_id,
        "quantity" => count,
        "moved_at" => weaned_at || Date.utc_today()
      })
      |> repo.insert()
    end)
    |> Multi.run(:batch_qty_updated, fn repo, %{batch: batch} ->
      batch
      |> Ecto.Changeset.change(%{quantity: (batch.quantity || 0) + count})
      |> repo.update()
    end)
  end

  # Stamps weaning.batch_animal_id with the resolved batch id, so each
  # weaning keeps provenance on which pool it contributed to.
  defp link_weaning_to_batch(multi) do
    Multi.run(multi, :weaning_linked, fn repo, %{weaning: weaning, batch: batch} ->
      case batch do
        nil ->
          {:ok, nil}

        %Animal{} = b ->
          weaning
          |> Ecto.Changeset.change(%{batch_animal_id: b.id})
          |> repo.update()
      end
    end)
  end

  # Weaning's destination_pen_id is the **sow's** destination (dry-sow
  # housing). The weaner batch is placed separately. No-op when nil or
  # when the sow is already in that pen.
  defp maybe_move_sow_on_weaning(multi, _farm_id, _sow, nil, _weaned_at), do: multi

  defp maybe_move_sow_on_weaning(multi, farm_id, sow, dest_pen_id, weaned_at)
       when is_integer(dest_pen_id) do
    if sow.current_pen_id == dest_pen_id do
      multi
    else
      moved = weaned_at || Date.utc_today()
      reason = if is_nil(sow.current_pen_id), do: "placement", else: "pen_transfer"

      multi
      |> Multi.run(:sow_movement, fn repo, _ ->
        Movement.changeset(%Movement{}, %{
          "farm_id" => farm_id,
          "animal_id" => sow.id,
          "from_pen_id" => sow.current_pen_id,
          "to_pen_id" => dest_pen_id,
          "reason" => reason,
          "quantity" => 1,
          "moved_at" => moved
        })
        |> repo.insert()
      end)
      |> Multi.run(:sow_pen_updated, fn repo, _ ->
        sow |> Ecto.Changeset.change(%{current_pen_id: dest_pen_id}) |> repo.update()
      end)
    end
  end

  defp active_weaner_batch_query(farm_id, tag) do
    from(a in Animal,
      where:
        a.farm_id == ^farm_id and
          a.tracking_type == "batch" and
          a.stage == "weaner" and
          a.status == "active" and
          a.ear_tag == ^tag,
      limit: 1
    )
  end

  @doc """
  Lists active weaner batches for the farm, ordered by `ear_tag`.
  Used by the weaning form's batch_tag autocomplete.
  """
  def list_active_weaner_batches(%Scope{farm: farm}) do
    from(a in Animal,
      where:
        a.farm_id == ^farm.id and
          a.tracking_type == "batch" and
          a.stage == "weaner" and
          a.status == "active",
      order_by: [asc: a.ear_tag]
    )
    |> Repo.all()
  end

  @doc """
  Finds the active weaner batch with this `ear_tag` on the farm, or
  `nil`. Tag whitespace is trimmed; blank → `nil`.
  """
  def find_active_weaner_batch(%Scope{farm: farm}, tag) do
    case normalize_batch_tag(tag) do
      nil -> nil
      clean -> Repo.one(active_weaner_batch_query(farm.id, clean))
    end
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
        preload: [
          :batch_animal,
          [destination_pen: :house],
          farrowing: [:sow, [pen: :house]]
        ]
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
    count = w.weaned_count || 0

    cond do
      count == 0 ->
        # No weaner batch was created; nothing to validate on the
        # batch side.
        true

      is_nil(w.batch_animal_id) ->
        # Legacy weanings predating the batch_animal_id backfill —
        # fall back to the per-farrowing lookup so we at least ensure
        # the litter batch is still present and serviceable.
        farrowing = Repo.get!(Farrowing, w.farrowing_id)

        batch =
          Repo.one(
            from(a in Animal,
              where:
                a.farm_id == ^farm.id and
                  a.farrowing_id == ^farrowing.id and
                  a.tracking_type == "batch"
            )
          )

        not is_nil(batch) and
          batch.status == "active" and
          batch.stage == "weaner" and
          (batch.quantity || 0) >= count and
          not batch_has_non_wean_movement?(batch.id)

      true ->
        batch = Repo.get(Animal, w.batch_animal_id)

        not is_nil(batch) and
          batch.farm_id == farm.id and
          batch.status == "active" and
          batch.stage == "weaner" and
          (batch.quantity || 0) >= count and
          not batch_has_non_wean_movement?(batch.id)
    end
  end

  defp batch_has_non_wean_movement?(batch_id) do
    Repo.exists?(from(m in Movement, where: m.animal_id == ^batch_id and m.reason != "wean"))
  end

  @doc """
  Soft-deletes a weaning and reverses its side-effects atomically.

  Cascade (in one transaction):
    * decrement `batch.quantity` by the weaned count on the linked
      weaner batch. When the result hits zero, transition the batch
      to `status = "deceased"` (the batch shell is kept for audit).
    * delete the `wean` movement row written for this weaning
      (linked via `weaning_id`).
    * revert sow status `"dry"` → `"lactating"` (if applicable)
    * stamp `deleted_at` / `deleted_by_id` on the weaning row
    * write `weaning.deleted` audit with a row snapshot

  The sow's pen-transfer at weaning (if any) is **not** reversed —
  same policy as farrowing pen moves.

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
    count = w.weaned_count || 0

    multi =
      Multi.new()
      |> Multi.run(:load_batch, fn repo, _ ->
        batch =
          cond do
            count == 0 ->
              nil

            w.batch_animal_id ->
              repo.get(Animal, w.batch_animal_id)

            true ->
              # Legacy fallback: locate the batch via farrowing_id.
              repo.one(
                from(a in Animal,
                  where:
                    a.farm_id == ^scope.farm.id and
                      a.farrowing_id == ^farrowing.id and
                      a.tracking_type == "batch"
                )
              )
          end

        {:ok, batch}
      end)
      |> Multi.run(:delete_wean_movement, fn repo, %{load_batch: batch} ->
        case batch do
          nil ->
            {:ok, 0}

          %Animal{} ->
            {n, _} =
              repo.delete_all(
                from(m in Movement,
                  where: m.weaning_id == ^w.id and m.reason == "wean"
                )
              )

            {:ok, n}
        end
      end)
      |> Multi.run(:decrement_batch, fn repo, %{load_batch: batch} ->
        case batch do
          nil ->
            {:ok, nil}

          %Animal{} = b ->
            new_qty = max((b.quantity || 0) - count, 0)

            changes =
              if new_qty == 0 do
                %{quantity: 0, status: "reversed"}
              else
                %{quantity: new_qty}
              end

            b |> Ecto.Changeset.change(changes) |> repo.update()
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
  Returns the count of surviving piglets for a farrowing, derived from
  the litter event ledger:

      surviving = born_alive + Σ foster_in − Σ foster_out − Σ death
  """
  def surviving_piglet_count(%Farrowing{} = farrowing) do
    born = farrowing.born_alive || 0

    rows =
      Repo.all(
        from(e in LitterEvent,
          where: e.farrowing_id == ^farrowing.id and is_nil(e.deleted_at),
          select: {e.kind, e.quantity}
        )
      )

    Enum.reduce(rows, born, fn
      {"foster_in", q}, acc -> acc + q
      {"foster_out", q}, acc -> acc - q
      {"death", q}, acc -> acc - q
      _, acc -> acc
    end)
  end

  @doc """
  Records a pre-wean piglet death against a farrowing's litter.

  `attrs` must include `:quantity` and `:occurred_at`; `:notes` is
  optional. Refuses to over-draw: the resulting surviving count must
  stay ≥ 0.
  """
  def record_pre_wean_death(%Scope{farm: farm} = scope, %Farrowing{} = farrowing, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.merge(%{
        "farm_id" => farm.id,
        "farrowing_id" => farrowing.id,
        "kind" => "death",
        "counterpart_farrowing_id" => nil,
        "created_by_id" => scope.user && scope.user.id
      })

    qty = to_int(attrs["quantity"]) || 0

    cond do
      qty <= 0 ->
        {:error, :invalid_quantity}

      surviving_piglet_count(farrowing) - qty < 0 ->
        {:error, :insufficient_surviving}

      true ->
        multi =
          Multi.new()
          |> Multi.insert(:event, LitterEvent.changeset(%LitterEvent{}, attrs))
          |> Audit.log!(scope, "litter_event.created",
            entity_type: :litter_event,
            changes: %{kind: "death", farrowing_id: farrowing.id, quantity: qty}
          )

        case Repo.transaction(multi) do
          {:ok, %{event: e}} -> {:ok, e}
          {:error, :event, cs, _} -> {:error, cs}
          {:error, step, reason, _} -> {:error, {step, reason}}
        end
    end
  end

  @doc """
  Records a paired fostering event between two farrowings.

  Writes two `LitterEvent` rows atomically: a `foster_out` on `source`
  and a `foster_in` on `destination`, each pointing at the other via
  `counterpart_farrowing_id`. Refuses to over-draw the source litter.
  """
  def record_fostering(
        %Scope{farm: farm} = scope,
        %Farrowing{} = source,
        %Farrowing{} = destination,
        attrs
      )
      when source.id != destination.id do
    attrs = stringify_keys(attrs)
    qty = to_int(attrs["quantity"]) || 0
    occurred_at = attrs["occurred_at"]
    notes = attrs["notes"]
    user_id = scope.user && scope.user.id

    cond do
      qty <= 0 ->
        {:error, :invalid_quantity}

      surviving_piglet_count(source) - qty < 0 ->
        {:error, :insufficient_surviving}

      true ->
        out_attrs = %{
          "farm_id" => farm.id,
          "farrowing_id" => source.id,
          "counterpart_farrowing_id" => destination.id,
          "kind" => "foster_out",
          "quantity" => qty,
          "occurred_at" => occurred_at,
          "notes" => notes,
          "created_by_id" => user_id
        }

        in_attrs = %{
          out_attrs
          | "farrowing_id" => destination.id,
            "counterpart_farrowing_id" => source.id,
            "kind" => "foster_in"
        }

        multi =
          Multi.new()
          |> Multi.insert(:out, LitterEvent.changeset(%LitterEvent{}, out_attrs))
          |> Multi.insert(:in, LitterEvent.changeset(%LitterEvent{}, in_attrs))
          |> Audit.log!(scope, "litter_event.fostered",
            entity_type: :litter_event,
            changes: %{
              source_farrowing_id: source.id,
              destination_farrowing_id: destination.id,
              quantity: qty
            }
          )

        case Repo.transaction(multi) do
          {:ok, %{out: out_ev, in: in_ev}} -> {:ok, {out_ev, in_ev}}
          {:error, step, cs, _} -> {:error, {step, cs}}
        end
    end
  end

  def record_fostering(_scope, %Farrowing{id: id}, %Farrowing{id: id}, _attrs),
    do: {:error, :same_farrowing}

  @doc """
  Soft-deletes a litter event, reversing its effect on the litter count.

  * `death` events can always be removed (surviving count only rises).
  * `foster_out` / `foster_in` events are paired — deleting one also
    deletes its counterpart atomically. The destination side (the one
    that gained piglets) must not go negative after removal.

  Blocked once a weaning has been recorded for the affected farrowing
  (or its counterpart), since weaning relies on the surviving count.
  """
  def delete_litter_event(%Scope{farm: farm} = scope, %LitterEvent{} = event) do
    event = Repo.preload(event, [])

    cond do
      event.farm_id != farm.id ->
        {:error, :not_found}

      not is_nil(event.deleted_at) ->
        {:error, :already_deleted}

      true ->
        do_delete_litter_event(scope, event)
    end
  end

  defp do_delete_litter_event(scope, %LitterEvent{kind: "death"} = event) do
    source = Repo.get!(Farrowing, event.farrowing_id)

    cond do
      weaning_exists?(source) ->
        {:error, :weaning_closed}

      true ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        user_id = scope.user && scope.user.id

        multi =
          Multi.new()
          |> Multi.update(
            :event,
            Ecto.Changeset.change(event, deleted_at: now, deleted_by_id: user_id)
          )
          |> Audit.log!(scope, "litter_event.deleted",
            entity_type: :litter_event,
            entity_id: event.id,
            changes: %{kind: "death", quantity: event.quantity}
          )

        case Repo.transaction(multi) do
          {:ok, _} -> {:ok, :deleted}
          {:error, step, reason, _} -> {:error, {step, reason}}
        end
    end
  end

  defp do_delete_litter_event(scope, %LitterEvent{kind: kind} = event)
       when kind in ["foster_in", "foster_out"] do
    counterpart =
      Repo.one(
        from(e in LitterEvent,
          where:
            e.farrowing_id == ^event.counterpart_farrowing_id and
              e.counterpart_farrowing_id == ^event.farrowing_id and
              e.quantity == ^event.quantity and
              is_nil(e.deleted_at) and
              e.kind != ^event.kind,
          limit: 1
        )
      )

    source = Repo.get!(Farrowing, event.farrowing_id)

    counterpart_farrowing =
      counterpart && Repo.get!(Farrowing, counterpart.farrowing_id)

    cond do
      is_nil(counterpart) ->
        {:error, :counterpart_missing}

      weaning_exists?(source) or weaning_exists?(counterpart_farrowing) ->
        {:error, :weaning_closed}

      # The foster_in side is the one that gained piglets; removing it
      # drops that farrowing's surviving count by `quantity`.
      foster_destination_would_underflow?(event, counterpart) ->
        {:error, :insufficient_surviving}

      true ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        user_id = scope.user && scope.user.id

        multi =
          Multi.new()
          |> Multi.update(
            :event,
            Ecto.Changeset.change(event, deleted_at: now, deleted_by_id: user_id)
          )
          |> Multi.update(
            :counterpart,
            Ecto.Changeset.change(counterpart, deleted_at: now, deleted_by_id: user_id)
          )
          |> Audit.log!(scope, "litter_event.deleted",
            entity_type: :litter_event,
            entity_id: event.id,
            changes: %{
              kind: kind,
              quantity: event.quantity,
              counterpart_event_id: counterpart.id
            }
          )

        case Repo.transaction(multi) do
          {:ok, _} -> {:ok, :deleted}
          {:error, step, reason, _} -> {:error, {step, reason}}
        end
    end
  end

  defp foster_destination_would_underflow?(event, counterpart) do
    foster_in = if event.kind == "foster_in", do: event, else: counterpart
    destination = Repo.get!(Farrowing, foster_in.farrowing_id)
    surviving_piglet_count(destination) - foster_in.quantity < 0
  end

  @doc """
  Lists all litter events (non-deleted) for a farrowing, oldest first.
  """
  def list_litter_events(%Scope{farm: farm}, %Farrowing{} = farrowing) do
    Repo.all(
      from(e in LitterEvent,
        where:
          e.farm_id == ^farm.id and
            e.farrowing_id == ^farrowing.id and
            is_nil(e.deleted_at),
        order_by: [asc: e.occurred_at, asc: e.id]
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

  defp audit_after(multi, scope, action, key, change_fn \\ nil) do
    Multi.run(multi, {:audit, action}, fn _repo, changes ->
      row = Map.fetch!(changes, key)

      opts = [entity_type: key, entity_id: row.id]

      opts =
        if change_fn,
          do: Keyword.put(opts, :changes, stringify_keys(change_fn.(row))),
          else: opts

      Audit.log_now!(scope, action, opts)

      {:ok, :logged}
    end)
  end

  defp audit_new_batch_animal(multi, scope) do
    Multi.run(multi, {:audit, :batch_animal_created}, fn _repo, changes ->
      case {Map.get(changes, :existing_batch), Map.get(changes, :batch)} do
        {nil, %Animal{} = batch} ->
          Audit.log_now!(scope, "animal.created",
            entity_type: :animal,
            entity_id: batch.id,
            changes: %{
              ear_tag: batch.ear_tag,
              tracking_type: batch.tracking_type,
              stage: batch.stage,
              dob: batch.dob,
              dam_id: batch.dam_id,
              sire_id: batch.sire_id,
              farrowing_id: batch.farrowing_id
            }
          )

          {:ok, :logged}

        _ ->
          {:ok, :skipped}
      end
    end)
  end

  defp audit_wean_movement(multi, scope) do
    Multi.run(multi, {:audit, :wean_movement}, fn _repo, changes ->
      case Map.get(changes, :wean_movement) do
        nil ->
          {:ok, :skipped}

        %Movement{} = m ->
          Audit.log_now!(scope, "movement.recorded",
            entity_type: :animal,
            entity_id: m.animal_id,
            changes: %{
              reason: m.reason,
              from_pen_id: m.from_pen_id,
              to_pen_id: m.to_pen_id,
              quantity: m.quantity,
              weaning_id: m.weaning_id
            }
          )

          {:ok, :logged}
      end
    end)
  end

  defp service_audit_data(%Service{} = s) do
    %{
      sow_id: s.sow_id,
      boar_id: s.boar_id,
      service_type: s.service_type,
      served_at: s.served_at,
      technician_user_id: s.technician_user_id,
      inferred: s.inferred,
      created_via: s.created_via
    }
  end

  defp farrowing_audit_data(%Farrowing{} = f) do
    %{
      service_id: f.service_id,
      sow_id: f.sow_id,
      pen_id: f.pen_id,
      farrowed_at: f.farrowed_at,
      born_alive: f.born_alive,
      stillborn: f.stillborn,
      mummified: f.mummified,
      total_birth_weight_g: f.total_birth_weight_g,
      inferred: f.inferred,
      created_via: f.created_via
    }
  end

  defp weaning_audit_data(%Weaning{} = w) do
    %{
      farrowing_id: w.farrowing_id,
      weaned_at: w.weaned_at,
      weaned_count: w.weaned_count,
      avg_wean_weight_g: w.avg_wean_weight_g,
      destination_pen_id: w.destination_pen_id,
      inferred: w.inferred,
      created_via: w.created_via
    }
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
