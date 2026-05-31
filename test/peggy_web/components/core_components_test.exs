defmodule PeggyWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Peggy.Animals.Animal
  alias PeggyWeb.CoreComponents

  describe "cull_flag/1" do
    test "renders a flag icon with a tooltip for a flagged animal" do
      html =
        render_component(&CoreComponents.cull_flag/1, animal: %Animal{marked_cull: true})

      assert html =~ "hero-flag-micro"
      assert html =~ "Flagged for culling"
    end

    test "renders nothing for an animal that is not flagged" do
      html =
        render_component(&CoreComponents.cull_flag/1, animal: %Animal{marked_cull: false})

      refute html =~ "hero-flag-micro"
    end

    test "renders nothing when the animal is nil" do
      html = render_component(&CoreComponents.cull_flag/1, animal: nil)

      refute html =~ "hero-flag-micro"
    end
  end
end
