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
