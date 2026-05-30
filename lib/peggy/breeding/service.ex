defmodule Peggy.Breeding.Service do
  use Ecto.Schema
  import Ecto.Changeset

  @service_types ~w(ai natural)
  @results ~w(farrowing abortion failed_pregnancy re_service death cull)

  schema "breeding_services" do
    field :service_type, :string
    field :served_at, :date
    field :last_serviced_at, :date
    field :mounting_count, :integer, default: 1
    field :result, :string
    field :result_at, :date
    field :result_notes, :string
    field :notes, :string
    field :semen, :string
    field :inferred, :boolean, default: false
    field :created_via, :string
    belongs_to :origin_audit, Peggy.Audit.AuditLog
    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :sow, Peggy.Animals.Animal
    belongs_to :boar, Peggy.Animals.Animal
    belongs_to :technician_user, Peggy.Accounts.User
    has_one :farrowing, Peggy.Breeding.Farrowing, where: [deleted_at: nil]
    field :deleted_at, :utc_datetime
    belongs_to :deleted_by, Peggy.Accounts.User
    timestamps(type: :utc_datetime)
  end

  def service_types, do: @service_types
  def results, do: @results

  def changeset(service, attrs) do
    service
    |> cast(attrs, [
      :service_type,
      :served_at,
      :last_serviced_at,
      :mounting_count,
      :result,
      :result_at,
      :result_notes,
      :notes,
      :semen,
      :inferred,
      :created_via,
      :origin_audit_id,
      :sow_id,
      :boar_id,
      :technician_user_id,
      :farm_id
    ])
    |> default_last_serviced_at()
    |> validate_required([:service_type, :served_at, :sow_id, :farm_id])
    |> validate_number(:mounting_count, greater_than_or_equal_to: 1)
    |> validate_inclusion(:service_type, @service_types)
    |> validate_inclusion(:result, @results)
    |> validate_boar_for_natural()
    |> validate_result_date()
  end

  @doc """
  Changeset that reopens a closed service (clears result fields).
  Used when undoing a departure movement linked to a service closure.
  """
  def reopen_changeset(service) do
    Ecto.Changeset.change(service, %{result: nil, result_at: nil, result_notes: nil})
  end

  def close_changeset(service, attrs) do
    service
    |> cast(attrs, [:result, :result_at, :result_notes])
    |> validate_required([:result, :result_at])
    |> validate_inclusion(:result, @results)
  end

  # last_serviced_at defaults to served_at on insert when not provided.
  # The collapse logic in Peggy.Breeding pushes it forward on re-service.
  defp default_last_serviced_at(cs) do
    case {get_field(cs, :last_serviced_at), get_field(cs, :served_at)} do
      {nil, %Date{} = served_at} -> put_change(cs, :last_serviced_at, served_at)
      _ -> cs
    end
  end

  defp validate_boar_for_natural(cs) do
    if get_field(cs, :service_type) == "natural" and is_nil(get_field(cs, :boar_id)) do
      add_error(cs, :boar_id, "is required for natural service")
    else
      cs
    end
  end

  defp validate_result_date(cs) do
    result = get_field(cs, :result)
    result_at = get_field(cs, :result_at)

    cond do
      not is_nil(result) and is_nil(result_at) ->
        add_error(cs, :result_at, "is required when result is set")

      is_nil(result) and not is_nil(result_at) ->
        add_error(cs, :result_at, "must be blank when result is not set")

      true ->
        cs
    end
  end
end
