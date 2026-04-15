defmodule Peggy.Audit.AuditLog do
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "audit_logs" do
    field :action, :string
    field :entity_type, :string
    field :entity_id, :string
    field :changes, :map, default: %{}
    field :inserted_at, :utc_datetime

    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :actor_user, Peggy.Accounts.User
  end
end
