defmodule Peggy.Repo.Migrations.AddStatusChangedAtToAnimals do
  use Ecto.Migration

  def up do
    alter table(:animals) do
      add :status_changed_at, :utc_datetime
    end

    # Backfill: no reliable per-status-change timestamp exists for
    # historical rows, so seed with the row's inserted_at. From this
    # point on the trigger keeps the column accurate for every path
    # that mutates `status` (changesets, update_all, raw SQL, etc.).
    execute("UPDATE animals SET status_changed_at = inserted_at WHERE status_changed_at IS NULL")

    alter table(:animals) do
      modify :status_changed_at, :utc_datetime, null: false
    end

    execute("""
    CREATE OR REPLACE FUNCTION animals_touch_status_changed_at() RETURNS trigger AS $$
    BEGIN
      IF (TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status) THEN
        NEW.status_changed_at := timezone('utc', now());
      ELSIF (TG_OP = 'INSERT' AND NEW.status_changed_at IS NULL) THEN
        NEW.status_changed_at := timezone('utc', now());
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER animals_touch_status_changed_at
    BEFORE INSERT OR UPDATE ON animals
    FOR EACH ROW EXECUTE FUNCTION animals_touch_status_changed_at();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS animals_touch_status_changed_at ON animals")
    execute("DROP FUNCTION IF EXISTS animals_touch_status_changed_at()")

    alter table(:animals) do
      remove :status_changed_at
    end
  end
end
