defmodule Peggy.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  Carries the current user and, when the caller is acting inside a
  farm-scoped route, the current farm and the caller's membership/role
  in that farm.
  """

  alias Peggy.Accounts.User
  alias Peggy.Farms.{Farm, Membership}

  defstruct user: nil, farm: nil, membership: nil, role: nil

  @doc "Creates a scope for the given user."
  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil

  @doc """
  Attaches a farm + membership to the scope. Membership role becomes `role`.
  """
  def put_farm(%__MODULE__{} = scope, %Farm{} = farm, %Membership{} = membership) do
    %{scope | farm: farm, membership: membership, role: String.to_existing_atom(membership.role)}
  end

  @doc "True if the scope carries an accepted membership in a farm."
  def member?(%__MODULE__{membership: %Membership{accepted_at: %DateTime{}}}), do: true
  def member?(_), do: false
end
