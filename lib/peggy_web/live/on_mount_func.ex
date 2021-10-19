defmodule PeggyWeb.OnMountFunc do
  import Phoenix.LiveView

  alias Peggy.UserAccounts

  # Ensures common `assigns` are applied to all LiveViews
  # that attach this module as an `on_mount` hook
  def on_mount(_, _params, session, socket) do
    set_locale(session)

    {:cont,
     socket
     |> assign_current_user(session)
     |> assign_current_farm_user(session)}
  end

  defp set_locale(%{"locale" => locale}) do
    Gettext.put_locale(PeggyWeb.Gettext, if(locale, do: locale, else: "en"))
  end

  defp assign_current_user(socket, session) do
    assign_new(socket, :current_user, fn ->
      UserAccounts.get_user_by_session_token(session["user_token"])
    end)
  end

  defp assign_current_farm_user(socket, session) do
    case session["current_farm_user"] do
      nil -> push_redirect(socket, to: "/farms")
      farm_user -> assign(socket, :current_farm_user, farm_user)
    end
  end
end
