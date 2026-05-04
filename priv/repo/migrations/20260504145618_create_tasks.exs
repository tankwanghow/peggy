defmodule Peggy.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :kind, :string, null: false, default: "ad_hoc"
      add :ref_entity_type, :string
      add :ref_entity_id, :integer
      add :due_at, :date
      add :notes, :text

      add :assignee_user_id, references(:users, on_delete: :nilify_all)
      add :created_by_user_id, references(:users, on_delete: :nilify_all)
      add :completed_at, :utc_datetime
      add :completed_by_user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:farm_id, :completed_at])
    create index(:tasks, [:farm_id, :due_at])
    create index(:tasks, [:farm_id, :assignee_user_id])
  end
end
