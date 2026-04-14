defmodule Peggy.Repo.Migrations.CreateFarmInvitations do
  use Ecto.Migration

  def change do
    create table(:farm_invitations) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :email, :citext, null: false
      add :role, :string, null: false
      add :token, :binary, null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:farm_invitations, [:token])
    create index(:farm_invitations, [:farm_id])

    create unique_index(:farm_invitations, [:farm_id, :email],
             where: "accepted_at IS NULL",
             name: :farm_invitations_pending_unique
           )
  end
end
