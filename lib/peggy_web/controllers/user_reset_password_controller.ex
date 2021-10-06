defmodule PeggyWeb.UserResetPasswordController do
  use PeggyWeb, :controller

  alias Peggy.UserAccounts

  plug :get_user_by_reset_password_token when action in [:edit, :update]

  def new(conn, _params) do
    render(conn, "new.html")
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = UserAccounts.get_user_by_email(email) do
      UserAccounts.deliver_user_reset_password_instructions(
        user,
        &Routes.user_reset_password_url(conn, :edit, &1)
      )
    end

    # Regardless of the outcome, show an impartial success/error message.
    conn
    |> put_flash(
      :info,
      "If your email is in our system, you will receive instructions to reset your password shortly."
    )
    |> redirect(to: "/")
  end

  def edit(conn, _params) do
    render(conn, "edit.html", changeset: UserAccounts.change_user_password(conn.assigns.user))
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def update(conn, %{"user" => user_params}) do
    case UserAccounts.reset_user_password(conn.assigns.user, user_params) do
      {:ok, _} ->
        if conn.assigns.user.confirm_at == nil, do: UserAccounts.confirm_user(conn.assigns.user)
        conn
        |> put_flash(:success, gettext("Password reset successfully."))
        |> redirect(to: Routes.user_session_path(conn, :new))

      {:error, changeset} ->
        render(conn |> put_flash(:error, gettext("Oops, something went wrong! Please check the errors below.")), "edit.html", changeset: changeset)
    end
  end

  defp get_user_by_reset_password_token(conn, _opts) do
    %{"token" => token} = conn.params

    if user = UserAccounts.get_user_by_reset_password_token(token) do
      conn |> assign(:user, user) |> assign(:token, token)
    else
      conn
      |> put_flash(:error, gettext("Reset password link is invalid or it has expired."))
      |> redirect(to: "/")
      |> halt()
    end
  end
end
