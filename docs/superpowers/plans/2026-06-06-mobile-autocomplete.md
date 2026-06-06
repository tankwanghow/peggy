# Mobile Autocomplete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the mobile UI a polished, offline-capable autocomplete on its picker fields (pens, boar) by reusing the existing `<.autocomplete>` component with an upward-opening, touch-sized variant, and polish the list-search bars with a clear button + result count.

**Architecture:** Extend the existing `<.autocomplete>` component + `AutoComplete` JS hook with two opt-in flags — `drop_up` (results open above the input so the on-screen keyboard never covers them) and `touch` (larger tap rows / `input-lg`). Mobile picker fields switch from the current server-side "type the exact code, resolve on phx-change" flow to the component's client-side model: items are preloaded as `%{id, label}` JSON, and selecting one writes the chosen id into a hidden input the form already submits. A small `PeggyWeb.Pickers` module builds the item lists so mobile never imports a `FarmLive` module. List-search bars keep their live card-stream filtering; they only gain a clear (×) button and a result count.

**Tech Stack:** Phoenix 1.8, LiveView 1.1, HEEx, daisyUI 5 / Tailwind v4, vendored `autoComplete.js`, ExUnit + `Phoenix.LiveViewTest`.

**Spec:** `docs/superpowers/specs/2026-06-06-mobile-autocomplete-design.md`

---

## File Structure

**Modified:**
- `lib/peggy_web/components/core_components.ex` — add `drop_up` + `touch` attrs to `autocomplete/1`, emit `data-ac-drop-up` / `data-ac-touch`.
- `assets/js/app.js` — `AutoComplete` hook reads the new data attrs and builds the results-list class accordingly.
- `lib/peggy_web/live/mobile_live/breeding/movement_form.ex` — From/To pen → `<.autocomplete>`; drop server-side `resolve_pen`.
- `lib/peggy_web/live/mobile_live/breeding/{serviceable,lactating,gestating}.ex` — pass pen items into `move_form`; bar polish.
- `lib/peggy_web/live/mobile_live/breeding/gestating.ex` — service boar field → `<.autocomplete>`; drop `resolve_service_boar`.
- `lib/peggy_web/live/mobile_live/animals.ex` — register pen → `<.autocomplete>`; drop `resolve_register_pen`; bar polish.

**Created:**
- `lib/peggy_web/pickers.ex` — `PeggyWeb.Pickers` with `pen_items/1` and `boar_items/1`.
- `test/peggy_web/pickers_test.exs`
- `test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs` — LiveView tests for the migrated picker flows + bar polish.
- `test/peggy_web/components/autocomplete_test.exs` — component render test for the new flags.

---

## Conventions reminder (read once)

- The existing `<.autocomplete>` renders a hidden `<input id="{id}-value" name={name}>` carrying the chosen id and a visible `<input id="{id}-input">` carrying the label. Selecting a result writes the id into the hidden input and dispatches an `input` event, so the enclosing form's `phx-change` fires with the id under `name`. The whole wrapper is `phx-update="ignore"`, so pre-fill via `selected_label` + `value` at render time.
- `AutoComplete` is a **plain** hook registered in `app.js` (`hooks: {...colocatedHooks, AutoComplete}`), **not** a colocated hook — editing `app.js` needs no phoenix-colocated rebuild.
- Run `mix precommit` before finishing (compile `--warnings-as-errors`, `deps.unlock --unused`, `format`, `test`).
- Tests: model setup on the existing `describe` blocks in `test/peggy_web/live/mobile_live_test.exs` — `user_fixture()`, `farm_fixture(owner)`, the `scope`, `house_fixture/2`, `pen_fixture/3`, `animal_fixture/2`, and `log_in_user(conn, owner)` for an authenticated `conn`. Copy the exact setup idiom from that file rather than inventing helpers.

---

## Task 1: Add `drop_up` + `touch` flags to the autocomplete component

**Files:**
- Modify: `lib/peggy_web/components/core_components.ex:352-413`
- Test: `test/peggy_web/components/autocomplete_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/peggy_web/components/autocomplete_test.exs`:

