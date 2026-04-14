defmodule Peggy.Farms do
  @moduledoc """
  Tenancy context: farms, memberships, and invitations.

  All functions that mutate tenant state take the acting `%User{}` or
  `%Scope{}` and record the relationship; authorization is handled by
  `Peggy.Policy` in the caller (LiveView / controller).
  """

  import Ecto.Query
  alias Ecto.Multi
  alias Peggy.Repo
  alias Peggy.Accounts.User
  alias Peggy.Farms.{Farm, Membership, Invitation}

  ## Farms

  def list_farms_for_user(%User{id: user_id}) do
    Repo.all(
      from f in Farm,
        join: m in Membership,
        on: m.farm_id == f.id,
        where:
          m.user_id == ^user_id and not is_nil(m.accepted_at) and
            is_nil(f.deleted_at),
        order_by: f.name
    )
  end

  @doc """
  Returns `[{farm, membership}, ...]` for the user's accepted memberships on
  active (non-archived) farms.
  """
  def list_memberships_with_farms(%User{id: user_id}) do
    Repo.all(
      from m in Membership,
        join: f in assoc(m, :farm),
        where:
          m.user_id == ^user_id and not is_nil(m.accepted_at) and
            is_nil(f.deleted_at),
        order_by: [desc: m.is_default, asc: f.name],
        select: {f, m}
    )
  end

  @doc """
  Returns archived farms the user owns (restore is owner-only).
  """
  def list_archived_farms_for_owner(%User{id: user_id}) do
    Repo.all(
      from f in Farm,
        join: m in Membership,
        on: m.farm_id == f.id,
        where:
          m.user_id == ^user_id and m.role == "owner" and
            not is_nil(f.deleted_at),
        order_by: [desc: f.deleted_at]
    )
  end

  def get_farm_by_slug!(slug) when is_binary(slug) do
    Repo.one!(
      from f in Farm,
        where: f.slug == ^String.downcase(slug) and is_nil(f.deleted_at)
    )
  end

  def get_farm_by_slug(slug) when is_binary(slug) do
    Repo.one(
      from f in Farm,
        where: f.slug == ^String.downcase(slug) and is_nil(f.deleted_at)
    )
  end

  @doc """
  Creates a farm and makes the given user its owner, in one transaction.
  """
  def create_farm(%User{} = user, attrs) do
    now = DateTime.utc_now(:second)

    Multi.new()
    |> Multi.insert(:farm, Farm.changeset(%Farm{}, attrs))
    |> Multi.insert(:membership, fn %{farm: farm} ->
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        farm_id: farm.id,
        role: "owner",
        accepted_at: now
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{farm: farm}} -> {:ok, farm}
      {:error, :farm, changeset, _} -> {:error, changeset}
      {:error, :membership, changeset, _} -> {:error, changeset}
    end
  end

  def change_farm(%Farm{} = farm, attrs \\ %{}), do: Farm.changeset(farm, attrs)

  def update_farm(%Farm{} = farm, attrs) do
    farm |> Farm.changeset(attrs) |> Repo.update()
  end

  @doc """
  Soft-deletes a farm. Sets `deleted_at`, records the actor, and revokes
  all pending (non-accepted) invitations. Memberships are preserved so the
  owner can restore with the team intact.
  """
  def archive_farm(%Farm{deleted_at: nil} = farm, %User{} = actor) do
    now = DateTime.utc_now(:second)

    Multi.new()
    |> Multi.update(
      :farm,
      Ecto.Changeset.change(farm, deleted_at: now, deleted_by_id: actor.id)
    )
    |> Multi.delete_all(
      :revoke_invitations,
      from(i in Invitation, where: i.farm_id == ^farm.id and is_nil(i.accepted_at))
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{farm: farm}} -> {:ok, farm}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  def archive_farm(%Farm{}, _), do: {:error, :already_archived}

  @doc """
  Restores a previously archived farm. No-op if the farm was never archived.
  """
  def restore_farm(%Farm{deleted_at: nil} = farm), do: {:ok, farm}

  def restore_farm(%Farm{} = farm) do
    farm
    |> Ecto.Changeset.change(deleted_at: nil, deleted_by_id: nil)
    |> Repo.update()
  end

  @doc """
  Bypasses the `deleted_at` filter — used by archive/restore flows that need
  to load an archived farm by slug.
  """
  def get_any_farm_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Farm, slug: String.downcase(slug))
  end

  ## Memberships

  def get_membership(%User{id: user_id}, %Farm{id: farm_id}) do
    Repo.get_by(Membership, user_id: user_id, farm_id: farm_id)
  end

  def list_members(%Farm{id: farm_id}) do
    Repo.all(
      from m in Membership,
        where: m.farm_id == ^farm_id,
        preload: [:user],
        order_by: [asc: m.role, asc: m.inserted_at]
    )
  end

  def change_role(%Membership{} = membership, role) do
    membership |> Membership.role_changeset(%{role: role}) |> Repo.update()
  end

  def remove_member(%Membership{} = membership), do: Repo.delete(membership)

  @doc """
  Marks the given membership as the user's default farm, clearing any previous
  default. Runs in one transaction so the partial unique index is never
  violated.
  """
  def set_default_farm(%User{id: user_id}, %Farm{id: farm_id}) do
    Multi.new()
    |> Multi.update_all(
      :clear,
      from(m in Membership, where: m.user_id == ^user_id and m.is_default == true),
      set: [is_default: false]
    )
    |> Multi.update_all(
      :mark,
      from(m in Membership, where: m.user_id == ^user_id and m.farm_id == ^farm_id),
      set: [is_default: true]
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{mark: {1, _}}} -> :ok
      _ -> {:error, :not_a_member}
    end
  end

  def get_default_farm(%User{id: user_id}) do
    Repo.one(
      from f in Farm,
        join: m in Membership,
        on: m.farm_id == f.id,
        where:
          m.user_id == ^user_id and m.is_default == true and
            not is_nil(m.accepted_at) and is_nil(f.deleted_at)
    )
  end

  ## Invitations

  def list_pending_invitations(%Farm{id: farm_id}) do
    Repo.all(
      from i in Invitation,
        where: i.farm_id == ^farm_id and is_nil(i.accepted_at),
        order_by: [desc: i.inserted_at]
    )
  end

  @doc """
  Returns pending, non-expired invitations for the given email (case-insensitive),
  with the farm preloaded. Used to surface invitations in the invitee's UI.
  """
  def list_pending_invitations_for_email(email) when is_binary(email) do
    now = DateTime.utc_now(:second)
    normalized = email |> String.downcase() |> String.trim()

    Repo.all(
      from i in Invitation,
        where:
          fragment("lower(?)", i.email) == ^normalized and
            is_nil(i.accepted_at) and
            i.expires_at > ^now,
        order_by: [desc: i.inserted_at],
        preload: [:farm]
    )
  end

  @doc """
  Creates a pending invitation and emails the invitee a link to accept it.

  The URL to the accept page is built by `url_fun.(encoded_token)`.

  Returns `{:error, :seat_limit_reached}` if accepted members + pending
  invitations would exceed the farm's `seat_limit`.
  """
  def invite(%Farm{} = farm, attrs, %User{} = invited_by, url_fun \\ nil)
      when is_function(url_fun, 1) or is_nil(url_fun) do
    if seats_used(farm) >= farm.seat_limit do
      {:error, :seat_limit_reached}
    else
      with {:ok, invitation} <- farm |> Invitation.build(attrs, invited_by) |> Repo.insert() do
        if url_fun do
          encoded = Invitation.encode_token(invitation.token)

          Peggy.Accounts.UserNotifier.deliver_farm_invitation(
            invitation.email,
            farm.name,
            invitation.role,
            url_fun.(encoded)
          )
        end

        {:ok, invitation}
      end
    end
  end

  @doc """
  Returns the number of seats consumed by the farm: accepted memberships plus
  pending, non-expired invitations.
  """
  def seats_used(%Farm{id: farm_id}) do
    now = DateTime.utc_now(:second)

    members =
      Repo.aggregate(
        from(m in Membership,
          where: m.farm_id == ^farm_id and not is_nil(m.accepted_at)
        ),
        :count
      )

    pending =
      Repo.aggregate(
        from(i in Invitation,
          where:
            i.farm_id == ^farm_id and is_nil(i.accepted_at) and i.expires_at > ^now
        ),
        :count
      )

    members + pending
  end

  def get_invitation_by_token(encoded) when is_binary(encoded) do
    with {:ok, token} <- Invitation.decode_token(encoded),
         %Invitation{} = invitation <-
           Repo.get_by(Invitation, token: token) |> Repo.preload(:farm) do
      if Invitation.expired?(invitation) or invitation.accepted_at,
        do: :error,
        else: {:ok, invitation}
    else
      _ -> :error
    end
  end

  @doc """
  Accepts an invitation: creates a membership for `user` on the invitation's
  farm, and marks the invitation accepted. One transaction.
  """
  def accept_invitation(%Invitation{} = invitation, %User{} = user) do
    now = DateTime.utc_now(:second)
    farm = Repo.get!(Farm, invitation.farm_id)

    # Guard against a stale invitation issued before seat_limit was lowered
    # or before other members filled the cap. Already-accepted members don't
    # count twice (accept flips the invitation's accepted_at in the same txn).
    current_members =
      Repo.aggregate(
        from(m in Membership,
          where: m.farm_id == ^farm.id and not is_nil(m.accepted_at)
        ),
        :count
      )

    if current_members >= farm.seat_limit and
         is_nil(Repo.get_by(Membership, user_id: user.id, farm_id: farm.id)) do
      {:error, :seat_limit_reached}
    else
      accept_invitation_multi(invitation, user, now)
    end
  end

  defp accept_invitation_multi(invitation, user, now) do
    Multi.new()
    |> Multi.insert(
      :membership,
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        farm_id: invitation.farm_id,
        role: invitation.role,
        invited_by_id: invitation.invited_by_id,
        accepted_at: now
      }),
      on_conflict: {:replace, [:role, :accepted_at, :updated_at]},
      conflict_target: [:user_id, :farm_id]
    )
    |> Multi.update(
      :invitation,
      Ecto.Changeset.change(invitation, accepted_at: now)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{membership: m}} -> {:ok, m}
      {:error, _op, changeset, _} -> {:error, changeset}
    end
  end

  def revoke_invitation(%Invitation{} = invitation), do: Repo.delete(invitation)
end
