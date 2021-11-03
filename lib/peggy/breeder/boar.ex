defmodule Peggy.Breeder.Boar do
  use Ecto.Schema
  import Ecto.Changeset

  schema "boars" do
    field :breed, :string
    field :dob, :date
    belongs_to :farm, Peggy.Company.Farm
    belongs_to :location, Peggy.Farm.Location
    field :location_code, :string, virtual: true
    field :name, :string
    field :cull_date, :date
    timestamps()
  end

  @doc false
  def changeset(boar, farm_user, attrs) do
    boar
    |> cast(attrs, [:name, :breed, :location_id, :location_code, :farm_id, :dob, :cull_date])
    |> validate_required([:name, :farm_id])
    |> fill_messages(farm_user)
  end

  defp fill_messages(boar, farm_user) do
    code = get_change(boar, :location_code)
    breed = get_change(boar, :breed)

    {boar, messages} =
      if(code != nil) do
        loc = Peggy.Farm.get_location_by_code(code, farm_user)

        if loc do
          {put_change(boar, :location_id, loc.id), []}
        else
          {put_change(boar, :location_id, -1), [location_code: {"Is New", "is-link"}]}
        end
      else
        {boar, []}
      end
    messages =
      if breed != nil do
        Enum.concat(
          messages,
          if !Enum.find(Peggy.Breeder.datalist_breeds(farm_user), fn x -> x == breed end) do
            [breed: {"Is New", "is-link"}]
          else
            []
          end
        )
      else
        messages
      end

    Map.put_new(boar, :messages, messages)
  end
end
