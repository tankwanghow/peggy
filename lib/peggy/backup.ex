defmodule Peggy.Backup do
  @moduledoc """
  Per-farm backup and restore.

  ## Backup

  `export/1` walks every farm-scoped table (farms, houses, pens, animals,
  placements, movements, breeding services/farrowings/weanings, litter
  events, audit logs) and emits a single gzipped JSON document.

  Memberships, invitations, and user records are intentionally
  **excluded** — restore lands the data in a fresh farm owned by the
  importing user; collaborators are re-invited afterwards.

  ## Restore

  `import_to_new_farm/3` reads a gzipped JSON blob produced by `export/1`
  and recreates the farm under the given user with a new slug + name.
  All FKs are remapped to the new IDs.

  Foreign keys pointing at users (technician, assignee, audit actor,
  deleted_by, etc.) are **dropped** — the new owner becomes the
  implicit actor going forward.

  ## Format

  The on-disk shape (after gunzip) is:

      {
        "schema_version": 1,
        "exported_at": "2026-05-23T12:34:56Z",
        "farm": { ... breeding params ... },
        "tables": {
          "houses": [...],
          "pens": [...],
          "animals": [...],
          ...
        }
      }

  Bump `@schema_version` when the shape of any table changes; old files
  remain readable as long as `import_to_new_farm/3` handles the version.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Peggy.Accounts.{Scope, User}
  alias Peggy.Animals.{Animal, Movement, Placement}
  alias Peggy.Audit
  alias Peggy.Audit.AuditLog
  alias Peggy.Breeding.{Farrowing, LitterEvent, Service, Weaning}
  alias Peggy.Farms
  alias Peggy.Farms.{Farm, Membership}
  alias Peggy.Locations.{House, Pen}
  alias Peggy.Repo

  @schema_version 1

  # Tables in insert order. Each tuple = {key_in_json, schema_module}.
  # Order respects FK dependencies; deferred FKs (animals.sire/dam/etc.)
  # are nulled at insert time and back-filled in `restore_phase_2/2`.
  @tables [
    {"houses", House},
    {"pens", Pen},
    {"animals", Animal},
    {"placements", Placement},
    {"breeding_services", Service},
    {"breeding_farrowings", Farrowing},
    {"breeding_weanings", Weaning},
    {"movements", Movement},
    {"breeding_litter_events", LitterEvent},
    {"audit_logs", AuditLog}
  ]

  # ── Export ────────────────────────────────────────────────────────

  @doc """
  Build the gzipped JSON binary for `scope.farm`.

  Returns `{:ok, binary, filename}` on success.
  """
  @spec export(Scope.t()) :: {:ok, binary(), String.t()}
  def export(%Scope{farm: %Farm{} = farm} = scope) do
    payload = %{
      "schema_version" => @schema_version,
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "farm" => farm_settings(farm),
      "tables" => collect_tables(farm.id)
    }

    json = Jason.encode_to_iodata!(payload)
    gz = :zlib.gzip(json)

    Audit.log_now!(scope, "farm.backup.exported",
      entity_type: :farm,
      entity_id: farm.id,
      changes: %{
        "schema_version" => @schema_version,
        "byte_size" => byte_size(gz)
      }
    )

    filename =
      "peggy-backup-#{farm.slug}-#{Date.utc_today() |> Date.to_iso8601()}.json.gz"

    {:ok, gz, filename}
  end

  defp farm_settings(%Farm{} = farm) do
    farm
    |> Map.take(
      [:name, :slug, :timezone, :unit_system, :plan, :seat_limit, :simulated_today] ++
        Farm.breeding_parameter_fields()
    )
    |> Map.new(fn {k, v} -> {Atom.to_string(k), encode_value(v)} end)
  end

  defp collect_tables(farm_id) do
    Map.new(@tables, fn {key, schema} ->
      rows = query_table(schema, farm_id) |> Repo.all() |> Enum.map(&row_to_map/1)
      {key, rows}
    end)
  end

  # Placements have no farm_id — scope through their animal.
  defp query_table(Placement, farm_id) do
    from(p in Placement,
      join: a in Animal,
      on: a.id == p.animal_id,
      where: a.farm_id == ^farm_id,
      order_by: p.id
    )
  end

  defp query_table(schema, farm_id) do
    from(r in schema, where: r.farm_id == ^farm_id, order_by: r.id)
  end

  defp row_to_map(%schema{} = row) do
    fields = schema.__schema__(:fields)

    Map.new(fields, fn f ->
      {Atom.to_string(f), encode_value(Map.get(row, f))}
    end)
  end

  defp encode_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp encode_value(v), do: v

  # ── Restore ───────────────────────────────────────────────────────

  @doc """
  Decode a gzipped backup blob and recreate the farm under `user`.

  `new_attrs` must include at least `"slug"` and `"name"` for the new
  farm; other fields fall back to the backup's snapshot.

  Returns `{:ok, %Farm{}}` or `{:error, reason}`.
  """
  @spec import_to_new_farm(User.t(), binary(), map()) ::
          {:ok, Farm.t()} | {:error, term()}
  def import_to_new_farm(%User{} = user, gz_binary, new_attrs)
      when is_binary(gz_binary) and is_map(new_attrs) do
    with {:ok, json} <- safe_gunzip(gz_binary),
         {:ok, payload} <- Jason.decode(json),
         :ok <- validate_payload(payload),
         {:ok, farm} <- do_restore(user, payload, new_attrs) do
      {:ok, farm}
    end
  end

  defp safe_gunzip(binary) do
    {:ok, :zlib.gunzip(binary)}
  rescue
    _ -> {:error, :invalid_gzip}
  end

  defp validate_payload(%{"schema_version" => v, "tables" => tables, "farm" => farm})
       when is_map(tables) and is_map(farm) do
    cond do
      v != @schema_version -> {:error, {:unsupported_schema_version, v}}
      true -> :ok
    end
  end

  defp validate_payload(_), do: {:error, :malformed_payload}

  defp do_restore(user, payload, new_attrs) do
    farm_attrs =
      payload["farm"]
      |> Map.merge(stringify_keys(new_attrs))

    Multi.new()
    |> Multi.run(:farm, fn _repo, _ -> insert_farm(user, farm_attrs) end)
    |> Multi.run(:membership, fn _repo, %{farm: farm} -> insert_owner(user, farm) end)
    |> Multi.run(:restore, fn _repo, %{farm: farm} ->
      restore_tables(farm, payload["tables"])
    end)
    |> Multi.run(:audit, fn _repo, %{farm: farm, restore: counts} ->
      Audit.log_now!(scope_for(user, farm), "farm.backup.restored",
        entity_type: :farm,
        entity_id: farm.id,
        changes: %{
          "schema_version" => @schema_version,
          "counts" => counts
        }
      )

      {:ok, :logged}
    end)
    |> Repo.transaction(timeout: :timer.minutes(5))
    |> case do
      {:ok, %{farm: farm}} -> {:ok, farm}
      {:error, :farm, cs, _} -> {:error, {:farm, cs}}
      {:error, :membership, cs, _} -> {:error, {:membership, cs}}
      {:error, :restore, reason, _} -> {:error, reason}
      {:error, step, reason, _} -> {:error, {step, reason}}
    end
  end

  defp insert_farm(_user, attrs) do
    %Farm{}
    |> Farm.changeset(attrs)
    |> Repo.insert()
  end

  defp insert_owner(user, farm) do
    %Membership{}
    |> Membership.changeset(%{
      "user_id" => user.id,
      "farm_id" => farm.id,
      "role" => "owner",
      "accepted_at" => DateTime.utc_now(:second)
    })
    |> Repo.insert()
  end

  defp scope_for(user, farm),
    do: %Scope{user: user, farm: farm, role: :owner}

  # ── Restore — table walk ─────────────────────────────────────────

  # Maps from old (source-export) id → new id, keyed by table name.
  # Built up as we insert each table; consulted when later tables
  # reference earlier ones.
  defp restore_tables(%Farm{id: farm_id}, tables) do
    init = %{id_map: %{}, counts: %{}}

    state =
      Enum.reduce(@tables, init, fn {key, schema}, acc ->
        rows = Map.get(tables, key, [])
        {new_id_map, count} = insert_table_rows(schema, key, rows, farm_id, acc.id_map)

        %{
          acc
          | id_map: Map.put(acc.id_map, key, new_id_map),
            counts: Map.put(acc.counts, key, count)
        }
      end)

    restore_phase_2(tables, state.id_map)
    {:ok, state.counts}
  end

  # Schema-specific row prep for the initial INSERT: drops user FKs,
  # remaps in-farm FKs via the id_map, nulls FKs that point at rows
  # we haven't inserted yet (filled in by `restore_phase_2/2`).
  defp insert_table_rows(schema, key, rows, farm_id, id_map) do
    {new_map, count} =
      Enum.reduce(rows, {%{}, 0}, fn row, {map, n} ->
        old_id = row["id"]
        attrs = prepare_row(schema, key, row, farm_id, id_map)

        {:ok, inserted} =
          schema
          |> struct(attrs)
          |> Repo.insert(returning: [:id])

        {Map.put(map, old_id, inserted.id), n + 1}
      end)

    {new_map, count}
  end

  # ── Per-table row prep ────────────────────────────────────────────

  defp prepare_row(House, _key, row, farm_id, _ids) do
    base_attrs(House, row)
    |> Map.put(:farm_id, farm_id)
  end

  defp prepare_row(Pen, _key, row, farm_id, ids) do
    base_attrs(Pen, row)
    |> Map.put(:farm_id, farm_id)
    |> remap(:house_id, ids["houses"], row)
  end

  defp prepare_row(Animal, _key, row, farm_id, ids) do
    # Defer sire_id, dam_id, farrowing_id, origin_audit_id — they
    # may point at rows we haven't inserted yet.
    base_attrs(Animal, row)
    |> Map.put(:farm_id, farm_id)
    |> Map.put(:sire_id, nil)
    |> Map.put(:dam_id, nil)
    |> Map.put(:farrowing_id, nil)
    |> Map.put(:origin_audit_id, nil)
    |> remap(:current_pen_id, ids["pens"], row)
  end

  defp prepare_row(Placement, _key, row, _farm_id, ids) do
    base_attrs(Placement, row)
    |> remap(:animal_id, ids["animals"], row)
    |> remap(:pen_id, ids["pens"], row)
  end

  defp prepare_row(Service, _key, row, farm_id, ids) do
    base_attrs(Service, row)
    |> Map.put(:farm_id, farm_id)
    |> Map.put(:technician_user_id, nil)
    |> Map.put(:deleted_by_id, nil)
    |> Map.put(:origin_audit_id, nil)
    |> remap(:sow_id, ids["animals"], row)
    |> remap(:boar_id, ids["animals"], row)
  end

  defp prepare_row(Farrowing, _key, row, farm_id, ids) do
    base_attrs(Farrowing, row)
    |> Map.put(:farm_id, farm_id)
    |> Map.put(:deleted_by_id, nil)
    |> Map.put(:origin_audit_id, nil)
    |> remap(:service_id, ids["breeding_services"], row)
    |> remap(:sow_id, ids["animals"], row)
    |> remap(:pen_id, ids["pens"], row)
  end

  defp prepare_row(Weaning, _key, row, farm_id, ids) do
    base_attrs(Weaning, row)
    |> Map.put(:farm_id, farm_id)
    |> Map.put(:deleted_by_id, nil)
    |> Map.put(:origin_audit_id, nil)
    |> remap(:farrowing_id, ids["breeding_farrowings"], row)
    |> remap(:destination_pen_id, ids["pens"], row)
    |> remap(:batch_animal_id, ids["animals"], row)
  end

  defp prepare_row(Movement, _key, row, farm_id, ids) do
    # weaning_id deferred — weanings inserted before movements but the
    # FK can also point forward in legacy data; safer to remap in
    # phase 2 only if it dangles.
    base_attrs(Movement, row)
    |> Map.put(:farm_id, farm_id)
    |> remap(:animal_id, ids["animals"], row)
    |> remap(:from_pen_id, ids["pens"], row)
    |> remap(:to_pen_id, ids["pens"], row)
    |> remap(:weaning_id, ids["breeding_weanings"], row)
  end

  defp prepare_row(LitterEvent, _key, row, farm_id, ids) do
    base_attrs(LitterEvent, row)
    |> Map.put(:farm_id, farm_id)
    |> Map.put(:created_by_id, nil)
    |> Map.put(:deleted_by_id, nil)
    |> remap(:farrowing_id, ids["breeding_farrowings"], row)
    |> remap(:counterpart_farrowing_id, ids["breeding_farrowings"], row)
  end

  defp prepare_row(AuditLog, _key, row, farm_id, ids) do
    base_attrs(AuditLog, row)
    |> Map.put(:farm_id, farm_id)
    |> Map.put(:actor_user_id, nil)
    |> remap_audit_entity(row, ids)
  end

  # ── Phase 2: back-fill deferred FKs ──────────────────────────────

  defp restore_phase_2(tables, id_map) do
    fix_animals(tables["animals"] || [], id_map)
    fix_origin_audit(tables, id_map)
    :ok
  end

  defp fix_animals(rows, id_map) do
    animals = id_map["animals"]
    farrowings = id_map["breeding_farrowings"]
    audits = id_map["audit_logs"]

    Enum.each(rows, fn row ->
      new_id = Map.get(animals, row["id"])
      next? = new_id != nil

      if next? do
        updates =
          %{}
          |> maybe_put(:sire_id, lookup(animals, row["sire_id"]))
          |> maybe_put(:dam_id, lookup(animals, row["dam_id"]))
          |> maybe_put(:farrowing_id, lookup(farrowings, row["farrowing_id"]))
          |> maybe_put(:origin_audit_id, lookup(audits, row["origin_audit_id"]))

        if map_size(updates) > 0 do
          from(a in Animal, where: a.id == ^new_id) |> Repo.update_all(set: Map.to_list(updates))
        end
      end
    end)
  end

  defp fix_origin_audit(tables, id_map) do
    audits = id_map["audit_logs"] || %{}

    for {key, schema} <- [
          {"breeding_services", Service},
          {"breeding_farrowings", Farrowing},
          {"breeding_weanings", Weaning}
        ] do
      rows = tables[key] || []
      table_map = id_map[key] || %{}

      Enum.each(rows, fn row ->
        with new_id when not is_nil(new_id) <- Map.get(table_map, row["id"]),
             new_audit_id when not is_nil(new_audit_id) <-
               lookup(audits, row["origin_audit_id"]) do
          from(r in schema, where: r.id == ^new_id)
          |> Repo.update_all(set: [origin_audit_id: new_audit_id])
        end
      end)
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────

  defp base_attrs(schema, row) do
    # Cast every storage field via the schema's field type so JSON
    # strings get back to Date/DateTime/integers/etc. Drop :id — let
    # the DB assign a fresh one.
    schema.__schema__(:fields)
    |> Enum.reject(&(&1 == :id))
    |> Map.new(fn field ->
      raw = row[Atom.to_string(field)]
      {field, cast_field(schema, field, raw)}
    end)
  end

  defp cast_field(_schema, _field, nil), do: nil

  defp cast_field(schema, field, raw) do
    case schema.__schema__(:type, field) do
      :date -> Date.from_iso8601!(raw)
      :utc_datetime -> raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.truncate(:second)
      :naive_datetime -> NaiveDateTime.from_iso8601!(raw)
      :integer when is_binary(raw) -> String.to_integer(raw)
      _ -> raw
    end
  end

  defp remap(attrs, field, nil, _row), do: Map.put(attrs, field, nil)

  defp remap(attrs, field, table_map, row) do
    old = row[Atom.to_string(field)]
    Map.put(attrs, field, lookup(table_map, old))
  end

  defp lookup(_map, nil), do: nil
  defp lookup(nil, _), do: nil
  defp lookup(map, old_id), do: Map.get(map, old_id)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # audit_log.entity_id is a string; remap when entity_type matches a
  # known table.
  defp remap_audit_entity(attrs, row, ids) do
    type = row["entity_type"]
    table_for_type = ref_table_for(type)
    raw = row["entity_id"]

    new_id =
      with table when not is_nil(table) <- table_for_type,
           {old_int, ""} <- (raw && Integer.parse(to_string(raw))) || :error,
           new when not is_nil(new) <- lookup(ids[table], old_int) do
        Integer.to_string(new)
      else
        _ -> raw
      end

    Map.put(attrs, :entity_id, new_id)
  end

  defp ref_table_for("animal"), do: "animals"
  defp ref_table_for("service"), do: "breeding_services"
  defp ref_table_for("farrowing"), do: "breeding_farrowings"
  defp ref_table_for("weaning"), do: "breeding_weanings"
  defp ref_table_for("pen"), do: "pens"
  defp ref_table_for("house"), do: "houses"
  defp ref_table_for("movement"), do: "movements"
  defp ref_table_for("litter_event"), do: "breeding_litter_events"
  defp ref_table_for(_), do: nil

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  # Unused-alias safety nets — referenced via @tables and module paths.
  _ = Farms
end
