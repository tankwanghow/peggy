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
    field :reusable, :boolean, default: false
    field :closed_at, :utc_datetime

    belongs_to :farm, Peggy.Farms.Farm
    belongs_to :invited_by, Peggy.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds an invitation with a fresh random token and expiry.
  """
  def build(farm, attrs, invited_by) do
    now = DateTime.utc_now(:second)
    email = normalize_email(attrs["email"] || attrs[:email])

    %__MODULE__{
      farm_id: farm.id,
      invited_by_id: invited_by && invited_by.id,
      token: :crypto.strong_rand_bytes(@token_bytes),
      expires_at: DateTime.add(now, @expiry_days * 86_400, :second)
    }
    |> changeset(Map.merge(attrs, %{"email" => email}))
  end

  @doc false
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :token, :expires_at, :accepted_at, :reusable, :closed_at])
    |> validate_required([:role, :token, :expires_at])
    |> validate_inclusion(:role, Peggy.Farms.Membership.roles())
    |> maybe_validate_email_format()
    |> unique_constraint([:farm_id, :email], name: :farm_invitations_pending_unique)
    |> unique_constraint(:token)
  end

  defp maybe_validate_email_format(changeset) do
    if get_field(changeset, :email) do
      validate_format(changeset, :email, ~r/^[^@,;\s]+@[^@,;\s]+$/)
    else
      changeset
    end
  end

  defp normalize_email(email) when email in [nil, ""], do: nil

  defp normalize_email(email) when is_binary(email) do
    email |> String.downcase() |> String.trim()
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
