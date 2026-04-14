defmodule PeggyWeb.FarmScope do
  @moduledoc """
  LiveView `on_mount` hook that resolves `:farm_slug` from the URL,
  verifies the current user has an accepted membership in that farm,
  and attaches the farm + membership to `current_scope`.

  Used by all `/farms/:farm_slug/...` live_sessions.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Peggy.Accounts.Scope
  alias Peggy.Farms

  def on_mount(:require_member, %{"farm_slug" => slug}, _session, socket) do
    scope = socket.assigns.current_scope

    with %Scope{user: user} when not is_nil(user) <- scope,
         farm when not is_nil(farm) <- Farms.get_farm_by_slug(slug),
         membership when not is_nil(membership) <- Farms.get_membership(user, farm),
         %DateTime{} <- membership.accepted_at do
      {:cont, assign(socket, :current_scope, Scope.put_farm(scope, farm, membership))}
    else
      _ ->
        socket =
          socket
          |> put_flash(:error, "Farm not found.")
          |> redirect(to: "/farms")

        {:halt, socket}
    end
  end
end