```elixir
defmodule PeggyWeb.AutocompleteTest do
  use PeggyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import PeggyWeb.CoreComponents

  test "renders drop_up and touch data attributes when flags are set" do
    html =
      render_component(&autocomplete/1,
        id: "pen-picker",
        label: "Pen",
        name: "animal[current_pen_id]",
        items: [%{id: 1, label: "EB-12"}],
        drop_up: true,
        touch: true
      )

    assert html =~ ~s(data-ac-drop-up="true")
    assert html =~ ~s(data-ac-touch="true")
    assert html =~ ~s(id="pen-picker-input")
  end

  test "omits the data attributes by default (desktop behavior unchanged)" do
    html =
      render_component(&autocomplete/1,
        id: "pen-picker",
        label: "Pen",
        name: "animal[current_pen_id]",
        items: [%{id: 1, label: "EB-12"}]
      )

    refute html =~ "data-ac-drop-up"
    refute html =~ "data-ac-touch"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/components/autocomplete_test.exs`
Expected: FAIL — the `drop_up`/`touch` attrs don't exist yet (unknown attribute warning / missing data attrs).

- [ ] **Step 3: Add the attrs and emit the data attributes**

In `lib/peggy_web/components/core_components.ex`, after the `:freetext` attr block (ends at line 369), add two attrs before `def autocomplete(assigns) do`:

```elixir
  attr :drop_up, :boolean,
    default: false,
    doc: "Open the results list upward (above the input). Use on mobile so the on-screen keyboard never covers it."

  attr :touch, :boolean,
    default: false,
    doc: "Touch-friendly sizing: input-lg and taller result rows (~44px). Use on the phone UI."
```

Then change the visible `<input>` (lines 388-400) to carry the data attributes and honor `touch` sizing. Replace the existing visible input element with:

```heex
        <input
          type="text"
          id={"#{@id}-input"}
          name={if @freetext, do: @name}
          value={if @freetext, do: @value || "", else: @selected_label || ""}
          placeholder={@placeholder || @label}
          autocomplete="off"
          class={@class || ["w-full input", @touch && "input-lg"]}
          phx-hook="AutoComplete"
          data-ac-items={Jason.encode!(@items)}
          data-ac-empty-text={@empty_text || ""}
          data-ac-freetext={if @freetext, do: "true"}
          data-ac-drop-up={if @drop_up, do: "true"}
          data-ac-touch={if @touch, do: "true"}
        />
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/peggy_web/components/autocomplete_test.exs`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/peggy_web/components/core_components.ex test/peggy_web/components/autocomplete_test.exs
git commit -m "Add drop_up and touch flags to autocomplete component"
```

---

## Task 2: Teach the JS hook to honor `drop_up` / `touch`

**Files:**
- Modify: `assets/js/app.js:98-126` (the `autoComplete` construction inside the `AutoComplete` hook)

No automated test — JS dropdown positioning is visual and not unit-tested, consistent with how the existing hook is treated. Verify by reading the produced class string.

- [ ] **Step 1: Read the new flags at the top of `mounted()`**

In `assets/js/app.js`, inside `AutoComplete.mounted()`, just after the `const freetext = ...` line (line 50), add:

```javascript
    const dropUp = this.el.dataset.acDropUp === "true"
    const touch = this.el.dataset.acTouch === "true"
