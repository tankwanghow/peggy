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
     |> assign(:email, "")
     |> assign(:resend, false)}
  end

  # @impl true
  # def handle_event("check_invite_user", %{"invite_user" => params}, socket) do
  #   email = params["email"]

  #   if email == socket.assigns.current_user.email do
  #     {:noreply, socket |> assign(:email, "") |> put_flash(:error, "Cannot Invite Yourself")}
  #   else
  #     user = UserAccounts.get_user_by_email(email)
  #     farm = if user, do: Company.get_farm(socket.assigns.current_farm.id, user)
  #     resend = if farm, do: true, else: false

  #     {:noreply, socket |> assign(:email, email) |> assign(:resend, resend)}
  #   end
  # end

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
        {:noreply,
         socket
         |> put_flash(:success, gettext("Invitation email has been sent to ") <> user.email)
         |> push_redirect(to: "/farms/#{socket.assigns.current_farm.id}/navigation")}

      {:error, %Ecto.Changeset{} = changeset, message} ->
        {:noreply, socket |> assign(:changeset, changeset) |> put_flash(:error, message)}
    end

    # if user.confirmed_at do
    #   UserAccounts.deliver_user_invitation_instructions(
    #     socket.assigns.current_user,
    #     user,
    #     socket.assigns.current_farm,
    #     &Routes.navigation_url(socket, :index, &1)
    #   )
    # else
    #   UserAccounts.deliver_user_invitation_instructions(
    #     socket.assigns.current_user,
    #     user,
    #     socket.assigns.current_farm,
    #     password,
    #     &Routes.user_confirmation_url(socket, :confirm, &1)
    #   )
    # end
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
