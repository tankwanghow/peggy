defmodule Peggy.Repo.Migrations.CreateInviteUsers do
  use Ecto.Migration

  def change do
    create table(:invite_users) do
      add :email, :string
      add :role, :string
      add :farm_id, references(:farms, on_delete: :nothing)

      timestamps()
    end

    create index(:invite_users, [:farm_id])
  end
end
