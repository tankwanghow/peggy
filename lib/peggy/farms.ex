defmodule Peggy.Farms do
  @moduledoc """
  Tenancy context: farms, memberships, and invitations.

  All functions that mutate tenant state take the acting `%User{}` or
  `%Scope{}` and record the relationship; authorization is handled by
  `Peggy.Policy` in the caller (LiveView / controller).
  """

  import Ecto.Query
  alias Ecto.Multi
  alias Peggy.{Repo, Audit}
  alias Peggy.Accounts.{Scope, User}
  alias Peggy.Farms.{Farm, Membership, Invitation}

  defp scope_for(%User{} = user, %Farm{} = farm),
    do: %Scope{user: user, farm: farm}

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
    |> Multi.run(:audit, fn _repo, %{farm: farm, membership: m} ->
      Audit.log_now!(scope_for(user, farm), "farm.created",
        entity_type: :farm,
        entity_id: farm.id,
        changes: %{name: farm.name, slug: farm.slug, owner_membership_id: m.id}
      )

      {:ok, :logged}
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

  @doc "Builds a changeset for the per-farm breeding-parameter form."
  def change_breeding_parameters(%Farm{} = farm, attrs \\ %{}),
    do: Farm.breeding_parameter_changeset(farm, attrs)

  @doc """
  Updates the per-farm breeding parameters (gestation_days, lactation_days,
  etc.). Validates each field against its biological range.
  """
  def update_breeding_parameters(%Farm{} = farm, attrs) do
    farm |> Farm.breeding_parameter_changeset(attrs) |> Repo.update()
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
    |> Multi.run(:audit, fn _repo, _ ->
      Audit.log_now!(scope_for(actor, farm), "farm.archived",
        entity_type: :farm,
        entity_id: farm.id,
        changes: %{deleted_at: now}
      )

      {:ok, :logged}
    end)
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

  @invitation_validity_days 7

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
      with {:ok, invitation} <- insert_invitation(farm, invited_by, attrs) do
        if url_fun && invitation.email do
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
  Opens a reusable, admin-supervised invite session for `role` ("manager" or
  "worker"). Auto-expires 30 minutes from now; close early with
  `close_invite_session/2`.
  """
  def open_invite_session(%Farm{} = farm, %User{} = inviter, role) do
    if role not in ["manager", "worker"] do
      {:error, :invalid_role}
    else
      token = :crypto.strong_rand_bytes(32)
      expires_at = DateTime.add(DateTime.utc_now(:second), 30 * 60, :second)

      %Invitation{farm_id: farm.id, invited_by_id: inviter.id}
      |> Invitation.changeset(%{
        role: role,
        token: token,
        expires_at: expires_at,
        reusable: true
      })
      |> Repo.insert()
    end
  end

  @doc """
  Closes a reusable invite session. Stamps `closed_at`.
  """
  def close_invite_session(%Farm{} = farm, invitation_id) do
    case Repo.get_by(Invitation, id: invitation_id, farm_id: farm.id, reusable: true) do
      nil ->
        {:error, :not_found}

      invitation ->
        invitation
        |> Invitation.changeset(%{closed_at: DateTime.utc_now(:second)})
        |> Repo.update()
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
          where: i.farm_id == ^farm_id and is_nil(i.accepted_at) and i.expires_at > ^now
        ),
        :count
      )

    members + pending
  end

  def get_invitation_by_token(encoded) when is_binary(encoded) do
    case get_invitation_by_encoded_token(encoded) do
      {:ok, invitation} -> {:ok, invitation}
      :error -> :error
    end
  end

  @doc """
  Fetches a pending, non-expired invitation by its URL-safe encoded token,
  with `:farm` preloaded.
  """
  def get_invitation_by_encoded_token(encoded) when is_binary(encoded) do
    with {:ok, token} <- Invitation.decode_token(encoded),
         {:ok, invitation} <- fetch_pending_invitation(token) do
      {:ok, invitation}
    else
      _ -> :error
    end
  end

  @doc """
  Accepts an invitation: creates a membership for `user` on the invitation's
  farm, and marks the invitation accepted (single-use only). One transaction.
  """
  def accept_invitation(%Invitation{} = invitation, %User{} = user) do
    accept_invitation(user, invitation.token)
  end

  def accept_invitation(%User{} = user, token) when is_binary(token) do
    with {:ok, invitation} <- fetch_pending_invitation(token),
         true <- seats_available_for_accept?(invitation, user),
         {:ok, membership} <- accept_invitation_multi(user, invitation) do
      {:ok, membership}
    else
      false -> {:error, :seat_limit_reached}
      {:error, reason} -> {:error, reason}
    end
  end

  def revoke_invitation(%Invitation{} = invitation), do: Repo.delete(invitation)

  defp insert_invitation(farm, inviter, attrs) do
    attrs = if is_map(attrs), do: attrs, else: %{}
    email = normalize_invite_email(attrs["email"] || attrs[:email])
    role = attrs["role"] || attrs[:role]
    token = :crypto.strong_rand_bytes(32)
    expires_at = DateTime.utc_now(:second) |> DateTime.add(@invitation_validity_days, :day)

    %Invitation{farm_id: farm.id, invited_by_id: inviter.id}
    |> Invitation.changeset(%{
      email: email,
      role: role,
      token: token,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  defp normalize_invite_email(email) when email in [nil, ""], do: nil

  defp normalize_invite_email(email) when is_binary(email) do
    email |> String.downcase() |> String.trim()
  end

  defp fetch_pending_invitation(token) do
    case Repo.get_by(Invitation, token: token) do
      %Invitation{} = invitation -> validate_invitation_live(invitation)
      nil -> {:error, :not_found}
    end
  end

  defp validate_invitation_live(%Invitation{reusable: true} = inv) do
    cond do
      not is_nil(inv.closed_at) -> {:error, :closed}
      invitation_expired?(inv) -> {:error, :expired}
      true -> {:ok, Repo.preload(inv, :farm)}
    end
  end

  defp validate_invitation_live(%Invitation{reusable: false} = inv) do
    cond do
      not is_nil(inv.accepted_at) -> {:error, :already_accepted}
      invitation_expired?(inv) -> {:error, :expired}
      true -> {:ok, Repo.preload(inv, :farm)}
    end
  end

  defp invitation_expired?(%Invitation{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(:second), expires_at) != :lt
  end

  defp seats_available_for_accept?(%Invitation{} = invitation, %User{} = user) do
    farm = Repo.get!(Farm, invitation.farm_id)

    current_members =
      Repo.aggregate(
        from(m in Membership,
          where: m.farm_id == ^farm.id and not is_nil(m.accepted_at)
        ),
        :count
      )

    current_members < farm.seat_limit or
      not is_nil(Repo.get_by(Membership, user_id: user.id, farm_id: farm.id))
  end

  defp accept_invitation_multi(user, %Invitation{} = invitation) do
    if Repo.get_by(Membership, user_id: user.id, farm_id: invitation.farm_id) do
      {:ok, :already_member}
    else
      do_accept_invitation_multi(user, invitation)
    end
  end

  defp do_accept_invitation_multi(user, %Invitation{} = invitation) do
    now = DateTime.utc_now(:second)

    multi =
      Multi.new()
      |> Multi.insert(
        :membership,
        Membership.changeset(%Membership{}, %{
          user_id: user.id,
          farm_id: invitation.farm_id,
          role: invitation.role,
          invited_by_id: invitation.invited_by_id,
          accepted_at: now,
          is_default: first_farm_for_user?(user)
        }),
        on_conflict: {:replace, [:role, :accepted_at, :updated_at]},
        conflict_target: [:user_id, :farm_id]
      )

    multi =
      if invitation.reusable do
        multi
      else
        Multi.update(
          multi,
          :invitation,
          Invitation.changeset(invitation, %{accepted_at: now})
        )
      end

    multi
    |> Repo.transaction()
    |> case do
      {:ok, %{membership: membership}} ->
        membership = Repo.preload(membership, :user)

        Phoenix.PubSub.broadcast(
          Peggy.PubSub,
          "farm:#{invitation.farm_id}:members",
          {:member_joined, membership}
        )

        {:ok, membership}

      {:error, :membership, changeset, _} ->
        {:error, changeset}

      {:error, :invitation, changeset, _} ->
        {:error, changeset}
    end
  end

  defp first_farm_for_user?(%User{} = user) do
    Membership
    |> where([m], m.user_id == ^user.id and not is_nil(m.accepted_at))
    |> Repo.aggregate(:count) == 0
  end
end
