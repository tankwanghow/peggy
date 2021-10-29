defmodule Peggy.Farm do
  @moduledoc """
  The Farm context.
  """
  import Ecto.Query, warn: false
  import Peggy.Authorization
  alias Peggy.Repo

  alias Peggy.Farm.Location
  alias Peggy.Company.{Farm, FarmUser}

  @doc """
  Returns the list of locations.

  ## Examples

      iex> list_locations()
      [%Location{}, ...]

  """
  def list_locations(farm_user) do
    Repo.all(
      from l in Location,
        join: f in Farm,
        on: l.farm_id == f.id,
        join: fu in FarmUser,
        on:
          fu.farm_id == f.id and
            fu.user_id == ^farm_user.user_id and
            f.id == ^farm_user.farm_id and
            fu.role != "disable",
        order_by: [desc: l.updated_at, asc: l.code],
        select: l
    )
  end

  def list_locations(code, farm_user, page: page, per_page: per_page) do
    code = "%#{code}%"

    Repo.all(
      from l in Location,
        join: f in Farm,
        on: l.farm_id == f.id,
        join: fu in FarmUser,
        on:
          fu.farm_id == f.id and
            fu.user_id == ^farm_user.user_id and
            f.id == ^farm_user.farm_id and
            fu.role != "disable",
        where: ilike(l.code, ^code) or ilike(l.status, ^code),
        order_by: [desc: l.updated_at, asc: l.code],
        offset: ^((page - 1) * per_page),
        limit: ^per_page,
        select: l
    )
  end

  @doc """
  Gets a single location.

  Raises `Ecto.NoResultsError` if the Location does not exist.

  ## Examples

      iex> get_location!(123)
      %Location{}

      iex> get_location!(456)
      ** (Ecto.NoResultsError)

  """
  def get_location!(id), do: Repo.get!(Location, id)

  @doc """
  Creates a location.

  ## Examples

      iex> create_location(%{field: value})
      {:ok, %Location{}}

      iex> create_location(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_location(attrs \\ %{}, farm_user) do
    case can?(farm_user, :create_location) do
      {:allow, _} ->
        %Location{}
        |> Location.changeset(attrs)
        |> Repo.insert()

      {:forbid, msg} ->
        {:error, Location.changeset(%Location{}, attrs), msg}
    end
  end

  @doc """
  Updates a location.

  ## Examples

      iex> update_location(location, %{field: new_value})
      {:ok, %Location{}}

      iex> update_location(location, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_location(%Location{} = location, attrs, farm_user) do
    case can?(farm_user, :update_location) do
      {:allow, _} ->
        location
        |> Location.changeset(attrs)
        |> Repo.update()

      {:forbid, msg} ->
        {:error, Location.changeset(%Location{}, attrs), msg}
    end
  end

  @doc """
  Deletes a location.

  ## Examples

      iex> delete_location(location)
      {:ok, %Location{}}

      iex> delete_location(location)
      {:error, %Ecto.Changeset{}}

  """
  def delete_location(%Location{} = location, farm_user) do
    case can?(farm_user, :delete_location) do
      {:allow, _} ->
        Repo.delete(location)

      {:forbid, msg} ->
        {:error, location, msg}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking location changes.

  ## Examples

      iex> change_location(location)
      %Ecto.Changeset{data: %Location{}}

  """
  def change_location(%Location{} = location, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end
end
