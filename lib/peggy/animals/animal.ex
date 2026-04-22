defmodule Peggy.Animals.Animal do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  @tracking_types ~w(individual batch)
  @stages ~w(piglet weaner grower finisher sow boar cull)
  @sexes ~w(male female unknown)
  @statuses ~w(active served open lactating dry culled sold slaughtered deceased transferred)
  @present_statuses ~w(active served open lactating dry culled)
  @departed_statuses ~w(sold slaughtered deceased transferred)
  @serviceable_statuses ~w(active open dry)
  @breeding_active_statuses ~w(served lactating)

  @status_descriptions %{
    "active" => "Present and healthy; no current reproductive cycle.",
    "served" => "Sow has been serviced and is presumed gestating.",
    "open" => "Pregnancy check negative or returned to heat; ready to re-serve.",
    "lactating" => "Sow has farrowed and is currently nursing piglets.",
    "dry" => "Piglets weaned; sow resting before next heat.",
    "culled" => "Marked for culling; final disposition pending.",
    "sold" => "Departed via sale.",
    "slaughtered" => "Departed via slaughter.",
    "deceased" => "Died on farm.",
    "transferred" => "Moved to another farm or entity."
  }

  # Allowed status transitions. See PLAN.md → "Animal status model".
  # Departed statuses are terminal (no outgoing transitions).
  # Same-status transitions are always allowed (no-op saves).
  @transitions %{
    "active" => ~w(served culled sold slaughtered deceased transferred),
    "served" => ~w(lactating open culled sold slaughtered deceased transferred),
    "open" => ~w(served culled sold slaughtered deceased transferred),
    "lactating" => ~w(dry culled sold slaughtered deceased transferred),
    "dry" => ~w(served culled sold slaughtered deceased transferred),
    "culled" => ~w(sold slaughtered deceased transferred),
    "sold" => [],
    "slaughtered" => [],
    "deceased" => [],
    "transferred" => []
  }

  schema "animals" do
    field :tracking_type, :string
    field :ear_tag, :string
    field :rfid, :string
    field :breed, :string
    field :stage, :string
    field :sex, :string
    field :dob, :date
    field :quantity, :integer, default: 1
    field :status, :string, default: "active"
    field :notes, :string
    field :inferred, :boolean, default: false
    field :needs_review, :boolean, default: false
    field :created_via, :string
    belongs_to :origin_audit, Peggy.Audit.AuditLog
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :sire, __MODULE__
    belongs_to :dam, __MODULE__
    belongs_to :current_pen, Peggy.Locations.Pen
    belongs_to :farrowing, Peggy.Breeding.Farrowing
    has_many :movements, Peggy.Animals.Movement
    has_many :placements, Peggy.Animals.Placement
    timestamps(type: :utc_datetime)
  end

  def tracking_types, do: @tracking_types
  def stages, do: @stages
  def sexes, do: @sexes
  def statuses, do: @statuses
  def present_statuses, do: @present_statuses
  def departed_statuses, do: @departed_statuses
  def serviceable_statuses, do: @serviceable_statuses
  def breeding_active_statuses, do: @breeding_active_statuses
  def present_status?(status), do: status in @present_statuses
  def serviceable_status?(status), do: status in @serviceable_statuses

  @doc "Short human-readable description of a status, used for UI tooltips."
  def status_description(status), do: Map.get(@status_descriptions, status, "")

  @doc "List of `{status, description}` tuples in canonical order."
  def statuses_with_descriptions,
    do: Enum.map(@statuses, &{&1, Map.get(@status_descriptions, &1, "")})

  @doc """
  Returns true if `from → to` is a valid status transition.

  Same-status transitions are allowed (no-op). Nil `from` is allowed
  (new records). Departed statuses are terminal (no outgoing transitions).
  """
  def valid_transition?(from, to) when from == to, do: true
  def valid_transition?(nil, _to), do: true

  def valid_transition?(from, to) when is_binary(from) and is_binary(to) do
    to in Map.get(@transitions, from, [])
  end

  def valid_transition?(_, _), do: false

  # ── Query scopes ──────────────────────────────────────────────────
  #
  # Canonical filters every LiveView and context should use. Never
  # inline `where: a.status == "active"` — status categories shift
  # (e.g. adding `under_treatment` in Phase 5) and inline filters drift.
  #
  # Usage: `from a in Animal, as: :a` |> Animal.scope_present() |> ...
  # Each scope is idempotent (applies to any query whose first binding
  # is the animal table).

  @doc "Narrows to animals currently on farm (any non-departed status)."
  def scope_present(query) do
    from(a in query, where: a.status in ^@present_statuses)
  end

  @doc """
  Narrows to the breeding herd — sows and gilts that are physically
  present (excludes piglets / weaners / growers / finishers / boars
  and departed animals).
  """
  def scope_breeding_herd(query) do
    from(a in query,
      where: a.status in ^@present_statuses and a.stage in ^~w(sow gilt)
    )
  end

  @doc "Narrows to sows eligible for a new service (active / open / dry)."
  def scope_serviceable(query) do
    from(a in query, where: a.status in ^@serviceable_statuses)
  end

  @doc """
  Narrows to animals eligible for sale / slaughter.

  Currently excludes departed statuses and `culled` (awaiting final
  disposition). Once `under_treatment` lands in Phase 5, exclude it
  here too so withdrawal-blocked animals drop out of sale autocomplete.
  """
  def scope_saleable(query) do
    saleable = ~w(active served open lactating dry)
    from(a in query, where: a.status in ^saleable)
  end

  @doc """
  Stage options offered by the UI for a given tracking type.

  Individuals are typically breeding stock (sow, boar) or culls;
  batches enter the herd at weaning (pre-wean piglets live as a count
  on the farrowing row, not as Animal rows) and move through the
  weaner → grower → finisher lifecycle. Schema-level validation still
  accepts any stage in `@stages` — this helper only narrows the
  dropdown.
  """
  def stages_for("individual"), do: ~w(sow boar cull)
  def stages_for("batch"), do: ~w(weaner grower finisher)
  def stages_for(_), do: @stages

  def changeset(animal, attrs) do
    animal
    |> cast(attrs, [
      :tracking_type,
      :ear_tag,
      :rfid,
      :breed,
      :stage,
      :sex,
      :dob,
      :quantity,
      :status,
      :notes,
      :inferred,
      :needs_review,
      :created_via,
      :origin_audit_id,
      :sire_id,
      :dam_id,
      :current_pen_id,
      :farrowing_id,
      :farm_id
    ])
    |> validate_required([:tracking_type, :stage, :status, :farm_id])
    |> validate_inclusion(:tracking_type, @tracking_types)
    |> validate_inclusion(:stage, @stages)
    |> validate_inclusion(:status, @statuses)
    |> validate_status_transition()
    |> validate_type_specific()
    |> validate_length(:ear_tag, min: 1, max: 40)
    |> validate_length(:rfid, min: 1, max: 60)
    |> validate_length(:breed, min: 1, max: 60)
    |> unsafe_validate_unique([:farm_id, :ear_tag], Peggy.Repo, error_key: :ear_tag)
    |> unsafe_validate_unique([:farm_id, :rfid], Peggy.Repo, error_key: :rfid)
    |> unique_constraint(:ear_tag, name: :animals_farm_id_ear_tag_index)
    |> unique_constraint(:rfid, name: :animals_farm_id_rfid_index)
  end

  @doc """
  Changeset for a weaner batch created at weaning time.

  Creates a batch animal with `quantity = weaned_count`. Does not
  require ear_tag (weaner batches are untagged) or sex (mixed litter).
  Skips the normal batch quantity > 1 check since a litter of 1 is valid.
  """
  def piglet_changeset(animal, attrs) do
    animal
    |> cast(attrs, [
      :tracking_type,
      :stage,
      :sex,
      :dob,
      :quantity,
      :status,
      :sire_id,
      :dam_id,
      :farrowing_id,
      :farm_id
    ])
    |> validate_required([:tracking_type, :stage, :quantity, :status, :farm_id])
    |> validate_inclusion(:tracking_type, @tracking_types)
    |> validate_inclusion(:stage, @stages)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:quantity, greater_than: 0)
  end

  defp validate_type_specific(cs) do
    case get_field(cs, :tracking_type) do
      "individual" ->
        cs
        |> validate_required([:ear_tag, :sex])
        |> validate_inclusion(:sex, @sexes)
        |> force_change(:quantity, 1)

      "batch" ->
        cs
        |> validate_required([:quantity])
        |> validate_batch_quantity()

      _ ->
        cs
    end
  end

  # Status transition guard. Only applies to existing rows (persisted
  # animals) so that new-record inserts and test fixtures can set any
  # valid status directly. Corrections that need to skip this guard
  # should build the changeset with `Ecto.Changeset.change/2` directly,
  # which bypasses `validate_status_transition`.
  defp validate_status_transition(cs) do
    case {cs.data.id, get_change(cs, :status)} do
      {nil, _} ->
        cs

      {_id, nil} ->
        cs

      {_id, new_status} ->
        old_status = cs.data.status

        if valid_transition?(old_status, new_status) do
          cs
        else
          add_error(
            cs,
            :status,
            "cannot transition from \"#{old_status}\" to \"#{new_status}\""
          )
        end
    end
  end

  # Active batches need >1 animals (a batch of 1 should be individual).
  # Once a batch has departed (sold/slaughtered/etc.) quantity is allowed
  # to drop to 0 so we can close out the row cleanly.
  defp validate_batch_quantity(cs) do
    qty = get_field(cs, :quantity)
    status = get_field(cs, :status)

    cond do
      is_integer(qty) and qty > 1 -> cs
      is_integer(qty) and qty >= 0 and status in @departed_statuses -> cs
      true -> add_error(cs, :quantity, "must be greater than 1 for batch animals")
    end
  end
end
