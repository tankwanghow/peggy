defmodule Peggy.Locations do
  @moduledoc """
  Farm location hierarchy: houses → pens.

  Every function takes a `%Scope{}` and enforces `farm_id` isolation.
  Mutations write an `audit_logs` row in the same transaction.
  """

  import Ecto.Query
  alias Ecto.Multi
  alias Peggy.{Repo, Audit}
  alias Peggy.Accounts.Scope
  alias Peggy.Locations.{House, Pen}

  ## Queries

  def list_houses(%Scope{farm: farm}) do
    Repo.all(
      from h in House,
        where: h.farm_id == ^farm.id,
        order_by: h.code,
        preload: [pens: ^from(p in Pen, order_by: p.code)]
    )
  end

  def get_house!(%Scope{farm: farm}, id),
    do: Repo.get_by!(House, id: id, farm_id: farm.id)

  def get_pen!(%Scope{farm: farm}, id),
    do: Repo.get_by!(Pen, id: id, farm_id: farm.id)

  def list_pens(%Scope{farm: farm}, %House{id: hid, farm_id: fid}) when fid == farm.id do
    Repo.all(from p in Pen, where: p.house_id == ^hid, order_by: p.code)
  end

  def change_house(%House{} = h, attrs \\ %{}), do: House.changeset(h, attrs)
  def change_pen(%Pen{} = p, attrs \\ %{}), do: Pen.changeset(p, attrs)

  ## Houses

  def create_house(%Scope{farm: farm} = scope, attrs) do
    attrs = Map.put(stringify(attrs), "farm_id", farm.id)
    cs = House.changeset(%House{}, attrs)

    Multi.new()
    |> Multi.insert(:house, cs)
    |> audit_after(scope, "house.created", :house, fn h ->
      %{name: h.name, code: h.code, purpose: h.purpose}
    end)
    |> Repo.transaction()
    |> unwrap(:house)
  end

  def update_house(%Scope{} = scope, %House{} = house, attrs) do
    cs = House.changeset(house, attrs)

    Multi.new()
    |> Multi.update(:house, cs)
    |> audit_after(scope, "house.updated", :house, fn _ -> cs.changes end)
    |> Repo.transaction()
    |> unwrap(:house)
  end

  def delete_house(%Scope{} = scope, %House{} = house) do
    Multi.new()
    |> Multi.delete(:house, house)
    |> Audit.log!(scope, "house.deleted",
      entity_type: :house,
      entity_id: house.id,
      changes: %{name: house.name, code: house.code}
    )
    |> Repo.transaction()
    |> unwrap(:house)
  end

  ## Pens

  def create_pen(%Scope{farm: farm} = scope, %House{id: house_id, farm_id: fid}, attrs)
      when fid == farm.id do
    attrs = attrs |> stringify() |> Map.merge(%{"farm_id" => farm.id, "house_id" => house_id})
    cs = Pen.changeset(%Pen{}, attrs)

    Multi.new()
    |> Multi.insert(:pen, cs)
    |> audit_after(scope, "pen.created", :pen, fn p ->
      %{code: p.code, capacity: p.capacity, status: p.status}
    end)
    |> Repo.transaction()
    |> unwrap(:pen)
  end

  def update_pen(%Scope{} = scope, %Pen{} = pen, attrs) do
    cs = Pen.changeset(pen, attrs)

    Multi.new()
    |> Multi.update(:pen, cs)
    |> audit_after(scope, "pen.updated", :pen, fn _ -> cs.changes end)
    |> Repo.transaction()
    |> unwrap(:pen)
  end

  @doc """
  Insert many pens for a house in a single transaction. Returns
  `{:ok, pens}` or `{:error, index, changeset}` pointing to the first
  row that failed validation. One audit row covers the whole batch.
  """
  def bulk_create_pens(%Scope{farm: farm} = scope, %House{id: house_id, farm_id: fid}, rows)
      when fid == farm.id and is_list(rows) do
    multi =
      rows
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {attrs, idx}, acc ->
        attrs =
          attrs |> stringify() |> Map.merge(%{"farm_id" => farm.id, "house_id" => house_id})

        Multi.insert(acc, {:pen, idx}, Pen.changeset(%Pen{}, attrs))
      end)
      |> Multi.run(:audit, fn _repo, changes ->
        pens = collect_pens(changes)

        Audit.log_now!(scope, "pen.bulk_created",
          entity_type: :house,
          entity_id: house_id,
          changes: %{
            "count" => length(pens),
            "codes" => Enum.map(pens, & &1.code)
          }
        )

        {:ok, :logged}
      end)

    case Repo.transaction(multi) do
      {:ok, changes} -> {:ok, collect_pens(changes)}
      {:error, {:pen, idx}, cs, _} -> {:error, idx, cs}
    end
  end

  def bulk_delete_pens(%Scope{farm: farm} = scope, ids) when is_list(ids) do
    q = from p in Pen, where: p.farm_id == ^farm.id and p.id in ^ids
    pens = Repo.all(q)

    Multi.new()
    |> Multi.delete_all(:del, q)
    |> Multi.run(:audit, fn _repo, _ ->
      Audit.log_now!(scope, "pen.bulk_deleted",
        entity_type: :pen,
        entity_id: nil,
        changes: %{
          "count" => length(pens),
          "codes" => Enum.map(pens, & &1.code)
        }
      )

      {:ok, :logged}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{del: {n, _}}} -> {:ok, n}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  defp collect_pens(changes) do
    changes
    |> Enum.filter(fn {k, _} -> match?({:pen, _}, k) end)
    |> Enum.sort_by(fn {{:pen, i}, _} -> i end)
    |> Enum.map(fn {_, p} -> p end)
  end

  def delete_pen(%Scope{} = scope, %Pen{} = pen) do
    Multi.new()
    |> Multi.delete(:pen, pen)
    |> Audit.log!(scope, "pen.deleted",
      entity_type: :pen,
      entity_id: pen.id,
      changes: %{code: pen.code}
    )
    |> Repo.transaction()
    |> unwrap(:pen)
  end

  ## Helpers

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
