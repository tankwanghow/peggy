defmodule Peggy.Farms.Invitation do
  use Ecto.Schema
  import Ecto.Changeset

  @token_bytes 32
  @expiry_days 7

  schema "farm_invitations" do
    field :email, :string
    field :role, :string
    field :token, :binary
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :invited_by, Peggy.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds an invitation with a fresh random token and expiry.
  """
  def build(farm, attrs, invited_by) do
    now = DateTime.utc_now(:second)

    %__MODULE__{
      farm_id: farm.id,
      invited_by_id: invited_by && invited_by.id,
      token: :crypto.strong_rand_bytes(@token_bytes),
      expires_at: DateTime.add(now, @expiry_days * 86_400, :second)
    }
    |> cast(attrs, [:email, :role])
    |> validate_required([:email, :role])
    |> update_change(:email, &(&1 |> String.downcase() |> String.trim()))
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/)
    |> validate_inclusion(:role, Peggy.Farms.Membership.roles())
    |> unique_constraint([:farm_id, :email], name: :farm_invitations_pending_unique)
  end

  def encode_token(token) when is_binary(token), do: Base.url_encode64(token, padding: false)

  def decode_token(encoded) when is_binary(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, token} -> {:ok, token}
      :error -> :error
    end
  end

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
