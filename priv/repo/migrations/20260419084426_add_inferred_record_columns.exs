defmodule Peggy.Repo.Migrations.AddInferredRecordColumns do
  use Ecto.Migration

  # Adds the columns that mark a row as having been auto-created by a
  # downstream event entry (e.g. a service inferred from a farrowing).
  # See PR 4 design notes: "back-fill on demand".

  def change do
    alter table(:animals) do
      add :inferred, :boolean, default: false, null: false
      add :needs_review, :boolean, default: false, null: false
      add :created_via, :string
      add :origin_audit_id, references(:audit_logs, on_delete: :nilify_all)
    end

    alter table(:breeding_services) do
      add :inferred, :boolean, default: false, null: false
      add :created_via, :string
      add :origin_audit_id, references(:audit_logs, on_delete: :nilify_all)
    end

    alter table(:breeding_farrowings) do
      add :inferred, :boolean, default: false, null: false
      add :created_via, :string
      add :origin_audit_id, references(:audit_logs, on_delete: :nilify_all)
    end

    alter table(:breeding_weanings) do
      add :inferred, :boolean, default: false, null: false
      add :created_via, :string
      add :origin_audit_id, references(:audit_logs, on_delete: :nilify_all)
    end

    # Partial indexes — most rows will have inferred=false / needs_review=false,
    # so a partial index is far smaller and the dashboards we want to power
    # always filter "= true".
    create index(:animals, [:farm_id, :inferred],
             where: "inferred = true",
             name: :animals_farm_inferred_index
           )

    create index(:animals, [:farm_id, :needs_review],
             where: "needs_review = true",
             name: :animals_farm_needs_review_index
           )

    create index(:breeding_services, [:farm_id, :inferred],
             where: "inferred = true",
             name: :breeding_services_farm_inferred_index
           )

    create index(:breeding_farrowings, [:farm_id, :inferred],
             where: "inferred = true",
             name: :breeding_farrowings_farm_inferred_index
           )

    create index(:breeding_weanings, [:farm_id, :inferred],
             where: "inferred = true",
             name: :breeding_weanings_farm_inferred_index
           )
  end
end
