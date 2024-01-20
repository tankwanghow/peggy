defmodule PeggyWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At the first glance, this module may seem daunting, but its goal is
  to provide some core building blocks in your application, such modals,
  tables, and forms. The components are mostly markup and well documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The default components use Tailwind CSS, a utility-first CSS framework.
  See the [Tailwind CSS documentation](https://tailwindcss.com) to learn
  how to customize them or feel free to swap in another framework altogether.

  Icons are provided by [heroicons](https://heroicons.com). See `icon/1` for usage.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS
  import PeggyWeb.Gettext

  @doc """
  Renders a modal.

  ## Examples

      <.modal id="confirm-modal">
        Are you sure?
        <:confirm>OK</:confirm>
        <:cancel>Cancel</:cancel>
      </.modal>

  JS commands may be passed to the `:on_cancel` and `on_confirm` attributes
  for the caller to react to each button press, for example:

      <.modal id="confirm" on_confirm={JS.push("delete")} on_cancel={JS.navigate(~p"/posts")}>
        Are you sure you?
        <:confirm>OK</:confirm>
        <:cancel>Cancel</:cancel>
      </.modal>
  """
  attr(:id, :string, required: true)
  attr(:show, :boolean, default: false)
  attr(:on_cancel, JS, default: %JS{})
  attr(:on_confirm, JS, default: %JS{})
  attr(:max_w, :string, default: "max-w-3xl")

  slot(:inner_block, required: true)
  slot(:title)
  slot(:subtitle)
  slot(:confirm)
  slot(:cancel)

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-remove={hide_modal(@on_cancel, @id)}
      phx-mounted={@show && show_modal(@id)}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="fixed inset-0 bg-zinc-50/90 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class={"w-full #{@max_w} p-4 sm:p-6 lg:py-8"}>
            <.focus_wrap
              id={"#{@id}-container"}
              phx-mounted={@show && show_modal(@id)}
              phx-window-keydown={JS.exec("phx-remove", to: "##{@id}")}
              phx-key="escape"
              class="hidden relative rounded-2xl bg-white p-14 shadow-lg shadow-zinc-700/10 ring-1 ring-zinc-700/10 transition"
            >
              <div class="absolute top-6 right-5">
                <button
                  phx-click={JS.exec("phx-remove", to: "##{@id}")}
                  type="button"
                  class="-m-3 flex-none p-3 opacity-20 hover:opacity-40"
                  aria-label={gettext("close")}
                >
                  esc <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
                </button>
              </div>
              <div id={"#{@id}-content"}>
                <header :if={@title != []}>
                  <h1 id={"#{@id}-title"} class="text-lg font-semibold leading-8 text-zinc-800">
                    <%= render_slot(@title) %>
                  </h1>
                  <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
                    <%= render_slot(@subtitle) %>
                  </p>
                </header>
                <%= render_slot(@inner_block) %>
                <div
                  :if={@confirm != [] or @cancel != []}
                  class="mt-2 grid grid-cols-4 gap-1 justify-items-center"
                >
                  <.button
                    :for={confirm <- @confirm}
                    id={"#{@id}-confirm"}
                    phx-click={@on_confirm}
                    phx-disable-with
                    class="col-start-2 py-2 px-3"
                  >
                    <%= render_slot(confirm) %>
                  </.button>
                  <.link
                    :for={cancel <- @cancel}
                    phx-click={JS.exec("phx-remove", to: "##{@id}")}
                    class="py-2 px-3 rounded-lg border font-semibold leading-6 bg-blue-200 hover:bg-blue-400 col-start-3"
                  >
                    <%= render_slot(cancel) %>
                  </.link>
                </div>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr(:id, :string, default: "flash", doc: "the optional id of flash container")
  attr(:flash, :map, default: %{}, doc: "the map of flash messages to display")
  attr(:title, :string, default: nil)
  attr(:kind, :atom, values: [:info, :warn, :error], doc: "used for styling and flash lookup")
  attr(:rest, :global, doc: "the arbitrary HTML attributes to add to the flash container")

  slot(:inner_block, doc: "the optional inner block that renders the flash message")

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "shake fixed top-10 left-12 w-80 sm:w-96 z-50 rounded-lg p-3 ring-1",
        @kind == :info && "bg-emerald-50 text-emerald-800 ring-emerald-500 fill-cyan-900",
        @kind == :warn && "bg-amber-50 text-amber-800 ring-amber-500 fill-amber-900",
        @kind == :error && "bg-rose-50 text-rose-900 shadow-md ring-rose-500 fill-rose-900"
      ]}
      {@rest}
    >
      <p :if={@title} class="flex items-center gap-1.5 text-sm font-semibold leading-6">
        <.icon :if={@kind == :info} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :warn} name="hero-information-circle-mini" class="h-4 w-4" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle-mini" class="h-4 w-4" />
        <%= @title %>
      </p>
      <p class="mt-2 text-sm leading-5"><%= msg %></p>
      <button type="button" class="group absolute top-1 right-1 p-2" aria-label={gettext("close")}>
        <.icon name="hero-x-mark-solid" class="h-5 w-5 opacity-40 group-hover:opacity-70" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr(:flash, :map, required: true, doc: "the map of flash messages")

  def flash_group(assigns) do
    ~H"""
    <.flash kind={:info} title={gettext("Success!")} flash={@flash} />
    <.flash kind={:warn} title={gettext("Warning!")} flash={@flash} />
    <.flash kind={:error} title={gettext("Error!")} flash={@flash} />
    <.flash
      id="disconnected"
      kind={:error}
      title={gettext("We can't find the internet")}
      phx-disconnected={show("#disconnected")}
      phx-connected={hide("#disconnected")}
      hidden
    >
      Attempting to reconnect <.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
    </.flash>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr(:for, :any, required: true, doc: "the datastructure for the form")
  attr(:as, :any, default: nil, doc: "the server side parameter to collect all input under")

  attr(:rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target),
    doc: "the arbitrary HTML attributes to apply to the form tag"
  )

  slot(:inner_block, required: true)
  slot(:actions, doc: "the slot for form actions, such as a submit button")

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="mt-5 space-y-4">
        <%= render_slot(@inner_block, f) %>
        <div :for={action <- @actions} class="flex items-center justify-between gap-6">
          <%= render_slot(action, f) %>
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" class="ml-2">Send!</.button>
  """
  attr(:type, :string, default: "submit")
  attr(:class, :string, default: nil)
  attr(:rest, :global, include: ~w(disabled form name value))

  slot(:inner_block, required: true)

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg bg-zinc-900 hover:bg-zinc-700 py-2 px-3",
        "text-sm font-semibold leading-6 text-white active:text-white/80",
        @class
      ]}
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </button>
    """
  end

  @doc """
  Renders an input with label and error messages.

  A `%Phoenix.HTML.Form{}` and field name may be passed to the input
  to build input names and error messages, or all the attributes and
  errors may be passed explicitly.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr(:id, :any, default: nil)
  attr(:name, :any)
  attr(:label, :string, default: nil)
  attr(:value, :any)
  attr(:url, :string, default: nil)
  attr(:feedback, :boolean, default: false)
  attr(:"phx-debounce", :string, default: "blur")
  attr(:klass, :string, default: "")

  attr(:type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file hidden month number password
                 range radio search select tel text textarea time url week)
  )

  attr(:field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"
  )

  attr(:errors, :list, default: [])
  attr(:checked, :boolean, doc: "the checked flag for checkbox inputs")
  attr(:prompt, :string, default: nil, doc: "the prompt for select inputs")
  attr(:options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2")
  attr(:multiple, :boolean, default: false, doc: "the multiple flag for select inputs")

  attr(:rest, :global,
    include: ~w(autocomplete cols disabled list form max maxlength min minlength
                  required pattern placeholder readonly rows size step tag-url)
  )

  slot(:inner_block)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox", value: value} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn -> Phoenix.HTML.Form.normalize_value("checkbox", value) end)

    ~H"""
    <div phx-feedback-for={@name}>
      <label class="flex items-center gap-4 text-sm leading-6 text-zinc-600">
        <input type="hidden" name={@name} value="false" />
        <input
          type="checkbox"
          phx-debounce={Map.get(assigns, :"phx-debounce")}
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="rounded border-zinc-300 text-zinc-900 focus:ring-0"
          {@rest}
        />
        <%= @label %>
      </label>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label :if={@label} for={@id}><%= @label %></.label>
      <select
        id={@id}
        name={@name}
        class="p-1 block w-full rounded border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0"
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value=""><%= @prompt %></option>
        <%= Phoenix.HTML.Form.options_for_select(@options, @value) %>
      </select>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div phx-feedback-for={@name}>
      <.label :if={@label} for={@id}><%= @label %></.label>
      <textarea
        id={@id}
        name={@name}
        phx-debounce={Map.get(assigns, :"phx-debounce")}
        class={[
          "block w-full rounded text-zinc-900 focus:ring-0",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          "min-h-[6rem] border-zinc-300 focus:border-zinc-400 p-1",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        url={@url}
        {@rest}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @value) %></textarea>
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  # Always Show Feedback
  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(%{feedback: true} = assigns) do
    ~H"""
    <div id={"phx-feedback-for-#{@id}"}>
      <.label :if={@label} for={@id}><%= @label %></.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        phx-debounce={Map.get(assigns, :"phx-debounce")}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        url={@url}
        class={[
          @klass,
          "block w-full rounded text-zinc-900 focus:ring-0",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          "border-zinc-300 focus:border-zinc-400 p-1",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div id={"phx-feedback-for-#{@id}"} phx-feedback-for={@name}>
      <.label :if={@label} for={@id}><%= @label %></.label>
      <input
        type={@type}
        name={@name}
        id={@id}
        phx-debounce={Map.get(assigns, :"phx-debounce")}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        url={@url}
        class={[
          @klass,
          "block w-full rounded text-zinc-900 focus:ring-0",
          "phx-no-feedback:border-zinc-300 phx-no-feedback:focus:border-zinc-400",
          "border-zinc-300 focus:border-zinc-400 p-1",
          @errors != [] && "border-rose-400 focus:border-rose-400"
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}><%= msg %></.error>
    </div>
    """
  end

  @doc """
  Renders a label.
  """
  attr(:for, :string, default: nil)
  slot(:inner_block, required: true)

  def label(assigns) do
    ~H"""
    <label for={@for} class="block text-sm font-semibold leading-6 text-zinc-800">
      <%= render_slot(@inner_block) %>
    </label>
    """
  end

  @doc """
  Generates a generic error message.
  """
  slot(:inner_block, required: true)

  def error(assigns) do
    ~H"""
    <span class="text-sm text-rose-600 phx-no-feedback:hidden tracking-tighter">
      <.icon name="hero-x-circle-mini" class="h-3 w-3" />
      <%= render_slot(@inner_block) %>
    </span>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr(:class, :string, default: nil)

  slot(:inner_block, required: true)
  slot(:subtitle)
  slot(:actions)

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", @class]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-zinc-800">
          <%= render_slot(@inner_block) %>
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm leading-6 text-zinc-600">
          <%= render_slot(@subtitle) %>
        </p>
      </div>
      <div class="flex-none"><%= render_slot(@actions) %></div>
    </header>
    """
  end

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """
  attr(:id, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:row_id, :any, default: nil, doc: "the function for generating the row id")
  attr(:row_click, :any, default: nil, doc: "the function for handling phx-click on each row")

  attr(:row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"
  )

  slot :col, required: true do
    attr(:label, :string)
  end

  slot(:action, doc: "the slot for showing user actions in the last table column")

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-y-auto px-4 sm:overflow-visible sm:px-0">
      <table class="w-[40rem] mt-11 sm:w-full">
        <thead class="text-sm text-left leading-6 text-zinc-500">
          <tr>
            <th :for={col <- @col} class="p-0 pr-6 pb-4 font-normal"><%= col[:label] %></th>
            <th class="relative p-0 pb-4"><span class="sr-only"><%= gettext("Actions") %></span></th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={match?(%Phoenix.LiveView.LiveStream{}, @rows) && "stream"}
          class="relative divide-y divide-zinc-100 border-t border-zinc-200 text-sm leading-6 text-zinc-700"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)} class="group hover:bg-zinc-50">
            <td
              :for={{col, i} <- Enum.with_index(@col)}
              phx-click={@row_click && @row_click.(row)}
              class={["relative p-0", @row_click && "hover:cursor-pointer"]}
            >
              <div class="block py-4 pr-6">
                <span class="absolute -inset-y-px right-0 -left-4 group-hover:bg-zinc-50 sm:rounded-l-xl" />
                <span class={["relative", i == 0 && "font-semibold text-zinc-900"]}>
                  <%= render_slot(col, @row_item.(row)) %>
                </span>
              </div>
            </td>
            <td :if={@action != []} class="relative w-14 p-0">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span class="absolute -inset-y-px -right-4 left-0 group-hover:bg-zinc-50 sm:rounded-r-xl" />
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  <%= render_slot(action, @row_item.(row)) %>
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title"><%= @post.title %></:item>
        <:item title="Views"><%= @post.views %></:item>
      </.list>
  """
  slot :item, required: true do
    attr(:title, :string, required: true)
  end

  def list(assigns) do
    ~H"""
    <div class="mt-14">
      <dl class="-my-4 divide-y divide-zinc-100">
        <div :for={item <- @item} class="flex gap-4 py-4 text-sm leading-6 sm:gap-8">
          <dt class="w-1/4 flex-none text-zinc-500"><%= item.title %></dt>
          <dd class="text-zinc-700"><%= render_slot(item) %></dd>
        </div>
      </dl>
    </div>
    """
  end

  @doc """
  Renders a back navigation link.

  ## Examples

      <.back navigate={~p"/posts"}>Back to posts</.back>
  """
  attr(:navigate, :any, required: true)
  slot(:inner_block, required: true)

  def back(assigns) do
    ~H"""
    <div class="mt-16">
      <.link
        navigate={@navigate}
        class="text-sm font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
      >
        <.icon name="hero-arrow-left-solid" class="h-3 w-3" />
        <%= render_slot(@inner_block) %>
      </.link>
    </div>
    """
  end

  @doc """
  Renders a [Hero Icon](https://heroicons.com).

  Hero icons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid an mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from your `assets/vendor/heroicons` directory and bundled
  within your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr(:name, :string, required: true)
  attr(:class, :string, default: nil)

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    # |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    # |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(PeggyWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(PeggyWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  def shake(datetime, seconds) do
    if Timex.diff(Timex.now(), DateTime.from_naive!(datetime, "Etc/UTC"), :seconds) <= seconds do
      "shake"
    else
      ""
    end
  end

  def datalist(list, id) do
    Phoenix.HTML.Tag.content_tag(:datalist, options(list), id: id)
  end

  def datalist_with_ids(list, id, value_key \\ :value, id_key \\ :id) do
    Phoenix.HTML.Tag.content_tag(:datalist, option_with_ids(list, value_key, id_key), id: id)
  end

  def options(list) do
    Enum.map(list, fn el ->
      Phoenix.HTML.Tag.content_tag(:option, "", value: el)
    end)
  end

  def option_with_ids(list, value_key, id_key) do
    Enum.map(list, fn el ->
      Phoenix.HTML.Tag.content_tag(:option, "",
        value: Map.get(el, value_key),
        data_id: Map.get(el, id_key)
      )
    end)
  end

  attr(:id, :any)
  attr(:msg1, :string)
  attr(:msg2, :string, default: nil)
  attr(:confirm, :any)
  # attr(:cancel, :any)

  def delete_confirm_modal(assigns) do
    ~H"""
    <.link id={@id} class="red button" phx-click={show_modal("#{@id}-modal")}>
      <%= gettext("Delete") %>
    </.link>
    <.modal id={"#{@id}-modal"} on_confirm={@confirm}>
      <div class="text-center">
        <div class="text-rose-600 font-bold text-2xl">
          <%= @msg1 %>
        </div>
        <div class="text-red-600 font-bold text-xl"><%= @msg2 %></div>
        <div class="text-amber-600 font-bold text-xl"><%= gettext("Are you sure?") %></div>
      </div>
      <:confirm><%= gettext("OK") %></:confirm>
      <:cancel><%= gettext("CANCEL") %></:cancel>
    </.modal>
    """
  end

  attr(:search_val, :any)
  attr(:placeholder, :any)

  def search_form(assigns) do
    ~H"""
    <div class="flex justify-center mb-2">
      <.form for={%{}} id="search-form" phx-submit="search" autocomplete="off" class="w-full">
        <div class="grid grid-cols-12 gap-1">
          <div class="col-span-11">
            <.input name="search[terms]" type="search" value={@search_val} placeholder={@placeholder} />
          </div>
          <.button class="col-span-1">🔍</.button>
        </div>
      </.form>
    </div>
    """
  end

  attr(:ended, :boolean)

  def infinite_scroll_footer(assigns) do
    ~H"""
    <div :if={@ended} class="mt-2 mb-2 text-center border-y-2 bg-orange-200 border-orange-400 p-2">
      <%= gettext("No More.") %>
    </div>

    <div :if={!@ended} class="mt-2 mb-2 text-center border-y-2 bg-blue-200 border-blue-400 p-2">
      <%= gettext("Loading...") %><.icon name="hero-arrow-path" class="ml-1 h-3 w-3 animate-spin" />
    </div>
    """
  end

  def list_errors_to_string(errors) do
    errors
    |> Enum.map(fn {x, _} ->
      "#{x} #{PeggyWeb.CoreComponents.translate_errors(errors, x)}"
    end)
    |> Enum.join(" ")
  end

  def to_fc_time_format(dt) do
    Timex.format!(Timex.local(dt), "%Y-%m-%d %I:%M:%S%p", :strftime)
  end

  def css_trans(module, obj, obj_name, id, ex_class_1, ex_class_2 \\ "") do
    Phoenix.LiveView.send_update(
      self(),
      module,
      [{:id, id}, {obj_name, obj}, {:ex_class, ex_class_1}]
    )

    Phoenix.LiveView.send_update_after(
      self(),
      module,
      [{:id, id}, {obj_name, obj}, {:ex_class, ex_class_2}],
      1500
    )
  end

  attr :form, :any

  def save_button(assigns) do
    ~H"""
    <button
      type="submit"
      disabled={!@form.source.valid?}
      class={[
        "phx-submit-loading:opacity-75 rounded-lg py-2 px-3 leading-6 border",
        @form.source.valid? && "bg-green-200 hover:bg-green-600 border-green-600",
        !@form.source.valid? &&
          "bg-rose-400 hover:bg-rose-200 border-rose-400 text-white active:text-white/80"
      ]}
    >
      <%= if @form.source.valid?,
        do: gettext("Save"),
        else: gettext("Cannot Save!! Form Invalid!") %>
    </button>
    """
  end

  attr :form, :any
  attr :live_action, :atom
  attr :current_farm, :any
  attr :type, :string

  def form_action_button(assigns) do
    ~H"""
    <.save_button form={@form} />
    <.link :if={@live_action != :new} navigate="" class="orange button">
      <%= gettext("Cancel") %>
    </.link>
    <.link
      :if={@live_action == :edit}
      navigate={"/farms/#{@current_farm.id}/#{@type}/new"}
      class="blue button"
    >
      <%= gettext("New") %>
    </.link>
    <.link class="orange button" navigate={"/farms/#{@current_farm.id}/#{@type}"}>
      <%= gettext("Index") %>
    </.link>
    <%!-- <a onclick="history.back();" class="blue button"><%= gettext("Back") %></a> --%>
    """
  end

  attr :doc_type, :string
  attr :doc_id, :string
  attr :farm, :any

  attr :class, :string,
    default: "text-xs border rounded-full hover:bg-amber-200 px-2 py-1 border-black"

  def print_button(assigns) do
    ~H"""
    <.link
      target="_blank"
      navigate={"/farms/#{@farm.id}/#{@doc_type}/#{@doc_id}/print?pre_print=false"}
      class={@class}
    >
      <%= gettext("Print") %>
    </.link>
    """
  end

  attr :doc_type, :string
  attr :doc_id, :string
  attr :farm, :any

  attr :class, :string,
    default:
      "border border-black hover:bg-blue-200 text-xs text-white rounded-full px-2 py-1 bg-black"

  def pre_print_button(assigns) do
    ~H"""
    <.link
      target="_blank"
      navigate={"/farms/#{@farm.id}/#{@doc_type}/#{@doc_id}/print?pre_print=true"}
      class={@class}
    >
      <%= gettext("Pre Print") %>
    </.link>
    """
  end

  attr(:id, :any)
  attr(:settings, :any)

  def settings(assigns) do
    ~H"""
    <.link id={@id} phx-click={show_modal("#{@id}-modal")} tabindex="-1">
      <.icon name="hero-cog-6-tooth-solid" class="w-5 h-5" />
    </.link>

    <.modal id={"#{@id}-modal"}>
      <div class="flex flex-row flex-wrap gap-5 mb-2 text-black">
        <%= for st <- @settings do %>
          <div class="">
            <label><%= st.display_name %></label>
            <select
              id={"settings_#{st.id}_value"}
              name={"settings[#{st.id}][value]"}
              class="py-1 rounded-md border border-gray-300 bg-white shadow-sm focus:border-zinc-400 focus:ring-0"
            >
              <%= for {v, k} <- st.values do %>
                <%= if st.value == v do %>
                  <option value={v} selected><%= k %></option>
                <% else %>
                  <option value={v}><%= k %></option>
                <% end %>
              <% end %>
            </select>
          </div>
        <% end %>
      </div>
      <:cancel><%= gettext("Close") %></:cancel>
    </.modal>
    """
  end

  attr(:doc_obj, :any)
  attr(:current_farm, :any)
  attr(:klass, :string, default: "")
  attr(:rest, :global)

  def doc_link(assigns) do
    ~H"""
    <.link
      class={["text-blue-600 hover:font-bold", @klass]}
      navigate={"/farms/#{@current_farm.id}/#{@doc_obj.doc_type}/#{@doc_obj.doc_id}/edit"}
      {@rest}
    >
      <%= @doc_obj.doc_no %>
    </.link>
    """
  end

  attr(:type, :any)
  attr(:current_farm, :any)
  attr(:rest, :global)

  def doc_index(assigns) do
    ~H"""

    """
  end

  attr(:doc_obj, :any)
  attr(:current_role, :any)
  attr(:current_farm, :any)
  attr(:klass, :string, default: "")
  attr(:rest, :global)

  def update_seed_link(assigns) do
    ~H"""
    <%= if @current_role == "admin" do %>
      <.link
        class={["text-blue-600 hover:font-bold", @klass]}
        navigate={"/farms/#{@current_farm.id}/seeds/#{@doc_obj.doc_type}/#{@doc_obj.doc_no}/edit"}
        {@rest}
      >
        <%= @doc_obj.doc_no %>
      </.link>
    <% else %>
      <%= @doc_obj.doc_no %>
    <% end %>
    """
  end
end
