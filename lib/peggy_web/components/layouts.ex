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
          <li><.theme_toggle /></li>
          <%= if @current_scope && @current_scope.user do %>
            <li class="hidden sm:block text-sm text-base-content/70">
              {@current_scope.user.email}
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

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  attr :current_scope, :map, required: true

  defp farm_nav(assigns) do
    ~H"""
    <nav class="border-b border-base-300 bg-base-200/50 px-4 sm:px-6 lg:px-8 overflow-visible">
      <div class="mx-auto max-w-5xl flex items-center gap-1 flex-wrap text-sm overflow-visible">
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
        <.farm_nav_link
          :if={Peggy.Policy.can?(@current_scope, :view_animals)}
          href={~p"/farms/#{@current_scope.farm.slug}/animals"}
          icon="hero-identification-micro"
          label={gettext("Animals")}
        />
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
              <.link navigate={~p"/farms/#{@current_scope.farm.slug}/breeding/deleted"}>
                {gettext("Deleted")}
              </.link>
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
          </ul>
        </div>
        <.farm_nav_link
          :if={Peggy.Policy.can?(@current_scope, :view_audit)}
          href={~p"/farms/#{@current_scope.farm.slug}/audit"}
          icon="hero-clipboard-document-list-micro"
          label={gettext("Audit")}
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
