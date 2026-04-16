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
    individuals =
      Repo.one(
        from a in Animal,
          where:
            a.farm_id == ^farm.id and a.current_pen_id == ^pen_id and a.status == "active" and
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
              a.status == "active",
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

  def update_animal(%Scope{} = scope, %Animal{} = animal, attrs) do
    # Batches: location changes go through record_movement/3; quantity is
    # owned by the context (set at create, decremented by departures) and
    # must not be hand-edited.
    attrs =
      if animal.tracking_type == "batch",
        do: attrs |> stringify() |> Map.drop(["current_pen_id", "quantity"]),
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

  defp record_individual_movement(_scope, %Animal{} = _animal, %{"reason" => reason} = attrs)
       when reason in ["adjustment_loss", "adjustment_gain"] do
    {:error,
     Movement.changeset(%Movement{}, attrs)
     |> Ecto.Changeset.add_error(:reason, "adjustments are only valid for batch animals")}
  end

  defp record_individual_movement(scope, %Animal{} = animal, attrs) do
    reason = Map.get(attrs, "reason")
    to_pen_id = Map.get(attrs, "to_pen_id")

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
      reason == "adjustment_gain" ->
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

  defp record_batch_adjustment_gain(scope, %Animal{} = animal, ctx) do
    %{attrs: attrs, to_pen_id: to_pen_id, qty: qty, moved_at: moved_at} = ctx

    cond do
      is_nil(to_pen_id) ->
        {:error, Movement.changeset(%Movement{}, attrs) |> missing(:to_pen_id)}

      is_nil(qty) or qty < 1 ->
        {:error, Movement.changeset(%Movement{}, attrs) |> missing(:quantity)}

      true ->
        cs = Movement.changeset(%Movement{}, attrs)

        Multi.new()
        |> Multi.insert(:movement, cs)
        |> maybe_upsert_destination("adjustment_gain", animal.id, to_pen_id, qty, moved_at)
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
       when reason in ["pen_transfer", "placement", "adjustment_gain"] do
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
  defp maybe_decrement_batch_total(multi, "adjustment_loss", %Animal{} = animal, qty) do
    Multi.run(multi, :animal, fn _repo, _ ->
      animal
      |> Animal.changeset(%{quantity: max(animal.quantity - qty, 0)})
      |> Repo.update()
    end)
  end

  defp maybe_decrement_batch_total(multi, _, _, _), do: multi

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
