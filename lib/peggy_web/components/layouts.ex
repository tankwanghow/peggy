defmodule PeggyWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PeggyWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-300">
      <div class="flex-1">
        <.link navigate={~p"/"} class="flex items-center gap-2 font-bold text-lg">
          <span class="text-2xl">🐷</span>
          <span>Peggy</span>
          <span
            :if={@current_scope && @current_scope.farm}
            class="text-base-content/60 font-normal font-mono"
          >
            ({@current_scope.farm.slug})
          </span>
        </.link>
      </div>
      <div class="flex-none">
        <ul class="flex items-center gap-2">
          <li><.language_switcher current_scope={@current_scope} /></li>
          <li><.theme_toggle /></li>
          <%= if @current_scope && @current_scope.user do %>
            <li class="hidden sm:block text-sm text-base-content/70">
              {@current_scope.user.email}
            </li>
            <li :if={@current_scope.farm}>
              <.link
                href={~p"/view-mode?#{[mode: "mobile", to: "/m/#{@current_scope.farm.slug}"]}"}
                class="btn btn-ghost btn-sm"
                title={gettext("Mobile view")}
              >
                <.icon name="hero-device-phone-mobile-micro" class="size-4" />
                <span class="hidden sm:inline ml-1">{gettext("Mobile")}</span>
              </.link>
            </li>
            <li>
              <.link navigate={~p"/farms"} class="btn btn-ghost btn-sm">{gettext("My farms")}</.link>
            </li>
            <li>
              <.link navigate={~p"/users/settings"} class="btn btn-ghost btn-sm">
                {gettext("Settings")}
              </.link>
            </li>
            <li>
              <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost btn-sm">
                {gettext("Log out")}
              </.link>
            </li>
          <% else %>
            <li>
              <.link navigate={~p"/users/log-in"} class="btn btn-ghost btn-sm">
                {gettext("Log in")}
              </.link>
            </li>
            <li>
              <.link navigate={~p"/users/register"} class="btn btn-primary btn-sm">
                {gettext("Sign up")}
              </.link>
            </li>
          <% end %>
        </ul>
      </div>
    </header>

    <.farm_nav :if={@current_scope && @current_scope.farm} current_scope={@current_scope} />
    <.simulated_clock_banner :if={Peggy.FarmClock.simulated?(@current_scope)} scope={@current_scope} />

    <main class="px-4 py-4 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    <.confirm_modal />
    """
  end

  @doc """
  Mobile (phone-floor) layout. Renders the page edge-to-edge with no
  desktop navbar / farm-nav chrome, since space is tight and the
  primary controls live inside each mobile LiveView (sticky header,
  bottom sheets). A small back-to-desktop link sits in the corner so
  operators can escape if they need a feature mobile doesn't cover yet.

  ## Examples

      <Layouts.mobile flash={@flash} current_scope={@current_scope}>
        <header>...</header>
        <ul>...</ul>
      </Layouts.mobile>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def mobile(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-100">
      {render_slot(@inner_block)}
    </main>
    <.simulated_clock_banner
      :if={@current_scope && Peggy.FarmClock.simulated?(@current_scope)}
      scope={@current_scope}
    />
    <.flash_group flash={@flash} />
    <.confirm_modal />
    """
  end

  @doc """
  Mobile layout with bottom tab navigation and a "More" sheet for
  system actions (theme, switch farm, log out, escape to desktop).

  Pages provide their own top header (sticky search, etc.). The bottom
  nav is fixed; pad the page content with `pb-20` so the last row
  isn't hidden behind it.

  Pass `active` as one of `:home | :animals | :breeding` to highlight
  the current tab.

  ## Examples

      <Layouts.mobile_app flash={@flash} current_scope={@current_scope} active={:home}>
        <header>...</header>
        <ul>...</ul>
      </Layouts.mobile_app>
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :active, :atom, default: nil
  slot :inner_block, required: true

  def mobile_app(assigns) do
    ~H"""
    <main class="min-h-screen bg-base-100 pb-20">
      {render_slot(@inner_block)}
    </main>
    <.simulated_clock_banner
      :if={@current_scope && Peggy.FarmClock.simulated?(@current_scope)}
      scope={@current_scope}
    />
    <.mobile_bottom_nav current_scope={@current_scope} active={@active} />
    <.mobile_more_sheet current_scope={@current_scope} />
    <.flash_group flash={@flash} />
    <.confirm_modal />
    """
  end

  attr :current_scope, :map, required: true
  attr :active, :atom, default: nil

  defp mobile_bottom_nav(assigns) do
    ~H"""
    <nav class="fixed bottom-0 inset-x-0 z-30 bg-base-100 border-t border-base-300
                pb-[env(safe-area-inset-bottom)]">
      <ul class="grid grid-cols-4">
        <li>
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}"}
            class={[
              "flex flex-col items-center gap-1 py-3 active:bg-base-200",
              @active == :home && "text-primary",
              @active != :home && "text-base-content/60"
            ]}
          >
            <.icon name="hero-home" class="size-6" />
            <span class="text-[11px]">{gettext("Home")}</span>
          </.link>
        </li>
        <li>
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}/animals"}
            class={[
              "flex flex-col items-center gap-1 py-3 active:bg-base-200",
              @active == :animals && "text-primary",
              @active != :animals && "text-base-content/60"
            ]}
          >
            <.icon name="hero-identification" class="size-6" />
            <span class="text-[11px]">{gettext("Animals")}</span>
          </.link>
        </li>
        <li>
          <.link
            navigate={~p"/m/#{@current_scope.farm.slug}/breeding/lactating"}
            class={[
              "flex flex-col items-center gap-1 py-3 active:bg-base-200",
              @active == :breeding && "text-primary",
              @active != :breeding && "text-base-content/60"
            ]}
          >
            <.icon name="hero-heart" class="size-6" />
            <span class="text-[11px]">{gettext("Breeding")}</span>
          </.link>
        </li>
        <li>
          <button
            type="button"
            phx-click={JS.show(to: "#mobile-more-sheet", display: "flex")}
            class="w-full flex flex-col items-center gap-1 py-3 active:bg-base-200 text-base-content/60"
          >
            <.icon name="hero-bars-3" class="size-6" />
            <span class="text-[11px]">{gettext("More")}</span>
          </button>
        </li>
      </ul>
    </nav>
    """
  end

  attr :current_scope, :map, required: true

  defp mobile_more_sheet(assigns) do
    ~H"""
    <div
      id="mobile-more-sheet"
      class="hidden fixed inset-0 z-40 flex items-end"
    >
      <div
        class="absolute inset-0 bg-black/40"
        phx-click={JS.hide(to: "#mobile-more-sheet")}
      >
      </div>
      <div class="relative w-full bg-base-100 rounded-t-2xl pb-[env(safe-area-inset-bottom)]">
        <div class="flex justify-center pt-2 pb-1">
          <div class="w-10 h-1 rounded-full bg-base-300"></div>
        </div>
        <div :if={@current_scope && @current_scope.user} class="px-4 py-2 border-b border-base-200">
          <div class="text-sm font-semibold">{@current_scope.user.email}</div>
          <div :if={@current_scope.farm} class="text-xs text-base-content/60 font-mono">
            {@current_scope.farm.name} ({@current_scope.farm.slug})
          </div>
        </div>
        <ul class="divide-y divide-base-200">
          <li class="flex items-center justify-between gap-3 px-4 py-3">
            <span class="flex items-center gap-3">
              <.icon name="hero-swatch" class="size-5 text-base-content/60" />
              <span>{gettext("Theme")}</span>
            </span>
            <.theme_toggle />
          </li>
          <li class="flex items-center justify-between gap-3 px-4 py-3">
            <span class="flex items-center gap-3">
              <.icon name="hero-language" class="size-5 text-base-content/60" />
              <span>{gettext("Language")}</span>
            </span>
            <.language_switcher current_scope={@current_scope} />
          </li>
          <li :if={@current_scope && @current_scope.farm}>
            <.link
              navigate={~p"/m/#{@current_scope.farm.slug}/tasks"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-check-circle" class="size-5 text-base-content/60" />
              <span>{gettext("Tasks")}</span>
            </.link>
          </li>
          <li :if={@current_scope && @current_scope.farm}>
            <.link
              navigate={~p"/m/#{@current_scope.farm.slug}/locations"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-map-pin" class="size-5 text-base-content/60" />
              <span>{gettext("Locations")}</span>
            </.link>
          </li>
          <li :if={@current_scope && @current_scope.farm}>
            <.link
              href={~p"/view-mode?#{[mode: "desktop", to: "/farms/#{@current_scope.farm.slug}"]}"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-computer-desktop" class="size-5 text-base-content/60" />
              <span>{gettext("Open desktop view")}</span>
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/farms"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-arrows-right-left" class="size-5 text-base-content/60" />
              <span>{gettext("Switch farm")}</span>
            </.link>
          </li>
          <li>
            <.link
              navigate={~p"/users/settings"}
              class="flex items-center gap-3 px-4 py-4 active:bg-base-200"
            >
              <.icon name="hero-cog-6-tooth" class="size-5 text-base-content/60" />
              <span>{gettext("Account settings")}</span>
            </.link>
          </li>
          <li>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="flex items-center gap-3 px-4 py-4 active:bg-error/10 text-error"
            >
              <.icon name="hero-arrow-left-on-rectangle" class="size-5" />
              <span>{gettext("Log out")}</span>
            </.link>
          </li>
        </ul>
        <button
          type="button"
          phx-click={JS.hide(to: "#mobile-more-sheet")}
          class="w-full py-3 text-sm text-base-content/60 border-t border-base-200"
        >
          {gettext("Close")}
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Minimal layout used by printable / "preview & print" pages.

  Renders no app navigation, sets A4 page size, and hides anything
  with class `print-hide` when the browser print dialog is open.

  ## Examples

      <Layouts.print flash={@flash} title="Gestating sows">
        <table>...</table>
      </Layouts.print>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :title, :string, default: nil
  slot :inner_block, required: true

  def print(assigns) do
    ~H"""
    <script>
      // Print preview is always rendered in light theme so paper output and
      // on-screen preview match, regardless of the user's site preference.
      document.documentElement.setAttribute("data-theme", "light");
    </script>
    <style>
      @page {
        size: A4;
        margin: 12mm 12mm 16mm 12mm;
        @bottom-center {
          content: "Page " counter(page) " of " counter(pages);
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-size: 9pt;
          color: #000;
        }
      }
      @media print {
        .print-hide { display: none !important; }
        html, body { background: white !important; }
        /* Force everything inside the print sheet to pure black on white. */
        .print-sheet, .print-sheet * {
          color: #000 !important;
          background: transparent !important;
          border-color: #000 !important;
          box-shadow: none !important;
          text-shadow: none !important;
        }
        .print-sheet svg, .print-sheet svg * {
          fill: #000 !important;
          stroke: #000 !important;
        }
        /* Ensure browsers respect our forced colors instead of auto-tweaking. */
        .print-sheet { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
      }
      .print-page {
        max-width: 186mm; /* A4 minus 12mm margins */
        margin: 0 auto;
        padding: 4mm 0;
      }
      @media screen {
        body { background: #f3f4f6; }
        .print-sheet {
          background: white;
          padding: 6mm 16mm 16mm 16mm;
          box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
      }
    </style>
    <div class="print-page">
      <div class="print-sheet">
        {render_slot(@inner_block)}
      </div>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  attr :scope, :map, required: true

  defp simulated_clock_banner(assigns) do
    ~H"""
    <div class="bg-warning/15 border-b border-warning/30 text-warning-content text-sm">
      <div class="mx-auto max-w-5xl px-4 sm:px-6 lg:px-8 py-1.5 flex items-center gap-2">
        <.icon name="hero-clock-micro" class="size-4 text-warning" />
        <span>
          {gettext("Simulated date: %{date}.", date: @scope.farm.simulated_today)}
          {gettext("All age, gestation, and lactation calculations use this date instead of today.")}
        </span>
        <.link
          :if={Peggy.Policy.can?(@scope, :manage_farm_settings)}
          navigate={~p"/farms/#{@scope.farm.slug}/settings"}
          class="ml-auto underline underline-offset-2 hover:no-underline"
        >
          {gettext("Change")}
        </.link>
      </div>
    </div>
    """
  end

  attr :current_scope, :map, required: true

  defp farm_nav(assigns) do
    ~H"""
    <nav class="border-b border-base-300 bg-base-200/50 px-4 sm:px-6 lg:px-8 overflow-visible">
      <div class="mx-auto max-w-5xl flex items-center justify-center gap-1 flex-wrap text-sm overflow-visible">
        <.farm_nav_link
          href={~p"/farms/#{@current_scope.farm.slug}"}
          icon="hero-home-micro"
          label={gettext("Dashboard")}
        />
        <.farm_nav_link
          href={~p"/farms/#{@current_scope.farm.slug}/locations"}
          icon="hero-map-pin-micro"
          label={gettext("Locations")}
        />
        <div
          :if={Peggy.Policy.can?(@current_scope, :view_animals)}
          class="dropdown dropdown-bottom"
        >
          <div
            tabindex="0"
            role="button"
            class="flex items-center gap-1.5 px-3 py-2.5 rounded-md text-base-content/70 hover:text-base-content hover:bg-base-300/50 transition-colors whitespace-nowrap cursor-pointer"
          >
            <.icon name="hero-identification-micro" class="size-4" />
            {gettext("Animals")}
            <.icon name="hero-chevron-down-micro" class="size-3" />
          </div>
          <ul
            tabindex="0"
            class="dropdown-content menu z-50 mt-1 w-56 rounded-md border border-base-300 bg-base-100 p-1 shadow-lg"
          >
            <li>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/animals"}>
                {gettext("Presents Animal")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :manage_animals)}>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/animals?new=1"}>
                {gettext("Register animal")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :manage_animals)}>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/animals/batch-register"}>
                {gettext("Batch Register Sire/Dam")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_movement)}>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/animals/bulk-move"}>
                {gettext("Bulk Move Sire/Dam")}
              </.link>
            </li>
          </ul>
        </div>
        <div
          :if={Peggy.Policy.can?(@current_scope, :read_breeding)}
          class="dropdown dropdown-bottom"
        >
          <div
            tabindex="0"
            role="button"
            class="flex items-center gap-1.5 px-3 py-2.5 rounded-md text-base-content/70 hover:text-base-content hover:bg-base-300/50 transition-colors whitespace-nowrap cursor-pointer"
          >
            <.icon name="hero-heart-micro" class="size-4" />
            {gettext("Breeding")}
            <.icon name="hero-chevron-down-micro" class="size-3" />
          </div>
          <ul
            tabindex="0"
            class="dropdown-content menu z-50 mt-1 w-56 rounded-md border border-base-300 bg-base-100 p-1 shadow-lg"
          >
            <li>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/serviceable"}>
                {gettext("Serviceable")}
              </.link>
            </li>
            <li>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/gestating"}>
                {gettext("Gestating")}
              </.link>
            </li>
            <li>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/lactating"}>
                {gettext("Lactating")}
              </.link>
            </li>
            <li>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/weaned"}>
                {gettext("Weaned")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_breeding)}>
              <hr class="my-1 border-base-300" />
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_breeding)}>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/gestating?new=service"}>
                {gettext("Record Service")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_breeding)}>
              <.link navigate={
                ~p"/farms/#{@current_scope.farm.slug}/breeding/gestating?new=farrowing"
              }>
                {gettext("Record Farrowing")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_breeding)}>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/lactating?new=weaning"}>
                {gettext("Record Weaning")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_breeding)}>
              <hr class="my-1 border-base-300" />
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_breeding)}>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/batch-service"}>
                {gettext("Batch Service")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_breeding)}>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/batch-farrowing"}>
                {gettext("Batch Farrowing")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_breeding)}>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/batch-weaning"}>
                {gettext("Batch Weaning")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_breeding)}>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/close-services"}>
                {gettext("Close Services")}
              </.link>
            </li>
            <li :if={Peggy.Policy.can?(@current_scope, :record_breeding)}>
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/deleted"}>
                {gettext("Deleted")}
              </.link>
            </li>
          </ul>
        </div>
        <.farm_nav_link
          :if={Peggy.Policy.can?(@current_scope, :view_reports)}
          href={~p"/farms/#{@current_scope.farm.slug}/reports"}
          icon="hero-chart-bar-micro"
          label={gettext("Reports")}
        />
        <.farm_nav_link
          :if={Peggy.Policy.can?(@current_scope, :view_tasks)}
          href={~p"/farms/#{@current_scope.farm.slug}/tasks"}
          icon="hero-check-circle-micro"
          label={gettext("Tasks")}
        />
        <.farm_nav_link
          :if={Peggy.Policy.can?(@current_scope, :manage_farm_settings)}
          href={~p"/farms/#{@current_scope.farm.slug}/settings"}
          icon="hero-cog-6-tooth-micro"
          label={gettext("Settings")}
        />
      </div>
    </nav>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp farm_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="flex items-center gap-1.5 px-3 py-2.5 rounded-md text-base-content/70 hover:text-base-content hover:bg-base-300/50 transition-colors whitespace-nowrap"
    >
      <.icon name={@icon} class="size-4" />
      {@label}
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc "Language picker; persists to user.locale via LocaleController. Logged-in only."
  attr :current_scope, :map, required: true

  def language_switcher(assigns) do
    ~H"""
    <div :if={@current_scope && @current_scope.user} class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm gap-1" title={gettext("Language")}>
        <.icon name="hero-language-micro" class="size-4" />
        <span class="hidden sm:inline">{language_label(@current_scope.user.locale)}</span>
      </div>
      <ul tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-50 w-44 p-2 shadow">
        <li :for={{code, label} <- language_options()}>
          <.link
            href={~p"/locale/#{code}"}
            class={@current_scope.user.locale == code && "menu-active"}
          >
            {label}
          </.link>
        </li>
      </ul>
    </div>
    """
  end

  defp language_options, do: [{"en", "English"}, {"ms", "Bahasa Malaysia"}, {"zh", "中文"}]

  defp language_label(code) do
    {_, label} = Enum.find(language_options(), {code, code}, fn {c, _} -> c == code end)
    label
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
