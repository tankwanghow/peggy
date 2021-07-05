defmodule Peggy.UserAccounts.UserNotifier do
  import Bamboo.Email

  defp deliver(email) do
    email = %{ email | from: Application.get_env(:peggy, Peggy.Mailer)[:username] }
    email |> Peggy.Mailer.deliver_now(response: true)
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    text_body = """
    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """

    new_email(
      to: user.email,
      subject: "Confirmation instructions",
      text_body: text_body
    )
    |> deliver
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    text_body = """

    ==============================

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """

    new_email(
      to: user.email,
      subject: "Reset Password instructions",
      text_body: text_body
    )
    |> deliver
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    text_body = """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """

    new_email(
      to: user.email,
      subject: "Update Emails instructions",
      text_body: text_body
    )
    |> deliver
  end
end
