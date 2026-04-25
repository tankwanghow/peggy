defmodule PeggyWeb.FarmLive.Locations do
  use PeggyWeb, :live_view

  alias Peggy.Locations
  alias Peggy.Locations.House
  # House.purposes/0 referenced in the template
  alias Peggy.Policy

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl">
        <.header>
          {gettext("Locations")}
          <:subtitle>{gettext("Houses → pens")}</:subtitle>
          <:actions>
            <.button :if={@can_manage} phx-click="new_house" class="btn btn-primary btn-sm">
              {gettext("New house")}
            </.button>
          </:actions>
        </.header>

        <ul id="houses" class="mt-6 space-y-1">
          <li :for={h <- @houses} id={"house-#{h.id}"} class="rounded border border-base-300 p-3">
            <div class="flex justify-between items-center">
              <div>
                <.link
                  navigate={~p"/farms/#{@current_scope.farm.slug}/locations/houses/#{h.id}"}
                  class="font-semibold font-mono text-primary underline underline-offset-2 decoration-dotted hover:decoration-solid"
                >
                  {h.code}
                </.link>
                <span class="ml-2 text-sm text-base-content/60">
                  {h.purpose} · {length(h.pens)} {gettext("pens")}
                </span>
              </div>
              <div :if={@can_manage} class="flex gap-2">
                <.link
                  navigate={~p"/farms/#{@current_scope.farm.slug}/locations/houses/#{h.id}"}
                  class="btn btn-sm btn-ghost"
                >
                  {gettext("Manage pens")}
                </.link>
                <button phx-click="edit_house" phx-value-id={h.id} class="btn btn-sm btn-ghost">
                  {gettext("Edit")}
                </button>
                <button
                  phx-click="delete_house"
                  phx-value-id={h.id}
                  data-confirm={gettext("Delete house and all child pens?")}
                  class="btn btn-sm btn-ghost text-error"
                >
                  {gettext("Delete")}
                </button>
              </div>
            </div>
          </li>
          <li :if={@houses == []} class="text-base-content/60">{gettext("No houses yet.")}</li>
        </ul>

        <div
          :if={@form_kind}
          id="form-modal"
          class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
        >
          <div
            class="bg-base-100 rounded p-6 w-full max-w-md"
            phx-click-away="cancel_form"
            phx-window-keydown="cancel_form"
            phx-key="escape"
          >
            <h3 class="text-lg font-semibold mb-3">{@form_title}</h3>
            <.form
              for={@form}
              id="location-form"
              phx-submit="save"
              phx-change="validate"
              class="space-y-3"
            >
              <.input
                field={@form[:code]}
                type="text"
                label={gettext("Code")}
                class="w-full input font-mono"
                required
              />

              <.input
                field={@form[:purpose]}
                type="select"
                label={gettext("Purpose")}
                options={Enum.map(House.purposes(), &{String.capitalize(&1), &1})}
              />

              <div class="flex gap-2 justify-end">
                <button type="button" phx-click="cancel_form" class="btn btn-ghost">
                  {gettext("Cancel")}
                </button>
                <.button class="btn btn-primary" phx-disable-with={gettext("Saving...")}>
                  {gettext("Save")}
                </.button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:can_manage, Policy.can?(socket.assigns.current_scope, :manage_locations))
     |> assign(form_kind: nil, form: nil, form_title: nil, form_target: nil)
     |> load()}
  end

  @impl true
  def handle_event("cancel_form", _, socket), do: {:noreply, reset_form(socket)}

  def handle_event("new_house", _, socket) do
    guard(socket, fn ->
      open(socket, :house, nil, %House{purpose: "grower"}, gettext("New house"))
    end)
  end

  def handle_event("edit_house", %{"id" => id}, socket) do
    guard(socket, fn ->
      house = Locations.get_house!(socket.assigns.current_scope, String.to_integer(id))
      open(socket, :house, house, house, gettext("Edit house"))
    end)
  end

  def handle_event("delete_house", %{"id" => id}, socket) do
    guard(socket, fn ->
      h = Locations.get_house!(socket.assigns.current_scope, String.to_integer(id))
      {:ok, _} = Locations.delete_house(socket.assigns.current_scope, h)
      {:noreply, socket |> put_flash(:info, gettext("House deleted.")) |> load()}
    end)
  end

  def handle_event("validate", %{} = params, socket) do
    key = form_param_key(socket.assigns.form_kind)
    attrs = Map.get(params, key, %{})

    cs =
      changeset(
        socket.assigns.form_kind,
        socket.assigns.form_target || struct_for(socket.assigns.form_kind),
        attrs
      )

    {:noreply, assign(socket, :form, to_form(Map.put(cs, :action, :validate), as: key))}
  end

  def handle_event("save", %{} = params, socket) do
    guard(socket, fn ->
      key = form_param_key(socket.assigns.form_kind)
      attrs = Map.get(params, key, %{})
      do_save(socket, socket.assigns.form_kind, socket.assigns.form_target, attrs)
    end)
  end

  ## Helpers

  defp guard(socket, fun) do
    if socket.assigns.can_manage do
      case fun.() do
        {:noreply, s} -> {:noreply, s}
        %Phoenix.LiveView.Socket{} = s -> {:noreply, s}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized."))}
    end
  end

  defp open(socket, kind, target, base, title) do
    key = form_param_key(kind)
    cs = changeset(kind, base, %{})

    socket
    |> assign(
      form_kind: kind,
      form_target: target,
      form_title: title,
      form: to_form(cs, as: key)
    )
  end

  defp do_save(socket, :house, nil, attrs) do
    case Locations.create_house(socket.assigns.current_scope, attrs) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, gettext("House created.")) |> reset_form() |> load()}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs, as: "house"))}
    end
  end

  defp do_save(socket, :house, %House{} = h, attrs) do
    case Locations.update_house(socket.assigns.current_scope, h, attrs) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, gettext("House updated.")) |> reset_form() |> load()}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs, as: "house"))}
    end
  end

  defp reset_form(socket),
    do:
      assign(socket,
        form_kind: nil,
        form: nil,
        form_title: nil,
        form_target: nil
      )

  defp load(socket),
    do: assign(socket, :houses, Locations.list_houses(socket.assigns.current_scope))

  defp changeset(:house, target, attrs), do: Locations.change_house(target, attrs)

  defp struct_for(:house), do: %House{}

  defp form_param_key(:house), do: "house"
end
