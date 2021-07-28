defmodule PeggyWeb.InviteUserLive.New do
  use PeggyWeb, :live_view
  alias Peggy.Company
  alias Peggy.Company.InviteUser

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)
    socket = assign_current_user_farm(socket, session)

    {:ok,
     socket
     |> assign(:page_title, gettext("Invite User"))
     |> assign(:changeset, Company.change_invite_user(%InviteUser{}, %{farm: socket.assigns.current_farm}))}
  end
end
