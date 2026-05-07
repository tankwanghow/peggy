defmodule PeggyWeb.MobileLive.Breeding.MovementForm do
  @moduledoc """
  Shared movement form for mobile breeding action sheets.

  Hosts the full-width `<.move_form>` HEEx component plus socket-state
  helpers (`init/0`, `open/2`, `validate/2`, `save/3`). Each calling
  LiveView wires its own event names but delegates the assign updates
  here so the form state is identical across Serviceable, Gestating,
  and Lactating tabs.
  """
  use PeggyWeb, :html

  alias Peggy.{Animals, FarmClock, Locations}
  alias Peggy.Animals.{Animal, Movement}

  # ── Component ──────────────────────────────────────────────────────

  @doc """
  Movement form rendered inside an action sheet body.

  The wrapping action-sheet container, header, and back-button are the
  caller's responsibility — this just renders the form fields and the
  cancel/save buttons. Caller wires three event names:

    * `change` — on phx-change (default `move_validate`)
    * `submit` — on phx-submit (default `move_save`)
    * `cancel` — on the Cancel button click (default `action_back`)
  """
  attr :form, :any, required: true
  attr :animal, :any, required: true
  attr :from_code, :string, required: true
  attr :from_state, :atom, required: true
  attr :to_code, :string, required: true
  attr :to_state, :atom, required: true
  attr :error, :any, default: nil
  attr :change, :string, default: "move_validate"
  attr :submit, :string, default: "move_save"
  attr :cancel, :string, default: "action_back"

  def move_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={@form}
      phx-change={@change}
      phx-submit={@submit}
      class="px-4 py-3 space-y-4"
    >
      <label class="block">
        <span class="text-xs uppercase text-base-content/60">{gettext("Reason")}</span>
        <select name="movement[reason]" class="select select-bordered select-lg w-full mt-1">
          <option
            :for={{label, value} <- reason_options(@animal)}
            value={value}
            selected={Phoenix.HTML.Form.input_value(f, :reason) == value}
          >
            {label}
          </option>
        </select>
      </label>

      <label
        :if={
          @animal.tracking_type == "batch" and
            Phoenix.HTML.Form.input_value(f, :reason) not in ["placement", "adjustment_gain"]
        }
        class="block"
      >
        <span class="text-xs uppercase text-base-content/60">{gettext("From pen")}</span>
        <input
          type="text"
          name="from_code"
          value={@from_code}
          phx-debounce="300"
          placeholder="EB-12"
          class={[
            "input input-bordered input-lg w-full mt-1 font-mono",
            @from_state == :resolved && "border-success focus:border-success",
            @from_state == :not_found && "border-error focus:border-error"
          ]}
        />
        <span class={[
          "text-xs mt-1 block",
          @from_state == :resolved && "text-success",
          @from_state == :not_found && "text-error",
          @from_state == :empty && "text-base-content/50"
        ]}>
          {pen_state_text(@from_state)}
        </span>
      </label>

      <label
        :if={
          Phoenix.HTML.Form.input_value(f, :reason) in [
            "placement",
            "pen_transfer",
            "adjustment_gain"
          ]
        }
        class="block"
      >
        <span class="text-xs uppercase text-base-content/60">{gettext("To pen")}</span>
        <input
          type="text"
          name="to_code"
          value={@to_code}
          phx-debounce="300"
          placeholder="EB-12"
          class={[
            "input input-bordered input-lg w-full mt-1 font-mono",
            @to_state == :resolved && "border-success focus:border-success",
            @to_state == :not_found && "border-error focus:border-error"
          ]}
        />
        <span class={[
          "text-xs mt-1 block",
          @to_state == :resolved && "text-success",
          @to_state == :not_found && "text-error",
          @to_state == :empty && "text-base-content/50"
        ]}>
          {pen_state_text(@to_state)}
        </span>
      </label>

      <div class="grid grid-cols-2 gap-3">
        <label :if={@animal.tracking_type == "batch"} class="block">
          <span class="text-xs uppercase text-base-content/60">{gettext("Quantity")}</span>
          <input
            type="number"
            name="movement[quantity]"
            value={Phoenix.HTML.Form.input_value(f, :quantity)}
            min="1"
            inputmode="numeric"
            class="input input-bordered input-lg w-full mt-1 font-mono"
          />
        </label>
        <label class="block">
          <span class="text-xs uppercase text-base-content/60">{gettext("When")}</span>
          <input
            type="date"
            name="movement[moved_at]"
            value={Phoenix.HTML.Form.input_value(f, :moved_at)}
            class="input input-bordered input-lg w-full mt-1"
          />
        </label>
      </div>

      <label class="block">
        <span class="text-xs uppercase text-base-content/60">{gettext("Notes")}</span>
        <input
          type="text"
          name="movement[notes]"
          value={Phoenix.HTML.Form.input_value(f, :notes)}
          class="input input-bordered input-lg w-full mt-1"
        />
      </label>

      <p :if={@error} class="text-sm text-error">{@error}</p>

      <div class="grid grid-cols-2 gap-3 pt-2">
        <button type="button" phx-click={@cancel} class="btn btn-lg btn-ghost">
          {gettext("Cancel")}
        </button>
        <button
          type="submit"
          phx-disable-with={gettext("Recording…")}
          class="btn btn-lg btn-primary"
        >
          {gettext("Record")}
        </button>
      </div>
    </.form>
    """
  end

  # ── Socket-state helpers ───────────────────────────────────────────

  @doc "Initial assigns; merge into mount/3 so the component renders cleanly even when closed."
  def init do
    %{
      move_form: nil,
      move_animal: nil,
      move_from_code: "",
      move_from_state: :empty,
      move_from_id: nil,
      move_to_code: "",
      move_to_state: :empty,
      move_to_id: nil,
      move_error: nil
    }
  end

  @doc """
  Opens the form for `animal` (must be preloaded with `current_pen: :house`).
  Pre-fills the From pen with the animal's current pen.
  """
  def open(socket, %Animal{} = animal) do
    today = FarmClock.today(socket.assigns.current_scope)
    from_code = pen_code(animal)
    from_state = if from_code == "", do: :empty, else: :resolved

    cs =
      Animals.change_movement(%Movement{
        moved_at: today,
        quantity: animal.quantity,
        reason: default_reason(animal)
      })

    Phoenix.Component.assign(socket,
      move_form: Phoenix.Component.to_form(cs, as: :movement),
      move_animal: animal,
      move_from_code: from_code,
      move_from_state: from_state,
      move_from_id: animal.current_pen_id,
      move_to_code: "",
      move_to_state: :empty,
      move_to_id: nil,
      move_error: nil
    )
  end

  @doc "Resets form state — call after save success or when leaving the move sheet."
  def reset(socket) do
    Phoenix.Component.assign(socket, init())
  end

  @doc """
  Re-validates the changeset and re-resolves the pen codes.

  `params` is the full phx-change payload (`%{"movement" => ..., "from_code" => ..., "to_code" => ...}`).
  """
  def validate(socket, params) do
    cs =
      Animals.change_movement(%Movement{}, Map.get(params, "movement", %{}))
      |> Map.put(:action, :validate)

    socket
    |> Phoenix.Component.assign(
      move_form: Phoenix.Component.to_form(cs, as: :movement),
      move_error: nil
    )
    |> resolve_pen(:from, params["from_code"])
    |> resolve_pen(:to, params["to_code"])
  end

  @doc """
  Submits the movement.

  Returns either `{:ok, socket}` (cleared form) or `{:error, socket}`
  (form still open with error message). Caller handles flash + reload.
  """
  def save(socket, params) do
    socket =
      socket
      |> resolve_pen(:from, params["from_code"])
      |> resolve_pen(:to, params["to_code"])

    movement_params = Map.get(params, "movement", %{})

    attrs =
      movement_params
      |> Map.put("from_pen_id", socket.assigns.move_from_id)
      |> Map.put("to_pen_id", socket.assigns.move_to_id)

    animal = socket.assigns.move_animal

    case Animals.record_movement(socket.assigns.current_scope, animal, attrs) do
      {:ok, _} ->
        {:ok, reset(socket)}

      {:error, %Ecto.Changeset{} = cs} ->
        {:error,
         Phoenix.Component.assign(socket,
           move_form: Phoenix.Component.to_form(cs, as: :movement)
         )}

      {:error, reason} ->
        {:error, Phoenix.Component.assign(socket, move_error: humanize_error(reason))}
    end
  end

  # ── Internals ──────────────────────────────────────────────────────

  defp resolve_pen(socket, side, nil), do: resolve_pen(socket, side, "")

  defp resolve_pen(socket, side, code) when is_binary(code) do
    code = String.trim(code)

    {state, pen_id} =
      cond do
        code == "" ->
          {:empty, nil}

        true ->
          case Locations.find_pen_by_code(socket.assigns.current_scope, code) do
            nil -> {:not_found, nil}
            pen -> {:resolved, pen.id}
          end
      end

    case side do
      :from ->
        Phoenix.Component.assign(socket,
          move_from_code: code,
          move_from_state: state,
          move_from_id: pen_id
        )

      :to ->
        Phoenix.Component.assign(socket,
          move_to_code: code,
          move_to_state: state,
          move_to_id: pen_id
        )
    end
  end

  defp pen_code(%{current_pen: %{code: code, house: %{code: hcode}}}), do: "#{hcode}-#{code}"
  defp pen_code(_), do: ""

  defp pen_state_text(:resolved), do: gettext("✓")
  defp pen_state_text(:not_found), do: gettext("⚠ No active pen with that code")
  defp pen_state_text(_), do: gettext("Type house-pen, e.g. EB-12")

  defp default_reason(_), do: "pen_transfer"

  defp reason_options(%Animal{tracking_type: "individual"}) do
    Movement.reasons()
    |> Enum.reject(&(&1 in ["adjustment_loss", "adjustment_gain", "wean"]))
    |> Enum.map(&{humanize_reason(&1), &1})
  end

  defp reason_options(_) do
    Movement.reasons()
    |> Enum.reject(&(&1 == "wean"))
    |> Enum.map(&{humanize_reason(&1), &1})
  end

  defp humanize_reason(r), do: r |> String.replace("_", " ") |> String.capitalize()

  defp humanize_error(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp humanize_error(reason), do: inspect(reason)
end
