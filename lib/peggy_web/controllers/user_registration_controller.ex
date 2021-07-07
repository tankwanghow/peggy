defmodule PeggyWeb.UserRegistrationController do
  use PeggyWeb, :controller

  alias Peggy.UserAccounts
  alias Peggy.UserAccounts.User
  # alias PeggyWeb.UserAuth

  def new(conn, _params) do
    changeset = UserAccounts.change_user_registration(%User{})
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case UserAccounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _, _} =
          UserAccounts.deliver_user_confirmation_instructions(
            user,
            &Routes.user_confirmation_url(conn, :confirm, &1)
          )

        conn
        |> put_flash(:success, gettext("User registered successfully. Please confirm your account at ") <> user.email)
        |> redirect(to: "/")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end
end
