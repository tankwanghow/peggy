defmodule Peggy.Breeder.Sow do
  use Ecto.Schema
  import Ecto.Changeset

  def status do
    ["Entered", "Paired", "Prefarrow", "Farrow", "Weaned", "Culled"]
  end

  schema "sows" do
    field :breed, :string, default: "NotEnter"
    field :code, :string
    field :dob, :date
    belongs_to :farm, Peggy.Company.Farm
    belongs_to :location, Peggy.Farm.Location
    field :location_code, :string, virtual: true
    field :parity, :integer
    field :cull_date, :date
    field :status, :string, default: "Entered"
    timestamps()
  end

  @doc false
  def changeset(sow, farm_user, attrs) do
    sow
    |> cast(attrs, [
      :code,
      :breed,
      :parity,
      :location_id,
      :farm_id,
      :dob,
      :cull_date,
      :status,
      :location_code
    ])
    |> validate_required([:code, :farm_id, :status])
    |> unsafe_validate_unique([:code, :farm_id], Peggy.Repo)
    |> fill_messages(farm_user)
  end

  defp fill_messages(sow, farm_user) do
    code = get_change(sow, :location_code)
    breed = get_change(sow, :breed)

    {sow, messages} =
      if(code != nil) do
        loc = Peggy.Farm.get_location_by_code(code, farm_user)

        if loc do
          {put_change(sow, :location_id, loc.id), []}
        else
          {put_change(sow, :location_id, -1), [location_code: {"Is New", "is-link"}]}
        end
      else
        {sow, []}
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

    Map.put_new(sow, :messages, messages)
  end
end
