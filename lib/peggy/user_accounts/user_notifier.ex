defmodule Peggy.UserAccounts.UserNotifier do
  import Swoosh.Email
  import PeggyWeb.Gettext

  alias Peggy.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Peggy", "tankwanghow@gmail.com"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to invite account.
  """
  def deliver_new_user_invitation_instructions(admin, user, farm_name, pwd, url) do
    deliver(
      user.email,
      gettext("Invitation instructions"),
      gettext(
        """
        ==============================

        Hi %{email},

        %{admin} has invited you to join %{farm} at Peggy.

        Please follow the URL below:

        %{url}

        And Login using the following:

        email: %{email}
        password: %{pwd}

        If you don't want to join, please ignore this.

        ==============================
        """,
        email: user.email,
        url: url,
        farm: farm_name,
        pwd: pwd,
        admin: admin.email
      )
    )
  end

  def deliver_invitation_instructions(admin, user, farm_name, url) do
    deliver(
      user.email,
      gettext("Invitation instructions"),
      gettext(
        """
        ==============================

        Hi %{email},

        %{admin} has invited you to join %{farm} at Peggy.

        Please follow the URL below:

        %{url}

        If you don't want to join, please ignore this.

        ==============================
        """,
        email: user.email,
        url: url,
        farm: farm_name,
        admin: admin.email
      )
    )
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      gettext("Confirmation instructions"),
      gettext(
        """
        ==============================

        Hi %{email},

        You can confirm your account by visiting the URL below:

        %{url}

        If you didn't create an account with us, please ignore this.

        ==============================
        """,
        email: user.email,
        url: url
      )
    )
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(
      user.email,
      gettext("Reset password instructions"),
      gettext(
        """

        ==============================

        Hi %{email},

        You can reset your password by visiting the URL below:

        %{url}

        If you didn't request this change, please ignore this.

        ==============================
        """,
        email: user.email,
        url: url
      )
    )
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(
      user.email,
      gettext("Update email instructions"),
      gettext(
        """

        ==============================

        Hi %{email},

        You can change your email by visiting the URL below:

        %{url}

        If you didn't request this change, please ignore this.

        ==============================
        """,
        email: user.email,
        url: url
      )
    )
  end
end
