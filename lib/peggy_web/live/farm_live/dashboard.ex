defmodule PeggyWeb.FarmLive.Dashboard do
  use PeggyWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl">
        <.header>
          {@current_scope.farm.name}
          <:subtitle>{gettext("Role: %{role}", role: @current_scope.role)}</:subtitle>
        </.header>

        <p class="mt-8 text-base-content/70">
          {gettext(
            "Dashboard placeholder — Phase 8 will populate today's tasks, mortality, sows due, vax due."
          )}
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}
end