```

- [ ] **Step 2: Build orientation/size-aware classes**

Still inside `mounted()`, immediately before `this.ac = new autoComplete({` (line 98), add:

```javascript
    const listPos = dropUp ? "bottom-full mb-1" : "top-full mt-1"
    const rowPad = touch ? "px-3 py-3" : "px-3 py-1.5"
```

- [ ] **Step 3: Use the computed classes in the config**

Replace the `resultsList.class` string (line 110-111) with:

```javascript
        class:
          `ac-results absolute ${listPos} left-0 z-50 w-full max-h-60 overflow-y-auto rounded border border-base-300 bg-base-100 shadow-lg text-sm divide-y divide-base-200`,
```

Replace the `resultItem.class` string (line 123) with:

```javascript
        class: `ac-result ${rowPad} cursor-pointer hover:bg-base-200`,
```

(Leave `highlight: true` and `selected: "bg-base-200"` as they are.)

- [ ] **Step 4: Verify the build compiles**

Run: `mix assets.build`
Expected: completes with no esbuild errors.

- [ ] **Step 5: Commit**

```bash
git add assets/js/app.js
git commit -m "AutoComplete hook: honor drop_up and touch data attributes"
```

---

## Task 3: Add `PeggyWeb.Pickers` item-builder helper

**Files:**
- Create: `lib/peggy_web/pickers.ex`
- Test: `test/peggy_web/pickers_test.exs`

This keeps mobile from importing `FarmLive.Breeding.Shared`. It mirrors the existing item shapes (`shared.ex:211` and `shared.ex:226-230`).

- [ ] **Step 1: Write the failing test**

Create `test/peggy_web/pickers_test.exs`:

```elixir
defmodule PeggyWeb.PickersTest do
  use Peggy.DataCase, async: true
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures

  setup do
    owner = user_fixture()
    farm = farm_fixture(owner)
    scope = Peggy.Farms.scope_for(owner, farm)
    %{scope: scope}
  end

  test "pen_items/1 returns %{id, label: HOUSE-PEN} for active pens", %{scope: scope} do
    house = house_fixture(scope, code: "EB")
    pen = pen_fixture(scope, house, code: "12", capacity: 10)

    items = PeggyWeb.Pickers.pen_items(scope)

    assert %{id: pen.id, label: "EB-12"} in items
  end

  test "boar_items/1 returns present boars by ear_tag", %{scope: scope} do
    house = house_fixture(scope, code: "EB")
    pen = pen_fixture(scope, house, code: "12", capacity: 10)
    boar = animal_fixture(scope, ear_tag: "BOAR1", stage: "boar", current_pen_id: pen.id)
    _sow = animal_fixture(scope, ear_tag: "SOW1", stage: "sow", current_pen_id: pen.id)

    items = PeggyWeb.Pickers.boar_items(scope)

    assert items == [%{id: boar.id, label: "BOAR1"}]
  end
end
```

> If `Peggy.Farms.scope_for/2` is not the real constructor, copy the exact scope-building line used in `test/peggy_web/live/mobile_live_test.exs` setup (around line 14).

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/pickers_test.exs`
Expected: FAIL — `PeggyWeb.Pickers` is undefined.

- [ ] **Step 3: Create the module**

Create `lib/peggy_web/pickers.ex`:

```elixir
defmodule PeggyWeb.Pickers do
  @moduledoc """
  Builds `%{id, label}` item lists for the `<.autocomplete>` component.

  UI-neutral so both the desktop and phone UIs can use it without crossing
  LiveView module boundaries.
  """
  alias Peggy.{Animals, Locations}

  @doc "Active pens as autocomplete items labelled `HOUSE-PEN`."
  def pen_items(scope) do
    scope
    |> Locations.list_all_pens()
    |> Enum.map(&%{id: &1.id, label: "#{&1.house.code}-#{&1.code}"})
  end

  @doc "Present boars as autocomplete items labelled by ear tag."
  def boar_items(scope) do
    scope
    |> Animals.list_animals(status: "present")
    |> Enum.filter(&(&1.stage == "boar" and &1.ear_tag != nil))
    |> Enum.map(&%{id: &1.id, label: &1.ear_tag})
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/peggy_web/pickers_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/peggy_web/pickers.ex test/peggy_web/pickers_test.exs
git commit -m "Add PeggyWeb.Pickers item-builder for autocomplete fields"
```

---

## Task 4: Migrate movement From/To pen to autocomplete

The `move_form/1` component and its socket helpers live in
`movement_form.ex` and are shared by `serviceable`, `lactating`, `gestating`.
We drop the server-side `resolve_pen` flow; the hidden inputs now carry
`from_pen_id` / `to_pen_id` directly.

**Files:**
- Modify: `lib/peggy_web/live/mobile_live/breeding/movement_form.ex`
- Modify (callers): `serviceable.ex:421-429`, `lactating.ex:536-544`, `gestating.ex:515-523`
- Test: `test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs` with the movement case (mirror the setup idiom from `mobile_live_test.exs`):

```elixir
defmodule PeggyWeb.MobileLive.AutocompletePickersTest do
  use PeggyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures

  setup %{conn: conn} do
    owner = user_fixture()
    farm = farm_fixture(owner)
    scope = Peggy.Farms.scope_for(owner, farm)
    house = house_fixture(scope, code: "EB")
    from_pen = pen_fixture(scope, house, code: "11", capacity: 50)
    to_pen = pen_fixture(scope, house, code: "12", capacity: 50)
    conn = log_in_user(conn, owner)
    %{conn: conn, farm: farm, scope: scope, from_pen: from_pen, to_pen: to_pen}
  end

  test "moving a batch via the To pen autocomplete records the move", ctx do
    %{conn: conn, farm: farm, scope: scope, from_pen: from_pen, to_pen: to_pen} = ctx

    batch =
      animal_fixture(scope,
        ear_tag: "B-100",
        tracking_type: "batch",
        stage: "weaner",
        quantity: 10,
        current_pen_id: from_pen.id
      )

    {:ok, lv, _html} = live(conn, ~p"/m/#{farm.slug}/animals/#{batch.id}")

    # Open the move sheet (button copy may differ — adjust selector to the
    # actual "Move" action trigger on the detail page).
    lv |> element("button", "Move") |> render_click()

    # The autocomplete hook writes the chosen pen id into the hidden input;
    # in a test we drive phx-change directly with that id.
    render_change(lv, "move_validate", %{
      "movement" => %{"reason" => "pen_transfer", "quantity" => "10", "moved_at" => Date.to_iso8601(Date.utc_today())},
      "from_pen_id" => Integer.to_string(from_pen.id),
      "to_pen_id" => Integer.to_string(to_pen.id)
    })

    render_submit(lv, "move_save", %{
      "movement" => %{"reason" => "pen_transfer", "quantity" => "10", "moved_at" => Date.to_iso8601(Date.utc_today())},
      "from_pen_id" => Integer.to_string(from_pen.id),
      "to_pen_id" => Integer.to_string(to_pen.id)
    })

    reloaded = Peggy.Animals.get_animal!(scope, batch.id)
    assert reloaded.current_pen_id == to_pen.id
  end
end
```

> The detail page / move-trigger selectors must match the real markup. If the move sheet opens from a different LiveView (e.g. `animal_detail`), point `live/2` and the trigger at that page. The assertion (move recorded into `to_pen`) is the contract.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs`
Expected: FAIL — the form still expects `from_code`/`to_code`, so `to_pen_id` is ignored and the move lands in the wrong (or no) pen.

- [ ] **Step 3: Update `init/0` and `open/2` to carry pen items + labels**

In `movement_form.ex`, replace `init/0` (lines 179-191) with:

```elixir
  def init do
    %{
      move_form: nil,
      move_animal: nil,
      move_pen_items: [],
      move_from_label: nil,
      move_from_id: nil,
      move_to_label: nil,
      move_to_id: nil,
      move_error: nil
    }
  end
```

Replace `open/2` (lines 197-220) with:

```elixir
  def open(socket, %Animal{} = animal) do
    today = FarmClock.today(socket.assigns.current_scope)
    from_label = pen_code(animal)

    cs =
      Animals.change_movement(%Movement{
        moved_at: today,
        quantity: animal.quantity,
        reason: default_reason(animal)
      })

    Phoenix.Component.assign(socket,
      move_form: Phoenix.Component.to_form(cs, as: :movement),
      move_animal: animal,
      move_pen_items: PeggyWeb.Pickers.pen_items(socket.assigns.current_scope),
      move_from_label: if(from_label == "", do: nil, else: from_label),
      move_from_id: animal.current_pen_id,
      move_to_label: nil,
      move_to_id: nil,
      move_error: nil
    )
  end
```

- [ ] **Step 4: Replace `validate/2` and `save/2` pen handling**

Replace `validate/2` (lines 232-244) with:

```elixir
  def validate(socket, params) do
    cs =
      Animals.change_movement(%Movement{}, Map.get(params, "movement", %{}))
      |> Map.put(:action, :validate)

    Phoenix.Component.assign(socket,
      move_form: Phoenix.Component.to_form(cs, as: :movement),
      move_from_id: blank_to_nil(params["from_pen_id"]),
      move_to_id: blank_to_nil(params["to_pen_id"]),
      move_error: nil
    )
  end
```

Replace `save/2` (lines 252-280) — only the leading `resolve_pen` lines change; the id now comes from params:

```elixir
  def save(socket, params) do
    movement_params = Map.get(params, "movement", %{})

    attrs =
      movement_params
      |> Map.put("from_pen_id", blank_to_nil(params["from_pen_id"]) || socket.assigns.move_from_id)
      |> Map.put("to_pen_id", blank_to_nil(params["to_pen_id"]) || socket.assigns.move_to_id)

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
```

Delete `resolve_pen/3` (the three clauses, lines 284-316) and the now-unused `pen_state_text/1` (lines 321-323). Add the small helper near the other internals:

```elixir
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
```

Keep `pen_code/1` (it still builds the pre-fill label).

- [ ] **Step 5: Replace the From/To pen inputs in `move_form/1`**

Update the component attrs (lines 29-38): remove `from_code`, `from_state`, `to_code`, `to_state`; add:

```elixir
  attr :pen_items, :list, default: []
  attr :from_label, :string, default: nil
  attr :from_id, :any, default: nil
  attr :to_label, :string, default: nil
  attr :to_id, :any, default: nil
```

Replace the **From pen** `<label>` block (lines 62-90) with:

```heex
      <div
        :if={
          @animal.tracking_type == "batch" and
            Phoenix.HTML.Form.input_value(f, :reason) not in ["placement", "adjustment_gain"]
        }
      >
        <.autocomplete
          id="move-from-pen"
          label={gettext("From pen")}
          name="from_pen_id"
          value={@from_id}
          items={@pen_items}
          selected_label={@from_label}
          placeholder="EB-12"
          drop_up
          touch
          empty_text={gettext("No active pen with that code")}
        />
      </div>
```

Replace the **To pen** `<label>` block (lines 92-123) with:

```heex
      <div
        :if={
          Phoenix.HTML.Form.input_value(f, :reason) in [
            "placement",
            "pen_transfer",
            "adjustment_gain"
          ]
        }
      >
        <.autocomplete
          id="move-to-pen"
          label={gettext("To pen")}
          name="to_pen_id"
          value={@to_id}
          items={@pen_items}
          selected_label={@to_label}
          placeholder="EB-12"
          drop_up
          touch
          empty_text={gettext("No active pen with that code")}
        />
      </div>
```

- [ ] **Step 6: Update the three callers**

In each of `serviceable.ex:421-429`, `lactating.ex:536-544`, `gestating.ex:515-523`, the `<MovementForm.move_form ...>` invocation currently passes `from_code`/`from_state`/`to_code`/`to_state`. Replace those four attrs with:

```heex
              pen_items={@move_pen_items}
              from_label={@move_from_label}
              from_id={@move_from_id}
              to_label={@move_to_label}
              to_id={@move_to_id}
```

(Leave `form`, `animal`, `error`, and the `change`/`submit`/`cancel` event names as they are.)

- [ ] **Step 7: Run the test**

Run: `mix test test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs`
Expected: PASS.

- [ ] **Step 8: Compile clean + commit**

```bash
mix compile --warnings-as-errors
git add lib/peggy_web/live/mobile_live/breeding/movement_form.ex \
        lib/peggy_web/live/mobile_live/breeding/serviceable.ex \
        lib/peggy_web/live/mobile_live/breeding/lactating.ex \
        lib/peggy_web/live/mobile_live/breeding/gestating.ex \
        test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs
git commit -m "Mobile movement: pen pickers use flip-up autocomplete"
```

---

## Task 5: Migrate animals register pen to autocomplete

**Files:**
- Modify: `lib/peggy_web/live/mobile_live/animals.ex` (register form field 390-416; handlers 559-595; reset 940-947; resolve 950-973)
- Test: add a case to `test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs`

- [ ] **Step 1: Write the failing test**

Append to `autocomplete_pickers_test.exs`:

```elixir
  test "registering an animal via the pen autocomplete sets current_pen_id", ctx do
    %{conn: conn, farm: farm, scope: scope, to_pen: pen} = ctx

    {:ok, lv, _html} = live(conn, ~p"/m/#{farm.slug}/animals")

    lv |> element("button", "Register") |> render_click()

    render_submit(lv, "register_save", %{
      "animal" => %{
        "tracking_type" => "individual",
        "ear_tag" => "NEW-1",
        "stage" => "sow"
      },
      "pen_id" => Integer.to_string(pen.id)
    })

    animal = Peggy.Animals.get_animal_by_tag(scope, "NEW-1")
    assert animal.current_pen_id == pen.id
  end
```

> If `get_animal_by_tag/2` does not exist, fetch via `Peggy.Animals.list_animals(scope, status: "present")` and find the `NEW-1` tag. Adjust the "Register" trigger selector to the real button.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs`
Expected: FAIL — register still reads `pen_code`, so `pen_id` is ignored.

- [ ] **Step 3: Add pen items to the register assigns**

In `animals.ex` `handle_event("register_open", ...)` (line 530), include the items and drop the code/state assigns. Change the assign in that handler (lines 547-549 area) to:

```elixir
         register_pen_items: PeggyWeb.Pickers.pen_items(socket.assigns.current_scope),
         register_pen_label: nil,
         register_pen_id: nil,
```

Update the mount defaults (lines 459-461) and the `register_close`/reset assigns (lines 940-947) to the same three keys (`register_pen_items: []` in mount/reset where there's no scope, `register_pen_label: nil`, `register_pen_id: nil`). Remove every `register_pen_code` / `register_pen_state` key.

- [ ] **Step 4: Replace the pen field markup**

Replace the pen `<label>` block (lines 390-416) with:

```heex
              <.autocomplete
                id="register-pen"
                label={gettext("Pen (HOUSE-PEN)")}
                name="pen_id"
                value={@register_pen_id}
                items={@register_pen_items}
                selected_label={@register_pen_label}
                placeholder="EB-12"
                drop_up
                touch
                empty_text={gettext("No active pen with that code")}
              />
```

- [ ] **Step 5: Simplify the handlers**

In `register_validate` (line 559), remove the `|> resolve_register_pen(all["pen_code"])` pipe and instead store the id:

```elixir
  def handle_event("register_validate", %{"animal" => params} = all, socket) do
    cs =
      # ...existing changeset build for params...
      socket_changeset(params)

    {:noreply,
     assign(socket,
       register_form: Phoenix.Component.to_form(cs, as: :animal),
       register_pen_id: blank_to_nil(all["pen_id"])
     )}
  end
```

> Keep the existing changeset-building logic that's already in this handler; only the pen handling changes (drop `resolve_register_pen`, read `all["pen_id"]`). Preserve `register_tracking` handling if present.

In `register_save` (line 585), replace the resolve line and the `Map.put` (lines 587-592) with:

```elixir
    pen_id = blank_to_nil(all["pen_id"])

    attrs =
      params
      |> Map.put("current_pen_id", pen_id)
```

Delete `resolve_register_pen/2` (lines 950-973) and, if `pen_state_text/1` exists in this module solely for the register field, delete it too. Add the `blank_to_nil/1` helper if not already present in this module:

```elixir
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v
```

- [ ] **Step 6: Run the test**

Run: `mix test test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs`
Expected: PASS.

- [ ] **Step 7: Compile clean + commit**

```bash
mix compile --warnings-as-errors
git add lib/peggy_web/live/mobile_live/animals.ex test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs
git commit -m "Mobile register: pen picker uses flip-up autocomplete"
```

---

## Task 6: Migrate gestating service boar to autocomplete

**Files:**
- Modify: `lib/peggy_web/live/mobile_live/breeding/gestating.ex` (boar field 421-443; service_validate 1011-1020; service_save 1025-1053; resets 675-677, 950-952, 1247-1249, 1310-1328)
- Test: add a case to `autocomplete_pickers_test.exs`

- [ ] **Step 1: Write the failing test**

Append to `autocomplete_pickers_test.exs`:

```elixir
  test "natural service via boar autocomplete stores the boar_id", ctx do
    %{conn: conn, farm: farm, scope: scope, from_pen: pen} = ctx

    sow = animal_fixture(scope, ear_tag: "SOW-7", stage: "sow", current_pen_id: pen.id)
    boar = animal_fixture(scope, ear_tag: "BOAR-9", stage: "boar", current_pen_id: pen.id)
    {:ok, _} = Peggy.Breeding.create_service(scope, %{sow_id: sow.id, service_type: "ai", served_at: Date.utc_today()})

    {:ok, lv, _html} = live(conn, ~p"/m/#{farm.slug}/breeding/gestating")

    # Open the re-service sheet for the sow (adjust trigger selector to real markup).
    lv |> element("[phx-value-id='#{sow.id}'] button", "Re-service") |> render_click()

    render_submit(lv, "service_save", %{
      "service_type" => "natural",
      "boar_id" => Integer.to_string(boar.id),
      "served_at" => Date.to_iso8601(Date.utc_today())
    })

    services = Peggy.Breeding.list_services_for_animal(scope, sow.id)
    assert Enum.any?(services, &(&1.boar_id == boar.id))
  end
```

> Selectors for opening the re-service sheet and the breeding context calls (`create_service/2`, `list_services_for_animal/2`) must match the real API — adjust names to the actual functions in `Peggy.Breeding`. The contract is: a natural service is saved with `boar_id` set from the hidden input.

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs`
Expected: FAIL — handler still resolves `boar_tag`; `boar_id` is ignored.

- [ ] **Step 3: Load boar items when the service sheet opens**

Find where the re-service sheet is opened (the handler that sets `service_boar_tag: ""` near line 1310). Add a `service_boar_items` assign there and in mount defaults / resets — set `service_boar_items: PeggyWeb.Pickers.boar_items(socket.assigns.current_scope)` on open, `service_boar_items: []` in mount/reset. Replace every `service_boar_tag: ""` with `service_boar_label: nil` and keep `service_boar_id: nil`.

- [ ] **Step 4: Replace the boar field markup**

Replace the boar `<label>` block (lines 421-443) with:

```heex
              <div :if={@service_type == "natural"}>
                <.autocomplete
                  id="service-boar"
                  label={gettext("Boar ear tag")}
                  name="boar_id"
                  value={@service_boar_id}
                  items={@service_boar_items}
                  selected_label={@service_boar_label}
                  drop_up
                  touch
                  empty_text={gettext("No boar with that tag")}
                />
              </div>
```

- [ ] **Step 5: Simplify the handlers**

In `service_validate` (line 1011), remove `|> resolve_service_boar(params["boar_tag"])` and instead `assign(socket, service_boar_id: blank_to_nil(params["boar_id"]))`.

In `service_save` (line 1025): remove the `resolve_service_boar` pipe (line 1030); change the natural-service guard (line 1040) to test `is_nil(blank_to_nil(params["boar_id"]))`; and change the `maybe_put("boar_id", socket.assigns.service_boar_id)` (line 1053) to `maybe_put("boar_id", blank_to_nil(params["boar_id"]))`.

Delete `resolve_service_boar/2` and `service_boar_state_text/1`. Add `blank_to_nil/1` to this module if not present.

- [ ] **Step 6: Run the test**

Run: `mix test test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs`
Expected: PASS.

- [ ] **Step 7: Compile clean + commit**

```bash
mix compile --warnings-as-errors
git add lib/peggy_web/live/mobile_live/breeding/gestating.ex test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs
git commit -m "Mobile gestating: boar picker uses flip-up autocomplete"
```

---

## Task 7: List-search bar polish (clear button + result count)

Applies to the sticky search bars in `animals`, `serviceable`, `lactating`,
`gestating`. Each keeps live filtering; we add a clear (×) button and a count.

**Files:**
- Modify: `animals.ex` (bar ~line 23), `serviceable.ex` (~24), `lactating.ex` (~28), `gestating.ex` (~29)
- Test: add a case to `autocomplete_pickers_test.exs`

- [ ] **Step 1: Write the failing test (animals bar)**

Append to `autocomplete_pickers_test.exs`:

```elixir
  test "animals search bar clear button resets the filter", ctx do
    %{conn: conn, farm: farm, scope: scope, from_pen: pen} = ctx
    _a = animal_fixture(scope, ear_tag: "FINDME", stage: "sow", current_pen_id: pen.id)
    _b = animal_fixture(scope, ear_tag: "OTHER", stage: "sow", current_pen_id: pen.id)

    {:ok, lv, _html} = live(conn, ~p"/m/#{farm.slug}/animals")

    html = render_change(lv, "search", %{"tag_search" => "FINDME"})
    assert html =~ "FINDME"
    refute html =~ "OTHER"

    cleared = lv |> element("button[phx-click='clear_search']") |> render_click()
    assert cleared =~ "FINDME"
    assert cleared =~ "OTHER"
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs`
Expected: FAIL — no `clear_search` button/handler.

- [ ] **Step 3: Add the clear button + count to each bar**

In each of the four LiveViews, inside the search `<form phx-change="search" ...>` block, after the search `<input>`, add a clear button shown only when there's a query (use the view's existing filter assign — `@filters.tag_search`):

```heex
            <button
              :if={@filters.tag_search not in [nil, ""]}
              type="button"
              phx-click="clear_search"
              aria-label={gettext("Clear search")}
              class="btn btn-ghost btn-circle btn-sm"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
```

And under the bar, a count line (use the view's existing result collection size — replace `@result_count` with whatever count the view already tracks, e.g. `@total` / `length(@entries)`):

```heex
          <p class="px-4 pt-1 text-xs text-base-content/50">
            {gettext("%{n} results", n: @result_count)}
          </p>
```

> If the view doesn't already expose a count, assign one alongside the stream in its search/load path (e.g. `assign(socket, :result_count, length(rows))` where `rows` is what's streamed). Reuse the count it already computes rather than re-querying.

- [ ] **Step 4: Add the `clear_search` handler to each view**

Add to each of the four LiveViews (resetting the same way the empty `search` does):

```elixir
  def handle_event("clear_search", _params, socket) do
    {:noreply, handle_event_search(socket, "")}
  end
```

> Implement by reusing the view's existing search path: set the filter's `tag_search` to `""` and re-run the same load/stream the `"search"` handler uses. If `"search"` is a single function clause, extract the body into a private helper and call it from both. Do not duplicate the query.

- [ ] **Step 5: Run the test**

Run: `mix test test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs`
Expected: PASS.

- [ ] **Step 6: Compile clean + commit**

```bash
mix compile --warnings-as-errors
git add lib/peggy_web/live/mobile_live/animals.ex \
        lib/peggy_web/live/mobile_live/breeding/serviceable.ex \
        lib/peggy_web/live/mobile_live/breeding/lactating.ex \
        lib/peggy_web/live/mobile_live/breeding/gestating.ex \
        test/peggy_web/live/mobile_live/autocomplete_pickers_test.exs
git commit -m "Mobile list-search bars: clear button and result count"
```

---

## Task 8: Full verification

- [ ] **Step 1: Run the whole suite + precommit**

Run: `mix precommit`
Expected: compiles with no warnings, `deps.unlock --unused` clean, formatted, all tests pass.

- [ ] **Step 2: Manual smoke (visual / offline)**

Run `iex -S mix phx.server`, open the phone UI (`/m/:slug/...`), and confirm on a narrow viewport with the keyboard up:
- pen/boar dropdowns open **upward**, rows are comfortably tappable;
- picking a result fills the field and the form saves the right id;
- list-search bars filter live, the × clears, and the count updates.

- [ ] **Step 3: Final commit if anything was tidied**

```bash
git add -A
git commit -m "Mobile autocomplete: formatting and verification fixups"
```

---

## Self-review notes

- **Spec coverage:** flip-up + touch component (Tasks 1–2) ✓; picker fields pen/boar (Tasks 4–6) ✓; client-side/offline model via hidden id ✓; shared item builder, no FarmLive import (Task 3) ✓; list bars stay live-filter + polish (Task 7) ✓; desktop unchanged (flags default false) ✓; tests at the LiveView seam, positioning left visual (each task) ✓.
- **Assumptions to confirm during execution (flagged inline):** exact scope constructor (`Peggy.Farms.scope_for/2`), the move/register/re-service trigger selectors, `Peggy.Breeding` service function names, and whether each list view already tracks a result count. These are existing-API lookups, not design gaps.
