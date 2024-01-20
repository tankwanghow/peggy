defmodule PeggyWeb.UserSessionController do
  use PeggyWeb, :controller

  alias Peggy.UserAccounts
  alias PeggyWeb.UserAuth

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, gettext("Account created successfully!"))
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, gettext("Password updated successfully!"))
  end

  def create(conn, params) do
    create(conn, params, gettext("Welcome back!"))
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    user = UserAccounts.get_user_by_email_and_password(email, password)

    if user do
      if user.confirmed_at do
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)
      else
        conn
        |> put_flash(:warn, gettext("Please Confirm your Account."))
        |> redirect(to: ~p"/users/log_in")
      end
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, gettext("Invalid email or password"))
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Logged out successfully."))
    |> UserAuth.log_out_user()
  end
end
