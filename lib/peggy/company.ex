defmodule Peggy.Company do
  @moduledoc """
  The Company context.
  """

  import Ecto.Query, warn: false
  alias Peggy.Repo

  alias Peggy.Company.Farm

  @doc """
  Returns the list of farms.

  ## Examples

      iex> list_farms()
      [%Farm{}, ...]

  """
  def list_farms do
    Repo.all(Farm)
  end

  @doc """
  Gets a single farm.

  Raises `Ecto.NoResultsError` if the Farm does not exist.

  ## Examples

      iex> get_farm!(123)
      %Farm{}

      iex> get_farm!(456)
      ** (Ecto.NoResultsError)

  """
  def get_farm!(id), do: Repo.get!(Farm, id)

  @doc """
  Creates a farm.

  ## Examples

      iex> create_farm(%{field: value})
      {:ok, %Farm{}}

      iex> create_farm(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_farm(attrs \\ %{}) do
    %Farm{}
    |> Farm.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a farm.

  ## Examples

      iex> update_farm(farm, %{field: new_value})
      {:ok, %Farm{}}

      iex> update_farm(farm, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_farm(%Farm{} = farm, attrs) do
    farm
    |> Farm.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a farm.

  ## Examples

      iex> delete_farm(farm)
      {:ok, %Farm{}}

      iex> delete_farm(farm)
      {:error, %Ecto.Changeset{}}

  """
  def delete_farm(%Farm{} = farm) do
    Repo.delete(farm)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking farm changes.

  ## Examples

      iex> change_farm(farm)
      %Ecto.Changeset{data: %Farm{}}

  """
  def change_farm(%Farm{} = farm, attrs \\ %{}) do
    Farm.changeset(farm, attrs)
  end
end
