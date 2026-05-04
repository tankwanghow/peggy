defmodule PeggyWeb.MobileLive.Locations do
  @moduledoc """
  Mobile locations browser. Lists active pens grouped by house with
  current occupancy counts. Tapping a pen jumps to the mobile animals
  list pre-filtered by that pen — answering the floor question:
  "what's in pen EB-12?"
  """
  use PeggyWeb, :live_view

  alias Peggy.Locations

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.mobile_app flash={@flash} current_scope={@current_scope}>
      <div>
        <%!-- Top bar --%>
        <header class="sticky top-0 z-10 bg-base-100 border-b border-base-200 px-3 py-2 flex items-center gap-2">
          <h1 class="font-semibold text-lg flex-1">{gettext("Locations")}</h1>
          <input
            type="search"
            name="q"
            value={@filter}
            phx-change="filter"
            phx-debounce="300"
            placeholder={gettext("Search pen…")}
            autocomplete="off"
            class="input input-bordered input-sm w-40 font-mono"
          />
        </header>

        <ul class="px-3 py-2 space-y-2">
          <li
            :for={{house_code, rows} <- @grouped}
            class="rounded-xl border border-base-300 bg-base-100 overflow-hidden"
          >
            <div class="px-4 py-2 bg-base-200/50 text-xs uppercase tracking-wide text-base-content/60 font-mono">
              {gettext("House")} {house_code}
            </div>
            <ul class="divide-y divide-base-200">
              <li :for={r <- rows}>
                <.link
                  navigate={
                    ~p"/m/#{@current_scope.farm.slug}/animals?#{[pen_search: pen_code(r.pen)]}"
                  }
                  class="flex items-center gap-3 px-4 py-3 active:bg-base-200"
                >
                  <.icon name="hero-map-pin-micro" class="size-4 text-blue-600" />
                  <span class="font-mono font-semibold flex-1">{pen_code(r.pen)}</span>
                  <span class="text-right">
                    <span class={[
                      "text-lg font-mono font-bold",
                      r.total == 0 && "text-base-content/30",
                      r.total > 0 && "text-base-content"
                    ]}>
                      {r.total}
                    </span>
                    <span class="text-[10px] uppercase tracking-wide text-base-content/50 ml-1">
                      {gettext("animals")}
                    </span>
                  </span>
                  <.icon name="hero-chevron-right-micro" class="size-4 text-base-content/40" />
                </.link>
              </li>
            </ul>
          </li>
        </ul>

        <p :if={@grouped == []} class="px-4 py-8 text-center text-sm text-base-content/60">
          {gettext("No pens match the filter.")}
        </p>
      </div>
    </Layouts.mobile_app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    rows = Locations.pen_summary(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       page_title: gettext("Locations"),
       filter: "",
       all_rows: rows,
       grouped: group_rows(rows, "")
     )}
  end

  @impl true
  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, assign(socket, filter: q, grouped: group_rows(socket.assigns.all_rows, q))}
  end

  defp group_rows(rows, filter) do
    needle = filter |> to_string() |> String.trim() |> String.upcase()

    rows
    |> Enum.filter(fn r -> matches_filter?(r.pen, needle) end)
    |> Enum.group_by(fn r -> r.pen.house.code end)
    |> Enum.sort_by(fn {house_code, _} -> house_code end)
  end

  defp matches_filter?(_pen, ""), do: true

  defp matches_filter?(pen, needle) do
    String.contains?(String.upcase(pen.house.code), needle) or
      String.contains?(String.upcase(pen.code), needle) or
      String.contains?(String.upcase(pen_code(pen)), needle)
  end

  defp pen_code(%{code: code, house: %{code: hcode}}), do: "#{hcode}-#{code}"
  defp pen_code(%{code: code}), do: code
end
