defmodule PeggyWeb.UserLive.New do
  use PeggyWeb, :live_view
  alias Peggy.UserAccounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("New User"))
     |> assign(:email, "")
     |> assign(:message, "")
     |> assign(:pwd, "")
     |> assign(:color, "green")
     |> assign(
       form:
         to_form(
           User.admin_add_user_changeset(%User{}, %{
             farm_id: socket.assigns.current_farm.id
           })
         )
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    user = Peggy.UserAccounts.get_user_by_email(params["email"]) || %User{}

    changeset =
      User.admin_add_user_changeset(user, params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("create_user", %{"user" => params}, socket) do
    case(
      Peggy.Sys.add_user_to_farm(
        socket.assigns.current_farm,
        params["email"],
        params["role"],
        socket.assigns.current_user
      )
    ) do
      {:ok, {u, _cu, pwd}} ->
        {:noreply,
         socket
         |> assign(
           :message,
           ~s|#{gettext("Successfully added")} #{u.email} #{gettext("to farm")}|
         )
         |> assign(:pwd, pwd)
         |> assign(:color, "green")}

      {:error, _cs} ->
        {:noreply,
         socket
         |> assign(:message, gettext("Failed to add user to farm"))
         |> assign(:pwd, nil)
         |> assign(:color, "rose")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <p class="w-full text-xl text-center font-medium"><%= @page_title %></p>
    <.form
      for={@form}
      id="user"
      phx-submit="create_user"
      phx-change="validate"
      autocomplete="off"
      class="w-11/12 mx-auto"
    >
      <div class="grid grid-cols-12 gap-2">
        <div class="col-span-8">
          <.input field={@form[:email]} label={gettext("Email")} />
        </div>
        <div class="col-span-4">
          <.input
            type="select"
            field={@form[:role]}
            options={Peggy.Authorization.roles()}
            required
            label={gettext("Role")}
          />
        </div>
        <.input field={@form[:password]} type="hidden" value="temp123456789" />
        <.input field={@form[:password_confirmation]} type="hidden" value="temp123456789" />
        <.input field={@form[:farm_id]} type="hidden" value={@current_farm.id} />
      </div>
      <div class="flex justify-center gap-x-1">
        <.button disabled={!@form.source.valid?} phx-disable-with={gettext("...")}>
          <%= gettext("Add User") %>
        </.button>
        <.link navigate={~p"/farms/#{@current_farm.id}/users"} class="blue button">
          <%= gettext("Back") %>
        </.link>
      </div>
    </.form>
    <%= if @message != "" do %>
      <div
        id="add-user-message"
        class={"border-2 border-#{@color}-600 bg-#{@color}-200 rounded text-center w-[90%] mt-2 mx-auto"}
      >
        <span class="m-2">
          <div><%= @message %></div>
          <%= if @pwd do %>
            <div class="font-bold font-mono text-red-500">
              <%= gettext("Password") %>
              <div class="font-bold font-mono text-2xl text-blue-500">
                <%= @pwd %>
              </div>
            </div>
          <% end %>
          <div>
            <%= gettext("Please contact your user") %>
          </div>
        </span>
      </div>
    <% end %>
    """
  end
end
