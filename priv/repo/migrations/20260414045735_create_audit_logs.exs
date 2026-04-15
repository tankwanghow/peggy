defmodule Peggy.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def up do
    create table(:audit_logs) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :actor_user_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :string
      add :changes, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:audit_logs, [:farm_id, :inserted_at])
    create index(:audit_logs, [:farm_id, :entity_type, :entity_id])

    # Immutable: reject UPDATE and DELETE regardless of role.
    execute("""
    CREATE OR REPLACE FUNCTION audit_logs_no_mutate() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'audit_logs is append-only (%)', TG_OP;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER audit_logs_no_update
    BEFORE UPDATE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION audit_logs_no_mutate();
    """)

    execute("""
    CREATE TRIGGER audit_logs_no_delete
    BEFORE DELETE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION audit_logs_no_mutate();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS audit_logs_no_update ON audit_logs")
    execute("DROP TRIGGER IF EXISTS audit_logs_no_delete ON audit_logs")
    execute("DROP FUNCTION IF EXISTS audit_logs_no_mutate()")
    drop table(:audit_logs)
  end
end
