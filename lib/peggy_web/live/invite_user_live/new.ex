defmodule PeggyWeb.InviteUserLive.New do
  use PeggyWeb, :live_view
  alias Peggy.UserAccounts
  alias Peggy.Company

  @impl true
  def mount(_params, session, socket) do
    PeggyWeb.LiveHelpers.set_locale(session)
    socket = assign_current_user_farm(socket, session)

    {:ok,
     socket
     |> assign(:page_title, gettext("Invite User"))
     |> assign(:email, "")}
  end

  @impl true
  def handle_event("invite", %{"invite_user" => params}, socket) do
    email = params["email"]
    password = random_string(8)
    user = find_or_create_user(email, password)

    case Company.allow_user_access_farm(
           user,
           socket.assigns.current_farm,
           params["role"],
           socket.assigns.current_user
         ) do
      {:ok, _farm_user} ->
        flag = send_invitation_email(user, password, socket)

        {:noreply,
         socket
         |> put_flash(
           :success,
           gettext("Invitation email has been sent to ") <> flag <> user.email
         )}

      {:error, %Ecto.Changeset{}, message} ->
        {:noreply, socket |> assign(:email, email) |> put_flash(:error, message)}

      {:error, %Ecto.Changeset{errors: [user_id: _]}} ->
        resend_invitation_email(user, socket)
        {:noreply,
         socket
         |> assign(:email, email)
         |> put_flash(:warning, gettext("Resended Invitation, because ") <> email <> gettext(" already invited."))}
    end
  end

  defp send_invitation_email(user, password, socket) do
    if user.confirmed_at do
      UserAccounts.deliver_user_invitation_instructions(
        socket.assigns.current_user,
        user,
        socket.assigns.current_farm,
        Routes.navigation_url(socket, :index, socket.assigns.current_farm.id)
      )

      gettext("existing user - ")
    else
      UserAccounts.deliver_user_invitation_instructions(
        socket.assigns.current_user,
        user,
        socket.assigns.current_farm,
        password,
        &Routes.user_confirmation_url(socket, :confirm, &1)
      )

      gettext("new user - ")
    end
  end

  defp resend_invitation_email(user, socket) do
    UserAccounts.resend_user_invitation_instructions(
        socket.assigns.current_user,
        user,
        socket.assigns.current_farm,
        Routes.user_session_url(socket, :new)
      )
  end

  defp find_or_create_user(email, password) do
    user = UserAccounts.get_user_by_email(email)

    if user do
      user
    else
      {:ok, user} =
        UserAccounts.register_user(%{
          email: email,
          password: password,
          password_confirmation: password
        })

      user
    end
  end

  defp random_string(length) do
    :crypto.strong_rand_bytes(length) |> Base.url_encode64() |> binary_part(0, length)
  end
end
