defmodule Peggy.Repo.Migrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :accepted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:user_id, :farm_id])
    create index(:memberships, [:farm_id])
  end
end
