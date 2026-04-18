defmodule Peggy.Animals do
  @moduledoc """
  Animal registry: individual and batch pig tracking, lifecycle stages,
  parentage, pen assignment, and movement log.

  Every function takes a `%Scope{}` and enforces `farm_id` isolation.
  Mutations write an `audit_logs` row in the same transaction.

  ## Location tracking

  * **Individual** animals use `animals.current_pen_id` as the single
    source of truth for their current pen.
  * **Batch** animals may be split across multiple pens. Each active
    slice is one row in `placements`. The sum of active placements
    equals `animals.quantity`. Batch animals never populate
    `animals.current_pen_id`.
  """

  import Ecto.Query
  alias Ecto.Multi
  alias Peggy.{Repo, Audit}
  alias Peggy.Accounts.Scope
  alias Peggy.Animals.{Animal, Movement, Placement}

  ## Queries

  def list_animals(%Scope{farm: farm}, opts \\ []) do
    stage = Keyword.get(opts, :stage)
    status = Keyword.get(opts, :status)
    pen_id = Keyword.get(opts, :pen_id)

    base =
      from(a in Animal,
        where: a.farm_id == ^farm.id,
        order_by: [asc: a.ear_tag, asc: a.id]
      )
      |> maybe_filter(:stage, stage)
      |> maybe_filter(:status, status)
      |> preload(current_pen: [:house], placements: ^active_placement_query())

    query =
      case pen_id do
        nil ->
          base

        "" ->
          base

        id ->
          from a in base,
            left_join: p in Placement,
            on: p.animal_id == a.id and is_nil(p.removed_at) and p.pen_id == ^id,
            where: a.current_pen_id == ^id or not is_nil(p.id),
            distinct: a.id
      end

    Repo.all(query)
  end

  def get_animal!(%Scope{farm: farm}, id) do
    Repo.get_by!(Animal, id: id, farm_id: farm.id)
    |> Repo.preload(
      current_pen: [:house],
      sire: [],
      dam: [],
      placements: active_placement_query()
    )
  end

  def list_movements(%Scope{farm: farm}, %Animal{id: animal_id, farm_id: fid})
      when fid == farm.id do
    Repo.all(
      from m in Movement,
        where: m.animal_id == ^animal_id,
        order_by: [desc: m.moved_at, desc: m.inserted_at, desc: m.id],
        preload: [from_pen: :house, to_pen: :house]
    )
  end

  def list_offspring(%Scope{farm: farm}, %Animal{id: id, farm_id: fid})
      when fid == farm.id do
    Repo.all(
      from a in Animal,
        where: a.farm_id == ^farm.id and (a.sire_id == ^id or a.dam_id == ^id),
        order_by: [asc: a.ear_tag, asc: a.id]
    )
  end

  @doc """
  Active placements for a batch animal, preloaded with pen + house.
  """
  def list_placements(%Scope{farm: farm}, %Animal{id: animal_id, farm_id: fid})
      when fid == farm.id do
    Repo.all(
      from p in Placement,
        where: p.animal_id == ^animal_id and is_nil(p.removed_at),
        order_by: [asc: p.id],
        preload: [pen: :house]
    )
  end

  def count_animals_in_pen(%Scope{farm: farm}, pen_id) do
    present = Animal.present_statuses()

    individuals =
      Repo.one(
        from a in Animal,
          where:
            a.farm_id == ^farm.id and a.current_pen_id == ^pen_id and a.status in ^present and
              a.tracking_type == "individual",
          select: coalesce(sum(a.quantity), 0)
      )

    batched =
      Repo.one(
        from p in Placement,
          join: a in Animal,
          on: a.id == p.animal_id,
          where:
            a.farm_id == ^farm.id and p.pen_id == ^pen_id and is_nil(p.removed_at) and
              a.status in ^present,
          select: coalesce(sum(p.quantity), 0)
      )

    individuals + batched
  end

  def change_animal(%Animal{} = a, attrs \\ %{}), do: Animal.changeset(a, attrs)
  def change_movement(%Movement{} = m, attrs \\ %{}), do: Movement.changeset(m, attrs)

  ## Animals CRUD

  def create_animal(%Scope{farm: farm} = scope, attrs) do
    attrs = stringify(attrs) |> Map.put("farm_id", farm.id)
    tracking_type = Map.get(attrs, "tracking_type")
    initial_pen_id = Map.get(attrs, "current_pen_id")

    # Batches track location via placements, not animals.current_pen_id.
    animal_attrs =
      if tracking_type == "batch",
        do: Map.put(attrs, "current_pen_id", nil),
        else: attrs

    cs = Animal.changeset(%Animal{}, animal_attrs)

    Multi.new()
    |> Multi.insert(:animal, cs)
    |> audit_after(scope, "animal.created", :animal, fn a ->
      base = %{tracking_type: a.tracking_type, stage: a.stage, status: a.status}

      base =
        if a.tracking_type == "individual",
          do: Map.merge(base, %{ear_tag: a.ear_tag, sex: a.sex}),
          else: Map.put(base, :quantity, a.quantity)

      if a.breed, do: Map.put(base, :breed, a.breed), else: base
    end)
    |> maybe_seed_placement(tracking_type, initial_pen_id)
    |> maybe_seed_initial_movement(tracking_type, initial_pen_id, farm.id)
    |> Repo.transaction()
    |> unwrap(:animal)
  end

  # Placement movement row — for individual or batch with an initial pen.
  defp maybe_seed_initial_movement(multi, tracking_type, pen_id, farm_id)
       when tracking_type in ["individual", "batch"] and pen_id not in [nil, ""] do
    Multi.run(multi, :placement_movement, fn _repo, %{animal: animal} ->
      Repo.insert(
        Movement.changeset(%Movement{}, %{
          "farm_id" => farm_id,
          "animal_id" => animal.id,
          "to_pen_id" => pen_id,
          "reason" => "placement",
          "quantity" => animal.quantity,
          "moved_at" => Date.utc_today()
        })
      )
    end)
  end

  defp maybe_seed_initial_movement(multi, _, _, _), do: multi

  # Batch with initial pen — seed a placement row covering the whole batch.
  defp maybe_seed_placement(multi, "batch", pen_id) when pen_id not in [nil, ""] do
    Multi.run(multi, :initial_placement, fn _repo, %{animal: animal} ->
      Repo.insert(
        Placement.changeset(%Placement{}, %{
          animal_id: animal.id,
          pen_id: pen_id,
          quantity: animal.quantity,
          placed_at: Date.utc_today()
        })
      )
    end)
  end

  defp maybe_seed_placement(multi, _, _), do: multi

  @doc """
  Creates multiple individual animals atomically (spreadsheet batch entry).

  Each entry is a map with animal fields (`:ear_tag`, `:stage`, `:sex`,
  `:breed`, `:dob`, `:current_pen_id`, `:notes`). Keys may be atoms or strings.

  Returns `{:ok, [animal, ...]}` on success,
  `{:error, {row_index, changeset}}` on failure.
  Any failure rolls back the entire batch.
  """
  def create_batch_animals(%Scope{farm: farm}, entries)
      when is_list(entries) and entries != [] do
    multi =
      entries
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {entry, i}, m ->
        attrs =
          entry
          |> stringify()
          |> Map.merge(%{
            "farm_id" => farm.id,
            "tracking_type" => "individual"
          })

        pen_id = Map.get(attrs, "current_pen_id")
        cs = Animal.changeset(%Animal{}, attrs)

        m
        |> Multi.insert({:animal, i}, cs)
        |> maybe_seed_initial_movement_keyed(i, pen_id, farm.id)
      end)

    case Repo.transaction(multi) do
      {:ok, changes} ->
        animals =
          0..(length(entries) - 1)
          |> Enum.map(&Map.fetch!(changes, {:animal, &1}))

        {:ok, animals}

      {:error, {:animal, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, _op, reason, _} ->
        {:error, reason}
    end
  end

  def create_batch_animals(_scope, []), do: {:error, :no_entries}

  defp maybe_seed_initial_movement_keyed(multi, _i, pen_id, _farm_id)
       when pen_id in [nil, ""],
       do: multi

  defp maybe_seed_initial_movement_keyed(multi, i, pen_id, farm_id) do
    Multi.run(multi, {:movement, i}, fn _repo, changes ->
      animal = Map.fetch!(changes, {:animal, i})

      Repo.insert(
        Movement.changeset(%Movement{}, %{
          "farm_id" => farm_id,
          "animal_id" => animal.id,
          "to_pen_id" => pen_id,
          "reason" => "placement",
          "quantity" => 1,
          "moved_at" => Date.utc_today()
        })
      )
    end)
  end

  def update_animal(%Scope{} = scope, %Animal{} = animal, attrs) do
    # Status is owned by domain events (service, farrowing, weaning,
    # movement, treatment) — never by the edit form. Drop it here so a
    # crafted POST can't silently shift an animal from `lactating` to
    # `sold` without producing the matching movement + audit trail.
    attrs = attrs |> stringify() |> Map.drop(["status"])

    # Batches: location changes go through record_movement/3; quantity is
    # owned by the context (set at create, decremented by departures) and
    # must not be hand-edited.
    attrs =
      if animal.tracking_type == "batch",
        do: Map.drop(attrs, ["current_pen_id", "quantity"]),
        else: attrs

    cs = Animal.changeset(animal, attrs)

    Multi.new()
    |> Multi.update(:animal, cs)
    |> audit_after(scope, "animal.updated", :animal, fn _ -> cs.changes end)
    |> Repo.transaction()
    |> unwrap(:animal)
  end

  def update_stage(%Scope{} = scope, %Animal{} = animal, new_stage) do
    update_animal(scope, animal, %{stage: new_stage})
  end

  ## Herd import (onboarding)

  @doc """
  Bulk-imports an existing herd at farm onboarding time.

  Each entry is a row map with the usual animal fields plus optional
  breeding metadata so the reproductive history starts coherent
  instead of collapsing every sow to `active`.

  Status handling:

  * `"active"`, `"open"`, `"dry"`, `"culled"` — animal only.
  * `"served"` — also requires `:last_served_at`; inserts an open
    `Peggy.Breeding.Service` so the sow has a real pregnancy to
    farrow / recheck.
  * `"lactating"` — also requires `:last_served_at` and
    `:last_farrowed_at`; inserts a closed service + a farrowing.
    If `:born_alive > 0` a litter batch is created and linked.

  Atomic: any row failure rolls back the whole import.

  Returns `{:ok, [animal, ...]}` or `{:error, {row_index, changeset_or_reason}}`.
  """
  def import_herd(%Scope{farm: farm} = scope, rows) when is_list(rows) and rows != [] do
    multi =
      rows
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {row, i}, m ->
        insert_herd_row(m, scope, farm, stringify(row || %{}), i)
      end)

    case Repo.transaction(multi) do
      {:ok, changes} ->
        animals =
          0..(length(rows) - 1)
          |> Enum.map(&Map.fetch!(changes, {:animal, &1}))

        {:ok, animals}

      {:error, {:animal, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, {:service, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, {:farrowing, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, {:validate, i}, reason, _} ->
        {:error, {i, reason}}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  def import_herd(_scope, []), do: {:error, :no_rows}

  defp insert_herd_row(multi, scope, farm, row, i) do
    status = Map.get(row, "status") || "active"
    tracking_type = Map.get(row, "tracking_type") || "individual"

    animal_attrs =
      row
      |> Map.put("farm_id", farm.id)
      |> Map.put("status", status)
      |> Map.put("tracking_type", tracking_type)
      |> Map.drop(["last_served_at", "last_farrowed_at", "born_alive"])

    multi =
      multi
      |> Multi.insert({:animal, i}, Animal.changeset(%Animal{}, animal_attrs))
      |> Multi.run({:audit_animal, i}, fn _repo, changes ->
        a = Map.fetch!(changes, {:animal, i})

        Audit.log_now!(scope, "animal.imported",
          entity_type: "animal",
          entity_id: a.id,
          changes: %{
            "tracking_type" => a.tracking_type,
            "stage" => a.stage,
            "status" => a.status
          }
        )

        {:ok, :logged}
      end)

    case status do
      "served" -> insert_served_service(multi, farm, row, i)
      "lactating" -> insert_lactating_history(multi, scope, farm, row, i)
      _ -> multi
    end
  end

  defp insert_served_service(multi, farm, row, i) do
    served_at = row["last_served_at"]

    if is_nil(served_at) or served_at == "" do
      Multi.run(multi, {:validate, i}, fn _, _ ->
        {:error, "last_served_at is required when status is \"served\""}
      end)
    else
      Multi.run(multi, {:service, i}, fn repo, changes ->
        sow = Map.fetch!(changes, {:animal, i})

        %Peggy.Breeding.Service{}
        |> Peggy.Breeding.Service.changeset(%{
          "farm_id" => farm.id,
          "sow_id" => sow.id,
          "boar_id" => row["boar_id"],
          "service_type" => row["service_type"] || "ai",
          "served_at" => served_at
        })
        |> repo.insert()
      end)
    end
  end

  defp insert_lactating_history(multi, scope, farm, row, i) do
    served_at = row["last_served_at"]
    farrowed_at = row["last_farrowed_at"]
    born_alive = parse_int(row["born_alive"]) || 0
    pen_id = row["current_pen_id"] || row["pen_id"]

    cond do
      is_nil(served_at) or served_at == "" ->
        Multi.run(multi, {:validate, i}, fn _, _ ->
          {:error, "last_served_at is required when status is \"lactating\""}
        end)

      is_nil(farrowed_at) or farrowed_at == "" ->
        Multi.run(multi, {:validate, i}, fn _, _ ->
          {:error, "last_farrowed_at is required when status is \"lactating\""}
        end)

      true ->
        multi
        |> Multi.run({:service, i}, fn repo, changes ->
          sow = Map.fetch!(changes, {:animal, i})

          %Peggy.Breeding.Service{}
          |> Peggy.Breeding.Service.changeset(%{
            "farm_id" => farm.id,
            "sow_id" => sow.id,
            "boar_id" => row["boar_id"],
            "service_type" => row["service_type"] || "ai",
            "served_at" => served_at,
            "result" => "farrowing",
            "result_at" => farrowed_at
          })
          |> repo.insert()
        end)
        |> Multi.run({:farrowing, i}, fn repo, changes ->
          sow = Map.fetch!(changes, {:animal, i})
          service = Map.fetch!(changes, {:service, i})

          %Peggy.Breeding.Farrowing{}
          |> Peggy.Breeding.Farrowing.changeset(%{
            "farm_id" => farm.id,
            "sow_id" => sow.id,
            "service_id" => service.id,
            "pen_id" => pen_id,
            "farrowed_at" => farrowed_at,
            "born_alive" => born_alive
          })
          |> repo.insert()
        end)
        |> maybe_insert_litter(scope, farm, row, i, born_alive)
    end
  end

  defp maybe_insert_litter(multi, _scope, _farm, _row, _i, 0), do: multi

  defp maybe_insert_litter(multi, _scope, farm, row, i, born_alive) do
    Multi.run(multi, {:litter, i}, fn repo, changes ->
      sow = Map.fetch!(changes, {:animal, i})
      farrowing = Map.fetch!(changes, {:farrowing, i})

      Animal.piglet_changeset(%Animal{}, %{
        "tracking_type" => "batch",
        "stage" => "piglet",
        "status" => "active",
        "quantity" => born_alive,
        "dob" => row["last_farrowed_at"],
        "dam_id" => sow.id,
        "sire_id" => row["boar_id"],
        "farrowing_id" => farrowing.id,
        "farm_id" => farm.id
      })
      |> repo.insert()
    end)
  end

  ## Movements

  @departure_reasons ~w(sale slaughter death farm_transfer)
  @departure_statuses %{
    "sale" => "sold",
    "slaughter" => "slaughtered",
    "death" => "deceased",
    "farm_transfer" => "transferred"
  }

  def record_movement(%Scope{farm: farm} = scope, %Animal{farm_id: fid} = animal, attrs)
      when fid == farm.id do
    attrs =
      attrs
      |> stringify()
      |> Map.merge(%{"farm_id" => farm.id, "animal_id" => animal.id})
      |> Map.put_new("quantity", animal.quantity)

    case animal.tracking_type do
      "individual" -> record_individual_movement(scope, animal, attrs)
      "batch" -> record_batch_movement(scope, animal, attrs)
    end
  end

  @doc """
  Records many batch movements for one batch animal atomically.

  Supported reasons: `"placement"` and `"pen_transfer"` — the two
  operations that happen in the large-batch spreadsheet-entry workflow.
  Other reasons (departures, adjustments) remain single-entry through
  `record_movement/3`.

  Each entry is a map with `:reason`, `:quantity`, `:to_pen_id` (always),
  `:from_pen_id` (required for `pen_transfer`), `:moved_at`, `:notes`.
  Keys may be atoms or strings.

  Validates the aggregate budget (unplaced qty for placements, per-pen
  balance for transfers) up front, projecting each row's effect onto a
  running state, so the caller gets the offending row index without
  starting a DB transaction.

  Returns `{:ok, [movement, ...]}` on success, `{:error, {row_index, cs}}`
  or `{:error, reason}` on failure. Any failure rolls back the entire
  batch — no partial writes.
  """
  def record_batch_movements(
        %Scope{farm: farm} = scope,
        %Animal{farm_id: fid, tracking_type: "batch"} = animal,
        entries
      )
      when fid == farm.id and is_list(entries) and entries != [] do
    with {:ok, normalized} <- normalize_batch_entries(animal, entries) do
      multi =
        normalized
        |> Enum.with_index()
        |> Enum.reduce(Multi.new(), fn {entry, i}, m ->
          add_batch_entry_to_multi(m, scope, animal, entry, i)
        end)

      case Repo.transaction(multi) do
        {:ok, changes} ->
          movements =
            0..(length(entries) - 1)
            |> Enum.map(&Map.fetch!(changes, {:movement, &1}))

          {:ok, movements}

        {:error, {:source, i}, reason, _} ->
          {:error, {i, reason}}

        {:error, {:movement, i}, cs, _} ->
          {:error, {i, cs}}

        {:error, _op, reason, _} ->
          {:error, reason}
      end
    end
  end

  def record_batch_movements(_scope, %Animal{tracking_type: "individual"}, _entries),
    do: {:error, :batch_only}

  def record_batch_movements(_scope, _animal, []),
    do: {:error, :no_entries}

  @doc """
  Records many pen-moves for individual animals atomically.

  This is the bulk counterpart to `record_movement/3` for individual
  tracking — every entry moves one animal to a destination pen. The
  reason is inferred from the animal's current state:

    * no `current_pen_id` → `"placement"` (first assignment)
    * has `current_pen_id` → `"pen_transfer"` (from that pen)

  Each entry is a map with `:animal_id`, `:to_pen_id`, and optional
  `:moved_at`, `:notes`. Keys may be atoms or strings.

  Validates per-entry before starting the transaction: animal must
  belong to the scoped farm, be individual, be active, not be already
  in the destination pen, and each animal may appear only once per
  batch (otherwise later rows would see stale pen state).

  Returns `{:ok, [movement, ...]}` on success, `{:error, {row_index,
  changeset_or_reason}}` on failure. Any failure rolls back the whole
  batch — no partial writes.
  """
  def record_bulk_individual_moves(%Scope{farm: farm} = scope, entries)
      when is_list(entries) and entries != [] do
    with {:ok, normalized} <- normalize_bulk_individual_entries(farm, entries) do
      multi =
        normalized
        |> Enum.with_index()
        |> Enum.reduce(Multi.new(), fn {entry, i}, m ->
          add_bulk_individual_entry_to_multi(m, scope, entry, i)
        end)

      case Repo.transaction(multi) do
        {:ok, changes} ->
          movements =
            0..(length(entries) - 1)
            |> Enum.map(&Map.fetch!(changes, {:movement, &1}))

          {:ok, movements}

        {:error, {:movement, i}, cs, _} ->
          {:error, {i, cs}}

        {:error, {:animal, i}, cs, _} ->
          {:error, {i, cs}}

        {:error, _op, reason, _} ->
          {:error, reason}
      end
    end
  end

  def record_bulk_individual_moves(_scope, []), do: {:error, :no_entries}

  defp record_individual_movement(_scope, %Animal{} = _animal, %{"reason" => reason} = attrs)
       when reason in ["adjustment_loss", "adjustment_gain"] do
    {:error,
     Movement.changeset(%Movement{}, attrs)
     |> Ecto.Changeset.add_error(:reason, "adjustments are only valid for batch animals")}
  end

  defp record_individual_movement(_scope, %Animal{} = _animal, %{"reason" => reason} = attrs)
       when reason in ["foster_on", "foster_off"] do
    {:error,
     Movement.changeset(%Movement{}, attrs)
     |> Ecto.Changeset.add_error(:reason, "fostering is only valid for piglet batches")}
  end

  defp record_individual_movement(scope, %Animal{} = animal, attrs) do
    reason = Map.get(attrs, "reason")
    to_pen_id = Map.get(attrs, "to_pen_id")

    # Auto-capture from_pen_id from the animal's current pen so undo can
    # restore it even when the caller omits the field.
    attrs =
      if is_nil(Map.get(attrs, "from_pen_id")) and not is_nil(animal.current_pen_id),
        do: Map.put(attrs, "from_pen_id", animal.current_pen_id),
        else: attrs

    # Store previous status on departure movements so they can be undone cleanly.
    attrs =
      if reason in @departure_reasons,
        do: Map.put(attrs, "previous_status", animal.status),
        else: attrs

    cs = Movement.changeset(%Movement{}, attrs)

    animal_updates =
      if reason in @departure_reasons do
        %{current_pen_id: nil, status: Map.fetch!(@departure_statuses, reason)}
      else
        %{current_pen_id: to_pen_id}
      end

    Multi.new()
    |> Multi.insert(:movement, cs)
    |> Multi.update(:animal, Animal.changeset(animal, animal_updates))
    |> audit_movement(scope, animal)
    |> Repo.transaction()
    |> unwrap(:movement)
  end

  defp record_batch_movement(scope, %Animal{} = animal, attrs) do
    reason = Map.get(attrs, "reason")

    # Foster events don't take a user-supplied pen — the batch's current
    # active placement is the pen. Resolve it and rewrite attrs so the
    # movement row carries the correct to_pen_id / from_pen_id, then fall
    # through to the same pipelines as adjustment_gain / adjustment_loss.
    case maybe_resolve_foster_pen(animal, reason, attrs) do
      {:error, cs} ->
        {:error, cs}

      {:ok, attrs} ->
        do_record_batch_movement_dispatch(scope, animal, attrs)
    end
  end

  defp do_record_batch_movement_dispatch(scope, %Animal{} = animal, attrs) do
    reason = Map.get(attrs, "reason")
    from_pen_id = parse_int(Map.get(attrs, "from_pen_id"))
    to_pen_id = parse_int(Map.get(attrs, "to_pen_id"))
    qty = parse_int(Map.get(attrs, "quantity"))
    moved_at = Map.get(attrs, "moved_at") || Date.utc_today()

    cond do
      # "placement" is the bootstrap op — it adds animals to a destination
      # pen without a source. Used when a batch is registered without an
      # initial pen, or when splitting a newly-arrived sub-batch.
      reason == "placement" ->
        record_batch_placement(scope, animal, %{
          attrs: attrs,
          to_pen_id: to_pen_id,
          qty: qty,
          moved_at: moved_at
        })

      # "adjustment_gain" — upward correction (miscounted at arrival,
      # unlogged births, etc.). Adds to a destination pen AND increments
      # the batch total. No source pen.
      #
      # "foster_on" shares this pipeline: same mechanics (destination pen +
      # quantity increment, no source pen), different reason tag so audit
      # history separates fostering from miscount corrections.
      reason in ["adjustment_gain", "foster_on"] ->
        record_batch_adjustment_gain(scope, animal, %{
          attrs: attrs,
          to_pen_id: to_pen_id,
          qty: qty,
          moved_at: moved_at
        })

      is_nil(from_pen_id) ->
        {:error, Movement.changeset(%Movement{}, attrs) |> missing(:from_pen_id)}

      is_nil(qty) or qty < 1 ->
        {:error, Movement.changeset(%Movement{}, attrs) |> missing(:quantity)}

      reason == "pen_transfer" and is_nil(to_pen_id) ->
        {:error, Movement.changeset(%Movement{}, attrs) |> missing(:to_pen_id)}

      true ->
        do_record_batch_movement(scope, animal, %{
          attrs: attrs,
          reason: reason,
          from_pen_id: from_pen_id,
          to_pen_id: to_pen_id,
          qty: qty,
          moved_at: moved_at
        })
    end
  end

  # Piglet batches have exactly one active placement (a litter stays with
  # its dam). Foster events don't ask the user for a pen — we look it up.
  # Reject 0 placements (batch not placed) and >1 placements (ambiguous;
  # not a normal piglet-litter shape) with a clear error.
  defp maybe_resolve_foster_pen(%Animal{} = animal, reason, attrs)
       when reason in ["foster_on", "foster_off"] do
    cond do
      animal.stage != "piglet" ->
        {:error,
         Movement.changeset(%Movement{}, attrs)
         |> Ecto.Changeset.add_error(:reason, "fostering is only valid for piglet batches")}

      true ->
        case Repo.all(
               from p in Placement,
                 where: p.animal_id == ^animal.id and is_nil(p.removed_at),
                 select: p.pen_id
             ) do
          [pen_id] ->
            key = if reason == "foster_on", do: "to_pen_id", else: "from_pen_id"
            {:ok, Map.put(attrs, key, pen_id)}

          [] ->
            {:error,
             Movement.changeset(%Movement{}, attrs)
             |> Ecto.Changeset.add_error(
               :reason,
               "cannot foster — batch has no active placement"
             )}

          _many ->
            {:error,
             Movement.changeset(%Movement{}, attrs)
             |> Ecto.Changeset.add_error(
               :reason,
               "cannot foster — batch is split across multiple pens"
             )}
        end
    end
  end

  defp maybe_resolve_foster_pen(_animal, _reason, attrs), do: {:ok, attrs}

  defp record_batch_adjustment_gain(scope, %Animal{} = animal, ctx) do
    %{attrs: attrs, to_pen_id: to_pen_id, qty: qty, moved_at: moved_at} = ctx

    cond do
      is_nil(to_pen_id) ->
        {:error, Movement.changeset(%Movement{}, attrs) |> missing(:to_pen_id)}

      is_nil(qty) or qty < 1 ->
        {:error, Movement.changeset(%Movement{}, attrs) |> missing(:quantity)}

      true ->
        cs = Movement.changeset(%Movement{}, attrs)
        reason = Map.get(attrs, "reason")

        Multi.new()
        |> Multi.insert(:movement, cs)
        |> maybe_upsert_destination(reason, animal.id, to_pen_id, qty, moved_at)
        |> Multi.run(:animal, fn _repo, _ ->
          animal
          |> Animal.changeset(%{quantity: animal.quantity + qty})
          |> Repo.update()
        end)
        |> audit_movement(scope, animal)
        |> Repo.transaction()
        |> unwrap(:movement)
    end
  end

  defp record_batch_placement(scope, %Animal{} = animal, ctx) do
    %{attrs: attrs, to_pen_id: to_pen_id, qty: qty, moved_at: moved_at} = ctx

    unplaced = unplaced_quantity(animal)

    cond do
      is_nil(to_pen_id) ->
        {:error, Movement.changeset(%Movement{}, attrs) |> missing(:to_pen_id)}

      is_nil(qty) or qty < 1 ->
        {:error, Movement.changeset(%Movement{}, attrs) |> missing(:quantity)}

      qty > unplaced ->
        {:error,
         Movement.changeset(%Movement{}, attrs)
         |> Ecto.Changeset.add_error(
           :quantity,
           "exceeds unplaced quantity (#{unplaced} remaining)"
         )}

      true ->
        cs = Movement.changeset(%Movement{}, attrs)

        Multi.new()
        |> Multi.insert(:movement, cs)
        |> maybe_upsert_destination("placement", animal.id, to_pen_id, qty, moved_at)
        |> audit_movement(scope, animal)
        |> Repo.transaction()
        |> unwrap(:movement)
    end
  end

  defp unplaced_quantity(%Animal{id: id, quantity: total}) do
    placed =
      Repo.one(
        from p in Placement,
          where: p.animal_id == ^id and is_nil(p.removed_at),
          select: coalesce(sum(p.quantity), 0)
      )

    total - placed
  end

  defp do_record_batch_movement(scope, %Animal{} = animal, ctx) do
    cs = Movement.changeset(%Movement{}, ctx.attrs)

    Multi.new()
    |> Multi.run(:source, fn _repo, _ ->
      case active_placement(animal.id, ctx.from_pen_id) do
        nil -> {:error, :no_source_placement}
        %Placement{quantity: q} when q < ctx.qty -> {:error, :insufficient_quantity}
        placement -> {:ok, placement}
      end
    end)
    |> Multi.insert(:movement, cs)
    |> Multi.run(:source_update, fn _repo, %{source: source} ->
      if source.quantity == ctx.qty do
        source
        |> Placement.changeset(%{removed_at: ctx.moved_at})
        |> Repo.update()
      else
        source
        |> Placement.changeset(%{quantity: source.quantity - ctx.qty})
        |> Repo.update()
      end
    end)
    |> maybe_upsert_destination(ctx.reason, animal.id, ctx.to_pen_id, ctx.qty, ctx.moved_at)
    |> maybe_decrement_batch_total(ctx.reason, animal, ctx.qty)
    |> audit_movement(scope, animal)
    |> Repo.transaction()
    |> unwrap(:movement)
  end

  defp maybe_upsert_destination(multi, reason, animal_id, to_pen_id, qty, moved_at)
       when reason in ["pen_transfer", "placement", "adjustment_gain", "foster_on"] do
    Multi.run(multi, :destination, fn _repo, _ ->
      case active_placement(animal_id, to_pen_id) do
        nil ->
          Repo.insert(
            Placement.changeset(%Placement{}, %{
              animal_id: animal_id,
              pen_id: to_pen_id,
              quantity: qty,
              placed_at: moved_at
            })
          )

        %Placement{} = existing ->
          existing
          |> Placement.changeset(%{quantity: existing.quantity + qty})
          |> Repo.update()
      end
    end)
  end

  defp maybe_upsert_destination(multi, _, _, _, _, _), do: multi

  # Departure reasons remove animals from the herd — decrement the
  # batch's `quantity`. If everything has left, flip status.
  defp maybe_decrement_batch_total(multi, reason, %Animal{} = animal, qty)
       when reason in @departure_reasons do
    Multi.run(multi, :animal, fn _repo, _ ->
      new_qty = animal.quantity - qty

      updates =
        if new_qty == 0 do
          %{quantity: 0, status: Map.fetch!(@departure_statuses, reason)}
        else
          %{quantity: new_qty}
        end

      animal
      |> Animal.changeset(updates)
      |> Repo.update()
    end)
  end

  # adjustment_loss corrects the batch total downward (unrecorded death,
  # miscount, escape). It decrements `quantity` but never flips status —
  # status changes belong to real departure events.
  #
  # foster_off follows the same mechanics: the piglet leaves this batch to
  # be fostered onto another dam's litter, so quantity drops at the source
  # pen with no destination within this batch.
  defp maybe_decrement_batch_total(multi, reason, %Animal{} = animal, qty)
       when reason in ["adjustment_loss", "foster_off"] do
    Multi.run(multi, :animal, fn _repo, _ ->
      animal
      |> Animal.changeset(%{quantity: max(animal.quantity - qty, 0)})
      |> Repo.update()
    end)
  end

  defp maybe_decrement_batch_total(multi, _, _, _), do: multi

  ## Batch-entry helpers (record_batch_movements/3)

  # Normalize input rows and project their effect onto a running placement
  # state so aggregate budget violations (unplaced exceeded, source pen
  # exceeded) surface with the row index before we touch the DB.
  defp normalize_batch_entries(%Animal{} = animal, entries) do
    proj = initial_projection(animal)

    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], proj}, fn {entry, i}, {:ok, acc, p} ->
      case normalize_batch_entry(animal, entry, p) do
        {:ok, norm, p2} -> {:cont, {:ok, [norm | acc], p2}}
        {:error, cs} -> {:halt, {:error, {i, cs}}}
      end
    end)
    |> case do
      {:ok, rev, _} -> {:ok, Enum.reverse(rev)}
      other -> other
    end
  end

  defp initial_projection(%Animal{id: id, quantity: total}) do
    per_pen =
      Repo.all(
        from p in Placement,
          where: p.animal_id == ^id and is_nil(p.removed_at),
          select: {p.pen_id, p.quantity}
      )
      |> Map.new()

    placed = per_pen |> Map.values() |> Enum.sum()
    %{per_pen: per_pen, unplaced: total - placed}
  end

  defp normalize_batch_entry(%Animal{} = animal, entry, proj) do
    reason = get_field_val(entry, :reason)
    qty = parse_int(get_field_val(entry, :quantity))
    from_pen_id = parse_int(get_field_val(entry, :from_pen_id))
    to_pen_id = parse_int(get_field_val(entry, :to_pen_id))
    moved_at = get_field_val(entry, :moved_at) || Date.utc_today()
    notes = get_field_val(entry, :notes)

    attrs = %{
      "reason" => reason,
      "quantity" => qty,
      "from_pen_id" => from_pen_id,
      "to_pen_id" => to_pen_id,
      "moved_at" => moved_at,
      "notes" => notes,
      "animal_id" => animal.id,
      "farm_id" => animal.farm_id
    }

    cs = Movement.changeset(%Movement{}, attrs) |> Map.put(:action, :validate)

    cond do
      not cs.valid? ->
        {:error, cs}

      reason == "placement" ->
        project_placement(cs, qty, to_pen_id, proj, attrs, moved_at)

      reason == "pen_transfer" ->
        project_transfer(cs, qty, from_pen_id, to_pen_id, proj, attrs, moved_at)

      true ->
        {:error, cs |> Ecto.Changeset.add_error(:reason, "not supported in batch entry")}
    end
  end

  defp project_placement(cs, qty, to_pen_id, proj, attrs, moved_at) do
    cond do
      is_nil(to_pen_id) ->
        {:error, cs |> missing(:to_pen_id)}

      qty > proj.unplaced ->
        {:error,
         cs
         |> Ecto.Changeset.add_error(
           :quantity,
           "exceeds unplaced quantity (#{proj.unplaced} remaining)"
         )}

      true ->
        proj2 =
          proj
          |> Map.update!(:unplaced, &(&1 - qty))
          |> update_in([:per_pen, to_pen_id], &((&1 || 0) + qty))

        norm = %{
          reason: "placement",
          qty: qty,
          from_pen_id: nil,
          to_pen_id: to_pen_id,
          moved_at: moved_at,
          attrs: attrs
        }

        {:ok, norm, proj2}
    end
  end

  defp project_transfer(cs, qty, from_pen_id, to_pen_id, proj, attrs, moved_at) do
    available = get_in(proj, [:per_pen, from_pen_id]) || 0

    cond do
      is_nil(from_pen_id) ->
        {:error, cs |> missing(:from_pen_id)}

      is_nil(to_pen_id) ->
        {:error, cs |> missing(:to_pen_id)}

      from_pen_id == to_pen_id ->
        {:error, cs |> Ecto.Changeset.add_error(:to_pen_id, "must differ from source pen")}

      available == 0 ->
        {:error, cs |> Ecto.Changeset.add_error(:from_pen_id, "pen has no active placement")}

      qty > available ->
        {:error,
         cs
         |> Ecto.Changeset.add_error(
           :quantity,
           "exceeds available in source pen (#{available} there)"
         )}

      true ->
        per_pen =
          if available == qty do
            Map.delete(proj.per_pen, from_pen_id)
          else
            Map.put(proj.per_pen, from_pen_id, available - qty)
          end
          |> Map.update(to_pen_id, qty, &(&1 + qty))

        proj2 = Map.put(proj, :per_pen, per_pen)

        norm = %{
          reason: "pen_transfer",
          qty: qty,
          from_pen_id: from_pen_id,
          to_pen_id: to_pen_id,
          moved_at: moved_at,
          attrs: attrs
        }

        {:ok, norm, proj2}
    end
  end

  # Append DB steps for one normalized entry, keyed by row index.
  # Within the outer transaction, later rows see earlier rows' writes —
  # so two placements into the same pen compose into one row naturally.
  defp add_batch_entry_to_multi(multi, scope, animal, %{reason: "placement"} = entry, i) do
    cs = Movement.changeset(%Movement{}, entry.attrs)

    multi
    |> Multi.insert({:movement, i}, cs)
    |> upsert_destination_keyed(i, animal.id, entry.to_pen_id, entry.qty, entry.moved_at)
    |> audit_movement_keyed(i, scope, animal)
  end

  defp add_batch_entry_to_multi(multi, scope, animal, %{reason: "pen_transfer"} = entry, i) do
    cs = Movement.changeset(%Movement{}, entry.attrs)

    multi
    |> Multi.run({:source, i}, fn _repo, _ ->
      case active_placement(animal.id, entry.from_pen_id) do
        nil -> {:error, :no_source_placement}
        %Placement{quantity: q} when q < entry.qty -> {:error, :insufficient_quantity}
        placement -> {:ok, placement}
      end
    end)
    |> Multi.insert({:movement, i}, cs)
    |> Multi.run({:source_update, i}, fn _repo, changes ->
      source = Map.fetch!(changes, {:source, i})

      if source.quantity == entry.qty do
        source |> Placement.changeset(%{removed_at: entry.moved_at}) |> Repo.update()
      else
        source
        |> Placement.changeset(%{quantity: source.quantity - entry.qty})
        |> Repo.update()
      end
    end)
    |> upsert_destination_keyed(i, animal.id, entry.to_pen_id, entry.qty, entry.moved_at)
    |> audit_movement_keyed(i, scope, animal)
  end

  defp upsert_destination_keyed(multi, i, animal_id, to_pen_id, qty, moved_at) do
    Multi.run(multi, {:destination, i}, fn _repo, _ ->
      case active_placement(animal_id, to_pen_id) do
        nil ->
          Repo.insert(
            Placement.changeset(%Placement{}, %{
              animal_id: animal_id,
              pen_id: to_pen_id,
              quantity: qty,
              placed_at: moved_at
            })
          )

        %Placement{} = existing ->
          existing
          |> Placement.changeset(%{quantity: existing.quantity + qty})
          |> Repo.update()
      end
    end)
  end

  defp audit_movement_keyed(multi, i, scope, %Animal{id: animal_id}) do
    Multi.run(multi, {:audit, i}, fn _repo, changes ->
      m = Map.fetch!(changes, {:movement, i})

      Audit.log_now!(scope, "movement.recorded",
        entity_type: :animal,
        entity_id: animal_id,
        changes:
          normalize_changes(%{
            reason: m.reason,
            from_pen_id: m.from_pen_id,
            to_pen_id: m.to_pen_id,
            quantity: m.quantity
          })
      )

      {:ok, :logged}
    end)
  end

  defp get_field_val(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  ## Bulk individual-move helpers (record_bulk_individual_moves/2)

  # Validate all entries up front, threading a MapSet of already-seen
  # animal ids so a duplicate row is rejected rather than silently
  # applied against stale state (the first move already shifted the
  # animal's current pen).
  defp normalize_bulk_individual_entries(farm, entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], MapSet.new()}, fn {entry, i}, {:ok, acc, seen} ->
      case normalize_bulk_individual_entry(farm, entry, seen) do
        {:ok, norm} ->
          {:cont, {:ok, [norm | acc], MapSet.put(seen, norm.animal.id)}}

        {:error, cs} ->
          {:halt, {:error, {i, cs}}}
      end
    end)
    |> case do
      {:ok, rev, _} -> {:ok, Enum.reverse(rev)}
      other -> other
    end
  end

  defp normalize_bulk_individual_entry(farm, entry, seen) do
    animal_id = parse_int(get_field_val(entry, :animal_id))
    to_pen_id = parse_int(get_field_val(entry, :to_pen_id))
    moved_at = get_field_val(entry, :moved_at) || Date.utc_today()
    notes = get_field_val(entry, :notes)

    cs = blank_movement_cs()

    cond do
      is_nil(animal_id) ->
        {:error, cs |> missing(:animal_id)}

      MapSet.member?(seen, animal_id) ->
        {:error, cs |> Ecto.Changeset.add_error(:animal_id, "duplicated in batch")}

      is_nil(to_pen_id) ->
        {:error, cs |> missing(:to_pen_id)}

      true ->
        validate_bulk_individual_animal(farm, animal_id, to_pen_id, moved_at, notes, cs)
    end
  end

  defp validate_bulk_individual_animal(farm, animal_id, to_pen_id, moved_at, notes, cs) do
    case Repo.get_by(Animal, id: animal_id, farm_id: farm.id) do
      nil ->
        {:error, cs |> Ecto.Changeset.add_error(:animal_id, "not found")}

      %Animal{tracking_type: "batch"} ->
        {:error, cs |> Ecto.Changeset.add_error(:animal_id, "not an individual animal")}

      %Animal{} = animal ->
        cond do
          not Animal.present_status?(animal.status) ->
            {:error, cs |> Ecto.Changeset.add_error(:animal_id, "is not active")}

          animal.current_pen_id == to_pen_id ->
            {:error, cs |> Ecto.Changeset.add_error(:to_pen_id, "animal is already in that pen")}

          true ->
            reason = if is_nil(animal.current_pen_id), do: "placement", else: "pen_transfer"

            {:ok,
             %{
               animal: animal,
               reason: reason,
               from_pen_id: animal.current_pen_id,
               to_pen_id: to_pen_id,
               moved_at: moved_at,
               notes: notes
             }}
        end
    end
  end

  defp blank_movement_cs do
    Movement.changeset(%Movement{}, %{}) |> Map.put(:action, :validate)
  end

  defp add_bulk_individual_entry_to_multi(multi, scope, entry, i) do
    attrs = %{
      "reason" => entry.reason,
      "quantity" => 1,
      "from_pen_id" => entry.from_pen_id,
      "to_pen_id" => entry.to_pen_id,
      "moved_at" => entry.moved_at,
      "notes" => entry.notes,
      "animal_id" => entry.animal.id,
      "farm_id" => entry.animal.farm_id
    }

    cs = Movement.changeset(%Movement{}, attrs)

    multi
    |> Multi.insert({:movement, i}, cs)
    |> Multi.update(
      {:animal, i},
      Animal.changeset(entry.animal, %{current_pen_id: entry.to_pen_id})
    )
    |> audit_movement_keyed(i, scope, entry.animal)
  end

  defp active_placement(animal_id, pen_id) when not is_nil(pen_id) do
    Repo.one(
      from p in Placement,
        where: p.animal_id == ^animal_id and p.pen_id == ^pen_id and is_nil(p.removed_at)
    )
  end

  defp active_placement(_, _), do: nil

  defp active_placement_query do
    from p in Placement, where: is_nil(p.removed_at), preload: [pen: :house]
  end

  defp audit_movement(multi, scope, %Animal{id: animal_id}) do
    Multi.run(multi, {:audit, "movement"}, fn _repo, %{movement: m} ->
      changes = %{
        reason: m.reason,
        from_pen_id: m.from_pen_id,
        to_pen_id: m.to_pen_id,
        quantity: m.quantity
      }

      Audit.log_now!(scope, "movement.recorded",
        entity_type: :animal,
        entity_id: animal_id,
        changes: normalize_changes(changes)
      )

      {:ok, :logged}
    end)
  end

  ## Undo last movement

  @doc """
  Undoes the most recent movement for an animal.

  Only the latest movement (highest id) can be undone — if earlier
  movements exist they must be undone first, preventing corrupt state.

  For individual animals:
  * `placement` → clears `current_pen_id`
  * `pen_transfer` → restores `current_pen_id` to `from_pen_id`
  * Departure reasons → restores `current_pen_id` + `status` (from
    `previous_status` stored on the movement). If the departure was
    triggered by a breeding service closure (death/cull), the service
    is also reopened atomically.

  For batch animals:
  * `placement` → decrements/removes destination placement
  * `pen_transfer` → reverses source + destination placements
  * `adjustment_gain` / `foster_on` → decrements quantity + destination placement
  * `adjustment_loss` / `foster_off` → increments quantity + source placement
  * Departure → increments quantity, restores `status` to `active` if
    the batch was fully departed, re-adds source placement

  Returns `{:ok, movement}` (the deleted movement) on success,
  `{:error, :no_movements}` when there is nothing to undo, or
  `{:error, reason}` on a transaction failure.
  """
  def undo_last_movement(
        %Scope{farm: farm} = scope,
        %Animal{farm_id: fid} = animal
      )
      when fid == farm.id do
    case fetch_last_movement(animal) do
      nil ->
        {:error, :no_movements}

      movement ->
        multi =
          Multi.new()
          |> Multi.delete(:movement, movement)
          |> reverse_animal_state(scope, animal, movement)
          |> audit_undo(scope, animal, movement)

        case Repo.transaction(multi) do
          {:ok, %{movement: m}} -> {:ok, m}
          {:error, :movement, cs, _} -> {:error, cs}
          {:error, _step, reason, _} -> {:error, reason}
        end
    end
  end

  defp fetch_last_movement(%Animal{id: id}) do
    Repo.one(
      from m in Movement,
        where: m.animal_id == ^id,
        order_by: [desc: m.id],
        limit: 1
    )
  end

  ## Individual and batch reversals

  defp reverse_animal_state(multi, scope, %Animal{tracking_type: "individual"} = animal, m) do
    reverse_individual(multi, scope, animal, m)
  end

  defp reverse_animal_state(multi, _scope, %Animal{tracking_type: "batch"} = animal, m) do
    reverse_batch(multi, animal, m)
  end

  defp reverse_individual(multi, _scope, animal, %{reason: "placement"}) do
    Multi.update(multi, :animal, Ecto.Changeset.change(animal, %{current_pen_id: nil}))
  end

  defp reverse_individual(multi, _scope, animal, %{
         reason: "pen_transfer",
         from_pen_id: from_pen_id
       }) do
    Multi.update(multi, :animal, Ecto.Changeset.change(animal, %{current_pen_id: from_pen_id}))
  end

  defp reverse_individual(multi, scope, animal, %{reason: reason} = movement)
       when reason in @departure_reasons do
    prev_status = movement.previous_status || "active"

    multi
    |> Multi.update(
      :animal,
      Ecto.Changeset.change(animal, %{
        current_pen_id: movement.from_pen_id,
        status: prev_status
      })
    )
    |> maybe_reopen_linked_service(scope, animal, movement)
  end

  defp reverse_individual(multi, _scope, _animal, _movement), do: multi

  # When undoing a departure (death/sale) for an individual animal, check if
  # it was linked to a service closed with death/cull and reopen it.
  defp maybe_reopen_linked_service(multi, scope, animal, %{reason: reason})
       when reason in ["death", "sale"] do
    Multi.run(multi, :reopen_service, fn repo, _ ->
      case repo.one(
             from s in Peggy.Breeding.Service,
               where:
                 s.farm_id == ^scope.farm.id and
                   s.sow_id == ^animal.id and
                   s.result in ["death", "cull"] and
                   is_nil(s.deleted_at),
               order_by: [desc: s.id],
               limit: 1
           ) do
        nil ->
          {:ok, nil}

        service ->
          service
          |> Peggy.Breeding.Service.reopen_changeset()
          |> repo.update()
      end
    end)
  end

  defp maybe_reopen_linked_service(multi, _scope, _animal, _movement), do: multi

  ## Batch reversals

  defp reverse_batch(multi, animal, %{reason: "placement", to_pen_id: to_pen_id, quantity: qty}) do
    Multi.run(multi, :batch, fn repo, _ ->
      decrement_or_remove_placement(repo, animal.id, to_pen_id, qty)
      {:ok, animal}
    end)
  end

  defp reverse_batch(multi, animal, %{
         reason: "pen_transfer",
         from_pen_id: from_pen_id,
         to_pen_id: to_pen_id,
         quantity: qty
       }) do
    Multi.run(multi, :batch, fn repo, _ ->
      decrement_or_remove_placement(repo, animal.id, to_pen_id, qty)
      if from_pen_id, do: upsert_placement_qty(repo, animal.id, from_pen_id, qty)
      {:ok, animal}
    end)
  end

  defp reverse_batch(multi, animal, %{
         reason: reason,
         to_pen_id: to_pen_id,
         quantity: qty
       })
       when reason in ["adjustment_gain", "foster_on"] do
    Multi.run(multi, :batch, fn repo, _ ->
      decrement_or_remove_placement(repo, animal.id, to_pen_id, qty)
      new_qty = max(animal.quantity - qty, 0)

      # Bypass changeset (skips transition guard and batch-qty check);
      # undo is a trusted reversal of a prior valid state.
      animal
      |> Ecto.Changeset.change(%{quantity: new_qty})
      |> repo.update()
    end)
  end

  defp reverse_batch(multi, animal, %{
         reason: reason,
         from_pen_id: from_pen_id,
         quantity: qty
       })
       when reason in ["adjustment_loss", "foster_off"] do
    Multi.run(multi, :batch, fn repo, _ ->
      if from_pen_id, do: upsert_placement_qty(repo, animal.id, from_pen_id, qty)

      animal
      |> Ecto.Changeset.change(%{quantity: animal.quantity + qty})
      |> repo.update()
    end)
  end

  defp reverse_batch(multi, animal, %{reason: reason, from_pen_id: from_pen_id, quantity: qty})
       when reason in @departure_reasons do
    Multi.run(multi, :batch, fn repo, _ ->
      new_qty = animal.quantity + qty
      # Restore status to active only if the batch was fully departed (quantity was 0).
      # Use `change/2` to bypass the transition guard — undoing a departure
      # necessarily transitions from a departed (terminal) status back to active.
      updates =
        if animal.quantity == 0,
          do: %{quantity: new_qty, status: "active"},
          else: %{quantity: new_qty}

      result = animal |> Ecto.Changeset.change(updates) |> repo.update()
      if from_pen_id, do: upsert_placement_qty(repo, animal.id, from_pen_id, qty)
      result
    end)
  end

  defp reverse_batch(multi, _animal, _movement), do: multi

  defp decrement_or_remove_placement(repo, animal_id, pen_id, qty) do
    case active_placement(animal_id, pen_id) do
      nil ->
        :ok

      %Placement{quantity: current} when current <= qty ->
        repo.delete_all(
          from p in Placement,
            where: p.animal_id == ^animal_id and p.pen_id == ^pen_id and is_nil(p.removed_at)
        )

      %Placement{} = p ->
        p |> Placement.changeset(%{quantity: p.quantity - qty}) |> repo.update()
    end
  end

  defp upsert_placement_qty(repo, animal_id, pen_id, qty) do
    case active_placement(animal_id, pen_id) do
      nil ->
        repo.insert(
          Placement.changeset(%Placement{}, %{
            animal_id: animal_id,
            pen_id: pen_id,
            quantity: qty,
            placed_at: Date.utc_today()
          })
        )

      %Placement{} = existing ->
        existing
        |> Placement.changeset(%{quantity: existing.quantity + qty})
        |> repo.update()
    end
  end

  defp audit_undo(multi, scope, %Animal{id: animal_id}, movement) do
    Multi.run(multi, {:audit, "movement.undone"}, fn _repo, _ ->
      Audit.log_now!(scope, "movement.undone",
        entity_type: :animal,
        entity_id: animal_id,
        changes:
          normalize_changes(%{
            reason: movement.reason,
            moved_at: movement.moved_at,
            quantity: movement.quantity
          })
      )

      {:ok, :logged}
    end)
  end

  ## Helpers

  defp missing(cs, field), do: Ecto.Changeset.add_error(cs, field, "can't be blank")

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(i) when is_integer(i), do: i

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp maybe_filter(query, _field, nil), do: query
  defp maybe_filter(query, _field, ""), do: query
  defp maybe_filter(query, :stage, val), do: where(query, [a], a.stage == ^val)

  defp maybe_filter(query, :status, "present"), do: Animal.scope_present(query)
  defp maybe_filter(query, :status, "serviceable"), do: Animal.scope_serviceable(query)
  defp maybe_filter(query, :status, "breeding_herd"), do: Animal.scope_breeding_herd(query)
  defp maybe_filter(query, :status, "saleable"), do: Animal.scope_saleable(query)
  defp maybe_filter(query, :status, val), do: where(query, [a], a.status == ^val)

  defp audit_after(multi, scope, action, key, change_fn) do
    Multi.run(multi, {:audit, action}, fn _repo, changes ->
      row = Map.fetch!(changes, key)

      Audit.log_now!(scope, action,
        entity_type: key,
        entity_id: row.id,
        changes: normalize_changes(change_fn.(row))
      )

      {:ok, :logged}
    end)
  end

  defp normalize_changes(%{} = m) do
    Map.new(m, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(v) when is_atom(v) and not is_boolean(v) and not is_nil(v),
    do: to_string(v)

  defp stringify_value(v), do: v

  defp stringify(%{} = m) do
    Map.new(m, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp unwrap(result, key) do
    case result do
      {:ok, %{^key => record}} -> {:ok, record}
      {:error, ^key, changeset, _} -> {:error, changeset}
      {:error, _op, reason, _} -> {:error, reason}
    end
  end
end
