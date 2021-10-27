defmodule PeggyWeb.OnMountFunc do
  import Phoenix.LiveView

  alias Peggy.UserAccounts

  # Ensures common `assigns` are applied to all LiveViews
  # that attach this module as an `on_mount` hook
  def on_mount(_, _params, session, socket) do
    set_locale(session)
    socket = assign_current_user(socket, session)

    case session["current_farm_user"] do
      nil -> {:cont, socket}

      farm_user -> {:cont, assign(socket, :current_farm_user, farm_user)}
    end
  end

  defp set_locale(session) do
    Gettext.put_locale(PeggyWeb.Gettext, if(session["locale"], do: session["locale"], else: "en"))
  end

  defp assign_current_user(socket, session) do
    assign_new(socket, :current_user, fn ->
      UserAccounts.get_user_by_session_token(session["user_token"])
    end)
  end
end
