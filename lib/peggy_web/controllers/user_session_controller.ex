defmodule PeggyWeb.UserSessionController do
  use PeggyWeb, :controller

  alias Peggy.UserAccounts
  alias PeggyWeb.UserAuth

  def new(conn, _params) do
    render(conn, "new.html", error_message: nil, info_message: nil)
  end

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    case UserAccounts.get_confirmed_user_by_email_and_password(email, password) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user, user_params)
      {:error, "confirm"} ->
        render(conn |> put_flash(:info, gettext("Confirm your account at the email you registered")), "new.html")
      _ ->
        render(conn |> put_flash(:error, gettext("Invalid email or password")), "new.html")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:success, gettext("Logged out successfully."))
    |> UserAuth.log_out_user()
  end

  def force_logout(conn, _params) do
    conn
    |> put_flash(
      :info,
      gettext("SECURITY UPDATE. Please login again.")
    )
    |> UserAuth.log_out_user()
  end
end
