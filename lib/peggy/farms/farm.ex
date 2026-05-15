defmodule Peggy.Farms.Farm do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(owner manager worker vet)a
  @unit_systems ~w(metric imperial)
  @plans ~w(free pro)

  schema "farms" do
    field :slug, :string
    field :name, :string
    field :timezone, :string, default: "Etc/UTC"
    field :unit_system, :string, default: "metric"
    field :plan, :string, default: "free"
    field :seat_limit, :integer, default: 5
    field :simulated_today, :date

    # Per-farm breeding parameters. Defaults track the historical
    # hard-coded values; settings UI clamps to the ranges in
    # `breeding_parameter_changeset/2` below.
    field :gestation_days, :integer, default: 114
    field :lactation_days, :integer, default: 24
    field :minimum_sow_age_days, :integer, default: 365
    field :gestation_tolerance_days, :integer, default: 3
    field :collapse_window_days, :integer, default: 7
    field :recent_weaner_batch_days, :integer, default: 60
    field :wean_due_days, :integer, default: 21

    # Thresholds for the "Promote batch animals" triage screen. Days
    # measured from the batch's `dob` (founding farrowing date).
    field :weaner_to_grower_days, :integer, default: 70
    field :grower_to_finisher_days, :integer, default: 120
    field :finisher_overdue_days, :integer, default: 200

    field :deleted_at, :utc_datetime
    belongs_to :deleted_by, Peggy.Accounts.User

    has_many :memberships, Peggy.Farms.Membership
    has_many :users, through: [:memberships, :user]

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  @breeding_parameter_fields ~w(
    gestation_days
    lactation_days
    minimum_sow_age_days
    gestation_tolerance_days
    collapse_window_days
    recent_weaner_batch_days
    wean_due_days
    weaner_to_grower_days
    grower_to_finisher_days
    finisher_overdue_days
  )a

  def breeding_parameter_fields, do: @breeding_parameter_fields

  def changeset(farm, attrs) do
    farm
    |> cast(attrs, [:slug, :name, :timezone, :unit_system, :plan, :seat_limit, :simulated_today])
    |> validate_required([:slug, :name, :timezone])
    |> update_change(:slug, &String.downcase/1)
    |> validate_format(:slug, ~r/^[a-z0-9][a-z0-9-]*[a-z0-9]$/,
      message: "lowercase letters, digits, and hyphens only"
    )
    |> validate_length(:slug, min: 3, max: 40)
    |> validate_length(:name, min: 1, max: 120)
    |> validate_inclusion(:unit_system, @unit_systems)
    |> validate_inclusion(:plan, @plans)
    |> validate_number(:seat_limit, greater_than: 0)
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset for the breeding-parameters form. Each field is clamped to
  a sensible biological range; out-of-range values become validation
  errors instead of silently saving nonsense.
  """
  def breeding_parameter_changeset(farm, attrs) do
    farm
    |> cast(attrs, @breeding_parameter_fields)
    |> validate_required(@breeding_parameter_fields)
    |> validate_number(:gestation_days, greater_than_or_equal_to: 100, less_than_or_equal_to: 130)
    |> validate_number(:lactation_days, greater_than_or_equal_to: 14, less_than_or_equal_to: 42)
    |> validate_number(:minimum_sow_age_days,
      greater_than_or_equal_to: 180,
      less_than_or_equal_to: 540
    )
    |> validate_number(:gestation_tolerance_days,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 7
    )
    |> validate_number(:collapse_window_days,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 14
    )
    |> validate_number(:recent_weaner_batch_days,
      greater_than_or_equal_to: 14,
      less_than_or_equal_to: 180
    )
    |> validate_number(:wean_due_days, greater_than_or_equal_to: 14, less_than_or_equal_to: 42)
    |> validate_number(:weaner_to_grower_days,
      greater_than_or_equal_to: 35,
      less_than_or_equal_to: 120
    )
    |> validate_number(:grower_to_finisher_days,
      greater_than_or_equal_to: 70,
      less_than_or_equal_to: 200
    )
    |> validate_number(:finisher_overdue_days,
      greater_than_or_equal_to: 140,
      less_than_or_equal_to: 365
    )
    |> validate_promotion_threshold_order()
  end

  # The three promotion thresholds drive a triage screen that groups
  # batches by stage; if the values overlap (e.g. weaner threshold ≥
  # grower threshold) the buckets become incoherent. Reject at the
  # changeset boundary so settings UI surfaces the error inline.
  defp validate_promotion_threshold_order(changeset) do
    weaner = get_field(changeset, :weaner_to_grower_days)
    grower = get_field(changeset, :grower_to_finisher_days)
    overdue = get_field(changeset, :finisher_overdue_days)

    cond do
      is_nil(weaner) or is_nil(grower) or is_nil(overdue) ->
        changeset

      weaner >= grower ->
        add_error(
          changeset,
          :grower_to_finisher_days,
          "must be greater than weaner→grower days"
        )

      grower >= overdue ->
        add_error(
          changeset,
          :finisher_overdue_days,
          "must be greater than grower→finisher days"
        )

      true ->
        changeset
    end
  end
end
