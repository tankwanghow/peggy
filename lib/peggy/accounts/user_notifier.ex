defmodule Peggy.Accounts.UserNotifier do
  import Swoosh.Email

  alias Peggy.Mailer
  alias Peggy.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    from_addr = Application.get_env(:peggy, :mail_from, {"Peggy", "noreply@peggy.asia"})

    email =
      new()
      |> to(recipient)
      |> from(from_addr)
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver a farm invitation to a potentially-unregistered recipient.
  """
  def deliver_farm_invitation(email, farm_name, role, url) do
    deliver(email, "You're invited to #{farm_name} on Peggy", """

    ==============================

    Hi,

    You've been invited to join "#{farm_name}" on Peggy as #{role}.

    Accept the invitation by visiting the URL below. If you don't have an
    account yet, you'll be asked to register first.

    #{url}

    If you didn't expect this email, you can safely ignore it.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
