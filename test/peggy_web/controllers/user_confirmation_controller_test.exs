defmodule PeggyWeb.UserConfirmationControllerTest do
  use PeggyWeb.ConnCase, async: true

  alias Peggy.UserAccounts
  alias Peggy.Repo
  import Peggy.UserAccountsFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/confirm" do
    test "renders the confirmation page", %{conn: conn} do
      conn = get(conn, Routes.user_confirmation_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "Resend confirmation instructions</h3>"
    end
  end

  describe "POST /users/confirm" do
    @tag :capture_log
    test "sends a new confirmation token", %{conn: conn, user: user} do
      conn =
        post(conn, Routes.user_confirmation_path(conn, :create), %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "If your email is in our system"
      assert Repo.get_by!(UserAccounts.UserToken, user_id: user.id).context == "confirm"
    end

    test "does not send confirmation token if User is confirmed", %{conn: conn, user: user} do
      Repo.update!(UserAccounts.User.confirm_changeset(user))

      conn =
        post(conn, Routes.user_confirmation_path(conn, :create), %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "If your email is in our system"
      refute Repo.get_by(UserAccounts.UserToken, user_id: user.id)
    end

    test "does not send confirmation token if email is invalid", %{conn: conn} do
      conn =
        post(conn, Routes.user_confirmation_path(conn, :create), %{
          "user" => %{"email" => "unknown@example.com"}
        })

      assert redirected_to(conn) == "/"
      assert get_flash(conn, :info) =~ "If your email is in our system"
      assert Repo.all(UserAccounts.UserToken) == []
    end
  end

  describe "GET /users/confirm/:token" do
    test "confirms the given token once", %{conn: conn, user: user} do
      token =
        extract_user_token(fn url ->
          UserAccounts.deliver_user_confirmation_instructions(user, url)
        end)

      conn = get(conn, Routes.user_confirmation_path(conn, :confirm, token))
      assert redirected_to(conn) == "/users/log_in"
      assert get_flash(conn, :success) =~ "User confirmed successfully"
      assert UserAccounts.get_user!(user.id).confirmed_at
      refute get_session(conn, :user_token)
      assert Repo.all(UserAccounts.UserToken) == []

      # When not logged in
      conn = get(conn, Routes.user_confirmation_path(conn, :confirm, token))
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) =~ "User confirmation link is invalid or it has expired"

      # When logged in
      conn =
        build_conn()
        |> log_in_user(user)
        |> get(Routes.user_confirmation_path(conn, :confirm, token))

      assert redirected_to(conn) == "/"
      refute get_flash(conn, :error)
    end

    test "does not confirm email with invalid token", %{conn: conn, user: user} do
      conn = get(conn, Routes.user_confirmation_path(conn, :confirm, "oops"))
      assert redirected_to(conn) == "/"
      assert get_flash(conn, :error) =~ "User confirmation link is invalid or it has expired"
      refute UserAccounts.get_user!(user.id).confirmed_at
    end
  end
end
