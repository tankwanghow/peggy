defmodule Peggy.Tasks.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(ad_hoc check review service vaccinate)

  schema "tasks" do
    field :title, :string
    field :kind, :string, default: "ad_hoc"
    field :ref_entity_type, :string
    field :ref_entity_id, :integer
    field :due_at, :date
    field :notes, :string
    field :completed_at, :utc_datetime

    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :assignee_user, Peggy.Accounts.User
    belongs_to :created_by_user, Peggy.Accounts.User
    belongs_to :completed_by_user, Peggy.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :kind,
      :ref_entity_type,
      :ref_entity_id,
      :due_at,
      :notes,
      :farm_id,
      :assignee_user_id,
      :created_by_user_id,
      :completed_at,
      :completed_by_user_id
    ])
    |> validate_required([:title, :kind, :farm_id])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:title, min: 1, max: 200)
  end
end
