defmodule PeggyWeb.LiveHelpers do
  import Phoenix.LiveView

  alias Peggy.UserAccounts

  def set_locale(%{"locale" => locale}) do
    Gettext.put_locale(PeggyWeb.Gettext, if(locale, do: locale, else: "en"))
  end

  def assign_current_user(socket, session) do
    assign_new(socket, :current_user,
      fn -> UserAccounts.get_user_by_session_token(session["user_token"])
    end)
  end
end
