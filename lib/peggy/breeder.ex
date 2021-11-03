defmodule Peggy.Breeder do
  @moduledoc """
  The Breeder context.
  """

  import Ecto.Query, warn: false
  alias Peggy.Repo
  import Peggy.Authorization
  alias Ecto.Multi

  alias Peggy.Breeder.Sow
  alias Peggy.Farm.Location
  alias Peggy.Company.{FarmUser, Farm}

  @doc """
  Returns the list of sows.

  ## Examples

      iex> list_sows()
      [%Sow{}, ...]

  """
  def datalist_breeds(farm_user) do
    Repo.all(
      from s in Sow,
        join: f in Farm,
        on: s.farm_id == f.id,
        join: fu in FarmUser,
        on:
          fu.farm_id == f.id and
            fu.user_id == ^farm_user.user_id and
            f.id == ^farm_user.farm_id and
            fu.role != "disable",
        distinct: s.breed,
        select: s.breed
    )
  end

  def list_sows(terms, farm_user, page: page, per_page: per_page) do
    Repo.all(
      from s in Sow,
        join: f in Farm,
        on: s.farm_id == f.id,
        join: fu in FarmUser,
        on:
          fu.farm_id == f.id and
            fu.user_id == ^farm_user.user_id and
            f.id == ^farm_user.farm_id and
            fu.role != "disable",
        left_join: l in Location,
        on: s.location_id == l.id,
        where: ^build_conditions(terms, [:code, :status, :location_code, :breed]),
        order_by: [desc: s.updated_at, asc: s.code],
        offset: ^((page - 1) * per_page),
        limit: ^per_page,
        select: %{
          id: s.id,
          code: s.code,
          location_code: l.code,
          parity: s.parity,
          cull_date: s.cull_date,
          dob: s.dob,
          breed: s.breed,
          status: s.status
        }
    )
  end

  defp build_conditions(terms, fields) do
    Enum.zip(
      fields,
      String.split(terms, "|")
      |> Enum.map(fn x -> "%#{String.trim(x)}%" end)
    )
    |> Enum.reject(fn {_k, v} -> v == "%%" end)
    |> Enum.reduce(true, fn
        {k, v}, true ->
          if k == :location_code do
            dynamic([s, f, fu, l], ilike(field(l, :code), ^v))
          else
            dynamic([s, f, fu, l], ilike(field(s, ^k), ^v))
          end

        {k, v}, acc ->
          if k == :location_code do
            dynamic([s, f, fu, l], ilike(field(l, :code), ^v) and ^acc)
          else
            dynamic([s, f, fu, l], ilike(field(s, ^k), ^v) and ^acc)
          end
        end)
  end

  @doc """
  Gets a single sow.

  Raises `Ecto.NoResultsError` if the Sow does not exist.

  ## Examples

      iex> get_sow!(123)
      %Sow{}

      iex> get_sow!(456)
      ** (Ecto.NoResultsError)

  """
  def get_sow!(id) do
    Repo.get!(
      from(s in Sow,
        left_join: l in Location,
        on: l.id == s.location_id,
        select: %Sow{
          id: s.id,
          code: s.code,
          location_code: l.code,
          parity: s.parity,
          cull_date: s.cull_date,
          dob: s.dob,
          breed: s.breed,
          status: s.status,
          location_id: s.location_id,
          farm_id: s.farm_id
        }
      ),
      id
    )
  end

  @doc """
  Creates a sow.

  ## Examples

      iex> create_sow(%{field: value})
      {:ok, %Sow{}}

      iex> create_sow(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_sow(attrs \\ %{}, farm_user) do
    case can?(farm_user, :create_sow) do
      {:allow, _} ->
        if attrs["location_code"] == "" do
          %Sow{}
          |> Sow.changeset(farm_user, attrs)
          |> Repo.insert()
        else
          loc = get_location_from_code(attrs["location_code"], farm_user)

          if loc == nil do
            {_, attrs} = Map.pop(attrs, "location_id")
            {location_code, attrs} = Map.pop(attrs, "location_code")

            Multi.new()
            |> Multi.insert(
              :location,
              Location.changeset(%Location{}, %{
                code: location_code,
                farm_id: farm_user.farm_id
              })
            )
            |> Multi.insert(:sow, fn %{location: location} ->
              Sow.changeset(%Sow{}, farm_user, Map.put_new(attrs, "location_id", location.id))
            end)
            |> Peggy.Repo.transaction()
            |> case do
              {:ok, %{sow: sow}} -> {:ok, sow}
              {:error, :sow, changeset, _} -> {:error, changeset}
            end
          end
        end

      {:forbid, msg} ->
        {:error, Sow.changeset(%Sow{}, farm_user, attrs), msg}
    end
  end

  defp get_location_from_code(code, farm_user) do
    if code != "" and code != nil do
      Peggy.Farm.get_location_by_code(code, farm_user)
    else
      nil
    end
  end

  @doc """
  Updates a sow.

  ## Examples

      iex> update_sow(sow, %{field: new_value})
      {:ok, %Sow{}}

      iex> update_sow(sow, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_sow(%Sow{} = sow, attrs, farm_user) do
    case can?(farm_user, :update_sow) do
      {:allow, _} ->
        loc = get_location_from_code(attrs["location_code"], farm_user)

        if loc == nil do
          {_, attrs} = Map.pop(attrs, "location_id")
          {location_code, attrs} = Map.pop(attrs, "location_code")

          Multi.new()
          |> Multi.insert(
            :location,
            Location.changeset(%Location{}, %{
              code: location_code,
              farm_id: farm_user.farm_id
            })
          )
          |> Multi.update(:sow, fn %{location: location} ->
            Sow.changeset(sow, farm_user, Map.put_new(attrs, "location_id", location.id))
          end)
          |> Peggy.Repo.transaction()
          |> case do
            {:ok, %{sow: sow}} -> {:ok, sow}
            {:error, :sow, changeset, _} -> {:error, changeset}
          end
        else
          sow
          |> Sow.changeset(farm_user, Map.replace(attrs, "location_id", loc.id))
          |> Repo.update()
        end

      {:forbid, msg} ->
        {:error, Sow.changeset(%Sow{}, farm_user, attrs), msg}
    end
  end

  @doc """
  Deletes a sow.

  ## Examples

      iex> delete_sow(sow)
      {:ok, %Sow{}}

      iex> delete_sow(sow)
      {:error, %Ecto.Changeset{}}

  """
  def delete_sow(%Sow{} = sow, farm_user) do
    case can?(farm_user, :delete_sow) do
      {:allow, _} ->
        Repo.delete(sow)

      {:forbid, msg} ->
        {:error, sow, msg}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking sow changes.

  ## Examples

      iex> change_sow(sow)
      %Ecto.Changeset{data: %Sow{}}

  """
  def change_sow(%Sow{} = sow, farm_user, attrs \\ %{}) do
    Sow.changeset(sow, farm_user, attrs)
  end

  alias Peggy.Breeder.Boar

  @doc """
  Returns the list of boars.

  ## Examples

      iex> list_boars()
      [%Boar{}, ...]

  """
  def list_boars(terms, farm_user, page: page, per_page: per_page) do
    Repo.all(
      from b in Boar,
        join: f in Farm,
        on: b.farm_id == f.id,
        join: fu in FarmUser,
        on:
          fu.farm_id == f.id and
            fu.user_id == ^farm_user.user_id and
            f.id == ^farm_user.farm_id and
            fu.role != "disable",
        left_join: l in Location,
        on: b.location_id == l.id,
        where: ^build_conditions(terms, [:name, :location_code, :breed]),
        order_by: [desc: b.updated_at, asc: b.name],
        offset: ^((page - 1) * per_page),
        limit: ^per_page,
        select: %{
          id: b.id,
          name: b.name,
          location_code: l.code,
          cull_date: b.cull_date,
          dob: b.dob,
          breed: b.breed
        }
    )
  end


  @doc """
  Gets a single boar.

  Raises `Ecto.NoResultsError` if the Boar does not exist.

  ## Examples

      iex> get_boar!(123)
      %Boar{}

      iex> get_boar!(456)
      ** (Ecto.NoResultsError)

  """
  def get_boar!(id) do
    Repo.get!(
      from(b in Boar,
        left_join: l in Location,
        on: l.id == b.location_id,
        select: %Boar{
          id: b.id,
          name: b.name,
          location_code: l.code,
          cull_date: b.cull_date,
          dob: b.dob,
          breed: b.breed,
          location_id: b.location_id,
          farm_id: b.farm_id
        }
      ),
      id
    )
  end

  @doc """
  Creates a boar.

  ## Examples

      iex> create_boar(%{field: value})
      {:ok, %Boar{}}

      iex> create_boar(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_boar(attrs \\ %{}, farm_user) do
    IO.inspect(farm_user)
    case can?(farm_user, :create_boar) do
      {:allow, _} ->
        if attrs["location_code"] == "" do
          %Boar{}
          |> Boar.changeset(farm_user, attrs)
          |> Repo.insert()
        else
          loc = get_location_from_code(attrs["location_code"], farm_user)

          if loc == nil do
            {_, attrs} = Map.pop(attrs, "location_id")
            {location_code, attrs} = Map.pop(attrs, "location_code")

            Multi.new()
            |> Multi.insert(
              :location,
              Location.changeset(%Location{}, %{
                code: location_code,
                farm_id: farm_user.farm_id
              })
            )
            |> Multi.insert(:boar, fn %{location: location} ->
              Boar.changeset(%Boar{}, farm_user, Map.put_new(attrs, "location_id", location.id))
            end)
            |> Peggy.Repo.transaction()
            |> case do
              {:ok, %{boar: boar}} -> {:ok, boar}
              {:error, :boar, changeset, _} -> {:error, changeset}
            end
          end
        end

      {:forbid, msg} ->
        {:error, Boar.changeset(%Boar{}, farm_user, attrs), msg}
    end
  end

  @doc """
  Updates a boar.

  ## Examples

      iex> update_boar(boar, %{field: new_value})
      {:ok, %Boar{}}

      iex> update_boar(boar, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_boar(%Boar{} = boar, attrs, farm_user) do
    case can?(farm_user, :update_boar) do
      {:allow, _} ->
        loc = get_location_from_code(attrs["location_code"], farm_user)

        if loc == nil do
          {_, attrs} = Map.pop(attrs, "location_id")
          {location_code, attrs} = Map.pop(attrs, "location_code")

          Multi.new()
          |> Multi.insert(
            :location,
            Location.changeset(%Location{}, %{
              code: location_code,
              farm_id: farm_user.farm_id
            })
          )
          |> Multi.update(:boar, fn %{location: location} ->
            Boar.changeset(boar, farm_user, Map.put_new(attrs, "location_id", location.id))
          end)
          |> Peggy.Repo.transaction()
          |> case do
            {:ok, %{boar: boar}} -> {:ok, boar}
            {:error, :boar, changeset, _} -> {:error, changeset}
          end
        else
          boar
          |> Boar.changeset(farm_user, Map.replace(attrs, "location_id", loc.id))
          |> Repo.update()
        end

      {:forbid, msg} ->
        {:error, Boar.changeset(%Boar{}, farm_user, attrs), msg}
    end
  end

  @doc """
  Deletes a boar.

  ## Examples

      iex> delete_boar(boar)
      {:ok, %Boar{}}

      iex> delete_boar(boar)
      {:error, %Ecto.Changeset{}}

  """
  def delete_boar(%Boar{} = boar, farm_user) do
    case can?(farm_user, :delete_boar) do
      {:allow, _} ->
        Repo.delete(boar)

      {:forbid, msg} ->
        {:error, boar, msg}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking boar changes.

  ## Examples

      iex> change_boar(boar)
      %Ecto.Changeset{data: %Boar{}}

  """
  def change_boar(%Boar{} = boar, farm_user, attrs \\ %{}) do
    Boar.changeset(boar, farm_user, attrs)
  end
end
