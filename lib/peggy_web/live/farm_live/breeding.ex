defmodule PeggyWeb.FarmLive.Breeding do
  @moduledoc """
  Thin redirect from the legacy `/breeding` URL (and its `?tab=` variants)
  to the per-tab LiveViews under `/breeding/<tab>`.
  """
  use PeggyWeb, :live_view

  alias PeggyWeb.FarmLive.Breeding.Shared

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    tab = param_tab(params["tab"])
    slug = socket.assigns.current_scope.farm.slug

    query =
      params
      |> Map.drop(["tab", "farm_slug"])
      |> Shared.prune_query()

    path = build_path(slug, tab, query)
    {:noreply, push_navigate(socket, to: path)}
  end

  defp build_path(slug, tab, query) do
    base = tab_base(slug, tab)

    case query do
      m when map_size(m) == 0 -> base
      m -> base <> "?" <> URI.encode_query(m)
    end
  end

  defp tab_base(slug, "serviceable"), do: ~p"/farms/#{slug}/breeding/serviceable"
  defp tab_base(slug, "lactating"), do: ~p"/farms/#{slug}/breeding/lactating"
  defp tab_base(slug, "weaned"), do: ~p"/farms/#{slug}/breeding/weaned"
  defp tab_base(slug, "deleted"), do: ~p"/farms/#{slug}/breeding/deleted"
  defp tab_base(slug, _), do: ~p"/farms/#{slug}/breeding/gestating"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-6xl p-6 text-sm text-base-content/60">
        {gettext("Redirecting…")}
      </div>
    </Layouts.app>
    """
  end

  defp param_tab("serviceable"), do: "serviceable"
  defp param_tab("lactating"), do: "lactating"
  defp param_tab("weaned"), do: "weaned"
  defp param_tab("deleted"), do: "deleted"
  defp param_tab(_), do: "gestating"
end
