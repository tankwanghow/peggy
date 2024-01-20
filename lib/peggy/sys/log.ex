defmodule Peggy.Sys.Log do
  use Peggy.Schema
  import Ecto.Changeset

  schema "logs" do
    field :action, :string
    field :delta, :string
    field :entity, :string
    field :entity_id, :binary_id
    belongs_to :user, Peggy.UserAccounts.User
    belongs_to :farm, Peggy.Sys.Farm

    field :email, :string, virtual: true

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:entity, :entity_id, :action, :delta, :farm_id, :user_id])
    |> validate_required([:entity, :entity_id, :action, :delta, :farm_id, :user_id])
  end
end
