defmodule PeggyWeb.FarmLive.Form do
  use PeggyWeb, :live_view
  alias Peggy.Sys
  alias Peggy.Sys.Farm

  @impl true
  def render(assigns) do
    ~H"""
    <p class="w-full text-3xl text-center font-medium"><%= @page_title %></p>
    <.form
      for={@form}
      id="farm"
      autocomplete="off"
      phx-change="validate"
      phx-submit="save"
      phx-trigger-action={@trigger_submit}
      action={@trigger_action}
      method={@trigger_method}
      class="max-w-2xl mx-auto w-[90%]"
    >
      <.input field={@form[:name]} label={gettext("Name")} />

      <.input field={@form[:address1]} label={gettext("Address Line 1")} />

      <.input field={@form[:address2]} label={gettext("Address Line 2")} />

      <div class="flex">
        <div class="w-[50%]">
          <.input field={@form[:city]} label={gettext("City")} />
        </div>
        <div class="w-[50%]">
          <.input field={@form[:zipcode]} label={gettext("Postal Code")} />
        </div>
      </div>

      <div class="flex">
        <div class="w-[50%]">
          <.input field={@form[:state]} label={gettext("State")} />
        </div>
        <div class="w-[50%]">
          <.input field={@form[:country]} label={gettext("Country")} list="countries" />
        </div>
      </div>
      <div class="flex">
        <div class="w-[50%]">
          <.input field={@form[:timezone]} label={gettext("Time Zone")} list="timezones" />
        </div>
        <div class="w-[50%]">
          <.input field={@form[:tel]} label={gettext("Tel")} />
        </div>
      </div>
      <div class="">
        <.input field={@form[:email]} type="email" label={gettext("Email")} />
      </div>
      <div class="2">
        <.input field={@form[:descriptions]} label={gettext("Descriptions")} />
      </div>
      <%= datalist(Peggy.Sys.countries(), "countries") %>
      <%= datalist(Tzdata.zone_list(), "timezones") %>
      <div class="flex justify-center gap-x-1 mt-2">
        <.save_button form={@form} />
        <%= if @live_action == :edit and Peggy.Authorization.can?(@current_user, :delete_farm, @farm) do %>
          <.delete_confirm_modal
            id="delete-farm"
            msg1={gettext("All Farm Data, will be LOST!!!")}
            msg2={gettext("Cannot Be Recover!!!")}
            confirm={JS.push("delete")}
          />
        <% end %>
        <.link navigate="/farms" class="blue button">
          <%= gettext("Back") %>
        </.link>
      </div>
    </.form>
    """
  end

  @impl true
  def mount(params, session, socket) do
    socket =
      socket
      |> assign(:current_farm, session["current_farm"])
      |> assign(:current_role, session["current_role"])

    case socket.assigns.live_action do
      :new -> mount_new(socket)
      :edit -> mount_edit(params, socket)
    end
  end

  defp mount_new(socket) do
    form = to_form(Sys.farm_changeset(%Farm{}, %{}, socket.assigns.current_user))

    {:ok,
     socket
     |> assign(:page_title, gettext("Creating Farm"))
     |> assign(:form, form)
     |> assign(:trigger_submit, false)
     |> assign(:trigger_action, nil)
     |> assign(:trigger_method, nil)
     |> assign(closing_days: [])}
  end

  defp mount_edit(%{"id" => id}, socket) do
    farm = Sys.get_farm!(id)
    form = to_form(Sys.farm_changeset(farm, %{}, socket.assigns.current_user))

    {:ok,
     socket
     |> assign(:page_title, gettext("Editing Farm"))
     |> assign(:form, form)
     |> assign(:trigger_submit, false)
     |> assign(:trigger_action, ~p"/update_active_farm?id=#{farm.id}")
     |> assign(:trigger_method, "post")
     |> assign(:farm, farm)}
  end

  @impl true
  def handle_event("validate", %{"farm" => params}, socket) do
    farm = if(socket.assigns[:farm], do: socket.assigns.farm, else: %Farm{})

    changeset =
      farm
      |> Sys.farm_changeset(params, socket.assigns.current_user)
      |> Map.put(:action, :insert)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"farm" => farm_params}, socket) do
    save_farm(socket, socket.assigns.live_action, farm_params)
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Sys.delete_farm(socket.assigns.farm, socket.assigns.current_user) do
      {:ok, com} ->
        if com.id == Util.attempt(socket.assigns.current_farm, :id) do
          {:noreply,
           socket
           |> redirect(to: ~p"/delete_active_farm")}
        else
          {:noreply,
           socket
           |> put_flash(:success, gettext("Farm Deleted!"))
           |> push_navigate(to: ~p"/farms")}
        end

      {:error, _, changeset, _} ->
        {:noreply,
         assign(socket, form: to_form(changeset))
         |> put_flash(:error, gettext("Failed to Delete Farm"))}

      :not_authorise ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("No Authorization"))}
    end
  end

  defp save_farm(socket, :edit, farm_params) do
    case Sys.update_farm(socket.assigns.farm, farm_params, socket.assigns.current_user) do
      {:ok, com} ->
        if com.id == Util.attempt(socket.assigns.current_farm, :id) do
          {:noreply,
           socket
           |> assign(:trigger_submit, true)}
        else
          {:noreply,
           socket
           |> assign(:trigger_submit, false)
           |> push_navigate(to: ~p"/farms")}
        end

      {:error, _, changeset, _} ->
        {:noreply,
         assign(socket, form: to_form(changeset))
         |> put_flash(:error, gettext("Failed to Update Farm"))}

      :not_authorise ->
        {:noreply,
         socket
         |> put_flash(:error, gettext("No Authorization"))}
    end
  end

  defp save_farm(socket, :new, farm_params) do
    case Sys.create_farm(farm_params, socket.assigns.current_user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_navigate(to: "/farms")}

      {:error, _, changeset, _} ->
        {:noreply,
         assign(socket, form: to_form(changeset))
         |> put_flash(:error, gettext("Failed to Create Farm"))}
    end
  end
end
