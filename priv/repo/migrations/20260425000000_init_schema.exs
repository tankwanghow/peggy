defmodule Peggy.Repo.Migrations.InitSchema do
  use Ecto.Migration

  @departed ~w(sold slaughtered deceased transferred reversed)

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS citext")
    execute("CREATE EXTENSION IF NOT EXISTS fuzzystrmatch")

    # ── Users / auth ─────────────────────────────────────────────────
    create table(:users) do
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :locale, :string, null: false, default: "en"
      add :timezone, :string, null: false, default: "Etc/UTC"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    # ── Farms ────────────────────────────────────────────────────────
    create table(:farms) do
      add :slug, :citext, null: false
      add :name, :string, null: false
      add :timezone, :string, null: false, default: "Etc/UTC"
      add :unit_system, :string, null: false, default: "metric"
      add :plan, :string, null: false, default: "free"
      add :seat_limit, :integer, null: false, default: 5
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create unique_index(:farms, [:slug])
    create index(:farms, [:deleted_at])

    # ── Memberships ──────────────────────────────────────────────────
    create table(:memberships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :invited_by_id, references(:users, on_delete: :nilify_all)
      add :accepted_at, :utc_datetime
      add :is_default, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:memberships, [:user_id, :farm_id])
    create index(:memberships, [:farm_id])

    create unique_index(:memberships, [:user_id],
             where: "is_default",
             name: :memberships_one_default_per_user
           )

    # ── Farm invitations ─────────────────────────────────────────────
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

    # ── Locations ────────────────────────────────────────────────────
    create table(:houses) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :purpose, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:houses, [:farm_id])
    create unique_index(:houses, [:farm_id, :code])

    create table(:pens) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :house_id, references(:houses, on_delete: :delete_all), null: false
      add :code, :string, null: false
      add :capacity, :integer, null: false, default: 0
      add :status, :string, null: false, default: "active"
      timestamps(type: :utc_datetime)
    end

    create index(:pens, [:farm_id])
    create index(:pens, [:house_id])
    create unique_index(:pens, [:house_id, :code])

    # ── Audit logs (immutable) ───────────────────────────────────────
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

    # ── Animals ──────────────────────────────────────────────────────
    create table(:animals) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :tracking_type, :string, null: false
      add :ear_tag, :string
      add :rfid, :string
      add :breed, :string
      add :stage, :string, null: false
      add :dob, :date
      add :quantity, :integer, default: 1, null: false
      add :status, :string, null: false, default: "active"
      add :legacy_parity, :integer, null: false, default: 0
      add :sire_id, references(:animals, on_delete: :nilify_all)
      add :dam_id, references(:animals, on_delete: :nilify_all)
      add :current_pen_id, references(:pens, on_delete: :nilify_all)
      add :notes, :text
      add :inferred, :boolean, default: false, null: false
      add :needs_review, :boolean, default: false, null: false
      add :created_via, :string
      add :origin_audit_id, references(:audit_logs, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:animals, [:farm_id])
    create index(:animals, [:current_pen_id])
    create index(:animals, [:sire_id])
    create index(:animals, [:dam_id])
    create index(:animals, [:farm_id, :stage])
    create index(:animals, [:farm_id, :status])

    create index(:animals, [:farm_id, :inferred],
             where: "inferred = true",
             name: :animals_farm_inferred_index
           )

    create index(:animals, [:farm_id, :needs_review],
             where: "needs_review = true",
             name: :animals_farm_needs_review_index
           )

    # Tag uniqueness scoped to present (non-departed) animals so a tag
    # can be reused once an animal departs.
    create unique_index(:animals, [:farm_id, :ear_tag],
             where: "status NOT IN ('#{Enum.join(@departed, "','")}')",
             name: :animals_farm_id_ear_tag_index
           )

    create unique_index(:animals, [:farm_id, :rfid],
             where: "status NOT IN ('#{Enum.join(@departed, "','")}')",
             name: :animals_farm_id_rfid_index
           )

    # ── Placements ───────────────────────────────────────────────────
    create table(:placements) do
      add :animal_id, references(:animals, on_delete: :delete_all), null: false
      add :pen_id, references(:pens, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :placed_at, :date, null: false
      add :removed_at, :date
      timestamps(type: :utc_datetime)
    end

    create index(:placements, [:animal_id])
    create index(:placements, [:pen_id])

    create unique_index(:placements, [:animal_id, :pen_id],
             where: "removed_at IS NULL",
             name: :placements_animal_id_pen_id_active_index
           )

    create constraint(:placements, :placements_quantity_positive, check: "quantity > 0")

    # ── Movements ────────────────────────────────────────────────────
    create table(:movements) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :animal_id, references(:animals, on_delete: :delete_all), null: false
      add :from_pen_id, references(:pens, on_delete: :restrict)
      add :to_pen_id, references(:pens, on_delete: :nilify_all)
      add :reason, :string, null: false
      add :quantity, :integer, default: 1, null: false
      add :moved_at, :date, null: false
      add :previous_status, :string
      add :notes, :text
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:movements, [:farm_id])
    create index(:movements, [:animal_id])
    create index(:movements, [:moved_at])
    create index(:movements, [:from_pen_id])

    # ── Breeding services ────────────────────────────────────────────
    create table(:breeding_services) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :sow_id, references(:animals, on_delete: :restrict), null: false
      add :boar_id, references(:animals, on_delete: :restrict)
      add :service_type, :string, null: false
      add :served_at, :date, null: false
      add :technician_user_id, references(:users, on_delete: :nilify_all)
      add :result, :string
      add :result_at, :date
      add :result_notes, :text
      add :notes, :text
      add :inferred, :boolean, default: false, null: false
      add :created_via, :string
      add :origin_audit_id, references(:audit_logs, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:breeding_services, [:farm_id])
    create index(:breeding_services, [:sow_id])
    create index(:breeding_services, [:boar_id])
    create index(:breeding_services, [:farm_id, :sow_id, :served_at])
    create index(:breeding_services, [:deleted_at])

    execute(
      "CREATE INDEX breeding_services_open_index ON breeding_services (farm_id, sow_id) WHERE result IS NULL",
      "DROP INDEX breeding_services_open_index"
    )

    create index(:breeding_services, [:farm_id, :inferred],
             where: "inferred = true",
             name: :breeding_services_farm_inferred_index
           )

    # ── Breeding farrowings ──────────────────────────────────────────
    create table(:breeding_farrowings) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :service_id, references(:breeding_services, on_delete: :restrict), null: false
      add :sow_id, references(:animals, on_delete: :restrict), null: false
      add :pen_id, references(:pens, on_delete: :restrict)
      add :farrowed_at, :date, null: false
      add :born_alive, :integer, null: false
      add :stillborn, :integer, null: false, default: 0
      add :mummified, :integer, null: false, default: 0
      add :total_birth_weight_g, :integer
      add :notes, :text
      add :inferred, :boolean, default: false, null: false
      add :created_via, :string
      add :origin_audit_id, references(:audit_logs, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:breeding_farrowings, [:farm_id])
    create index(:breeding_farrowings, [:sow_id])
    create index(:breeding_farrowings, [:farrowed_at])
    create index(:breeding_farrowings, [:deleted_at])

    create unique_index(:breeding_farrowings, [:service_id],
             where: "deleted_at IS NULL",
             name: :breeding_farrowings_service_id_active_index
           )

    create constraint(:breeding_farrowings, :breeding_farrowings_born_alive_non_neg,
             check: "born_alive >= 0"
           )

    create constraint(:breeding_farrowings, :breeding_farrowings_stillborn_non_neg,
             check: "stillborn >= 0"
           )

    create constraint(:breeding_farrowings, :breeding_farrowings_mummified_non_neg,
             check: "mummified >= 0"
           )

    create index(:breeding_farrowings, [:farm_id, :inferred],
             where: "inferred = true",
             name: :breeding_farrowings_farm_inferred_index
           )

    # animals.farrowing_id (added after breeding_farrowings exists)
    alter table(:animals) do
      add :farrowing_id, references(:breeding_farrowings, on_delete: :nilify_all)
    end

    create index(:animals, [:farrowing_id])

    # ── Breeding weanings ────────────────────────────────────────────
    create table(:breeding_weanings) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :farrowing_id, references(:breeding_farrowings, on_delete: :restrict), null: false
      add :batch_animal_id, references(:animals, on_delete: :nilify_all)
      add :weaned_at, :date, null: false
      add :weaned_count, :integer, null: false
      add :avg_wean_weight_g, :integer
      add :destination_pen_id, references(:pens, on_delete: :restrict)
      add :notes, :text
      add :inferred, :boolean, default: false, null: false
      add :created_via, :string
      add :origin_audit_id, references(:audit_logs, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:breeding_weanings, [:farm_id])
    create index(:breeding_weanings, [:batch_animal_id])
    create index(:breeding_weanings, [:deleted_at])

    create unique_index(:breeding_weanings, [:farrowing_id],
             where: "deleted_at IS NULL",
             name: :breeding_weanings_farrowing_id_active_index
           )

    create constraint(:breeding_weanings, :breeding_weanings_weaned_count_non_neg,
             check: "weaned_count >= 0"
           )

    create index(:breeding_weanings, [:farm_id, :inferred],
             where: "inferred = true",
             name: :breeding_weanings_farm_inferred_index
           )

    # movements.weaning_id (added after weanings exists)
    alter table(:movements) do
      add :weaning_id, references(:breeding_weanings, on_delete: :nilify_all)
    end

    create index(:movements, [:weaning_id])

    # ── Breeding litter events ───────────────────────────────────────
    create table(:breeding_litter_events) do
      add :farm_id, references(:farms, on_delete: :delete_all), null: false
      add :farrowing_id, references(:breeding_farrowings, on_delete: :restrict), null: false
      add :kind, :string, null: false
      add :quantity, :integer, null: false
      add :occurred_at, :date, null: false

      add :counterpart_farrowing_id,
          references(:breeding_farrowings, on_delete: :nilify_all)

      add :notes, :text
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime
      add :deleted_by_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime)
    end

    create index(:breeding_litter_events, [:farm_id])
    create index(:breeding_litter_events, [:farrowing_id])
    create index(:breeding_litter_events, [:counterpart_farrowing_id])
    create index(:breeding_litter_events, [:deleted_at])

    create constraint(:breeding_litter_events, :breeding_litter_events_quantity_positive,
             check: "quantity > 0"
           )

    create constraint(:breeding_litter_events, :breeding_litter_events_kind_valid,
             check: "kind IN ('death', 'foster_out', 'foster_in')"
           )

    create constraint(:breeding_litter_events, :breeding_litter_events_counterpart_consistent,
             check: """
             (kind = 'death' AND counterpart_farrowing_id IS NULL)
             OR
             (kind IN ('foster_out', 'foster_in') AND counterpart_farrowing_id IS NOT NULL)
             """
           )
  end

  def down do
    execute("DROP TRIGGER IF EXISTS audit_logs_no_update ON audit_logs")
    execute("DROP TRIGGER IF EXISTS audit_logs_no_delete ON audit_logs")
    execute("DROP FUNCTION IF EXISTS audit_logs_no_mutate()")

    drop table(:breeding_litter_events)

    alter table(:movements) do
      remove :weaning_id
    end

    drop table(:breeding_weanings)

    alter table(:animals) do
      remove :farrowing_id
    end

    drop table(:breeding_farrowings)
    drop table(:breeding_services)
    drop table(:movements)
    drop table(:placements)
    drop table(:animals)
    drop table(:audit_logs)
    drop table(:pens)
    drop table(:houses)
    drop table(:farm_invitations)
    drop table(:memberships)
    drop table(:farms)
    drop table(:users_tokens)
    drop table(:users)

    execute("DROP EXTENSION IF EXISTS fuzzystrmatch")
  end
end
