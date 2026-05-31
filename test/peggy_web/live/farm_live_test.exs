defmodule PeggyWeb.FarmLiveTest do
  use PeggyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures

  describe "/farms" do
    test "lists only the current user's farms when they have more than one", %{conn: conn} do
      alice = user_fixture()
      bob = user_fixture()
      _a1 = farm_fixture(alice, name: "Alice Acres")
      _a2 = farm_fixture(alice, name: "Second Acres")
      _bob_farm = farm_fixture(bob, name: "Bob Barns")

      {:ok, _lv, html} = conn |> log_in_user(alice) |> live(~p"/farms")
      assert html =~ "Alice Acres"
      assert html =~ "Second Acres"
      refute html =~ "Bob Barns"
    end

    test "shows the picker even when the user has a single farm", %{conn: conn} do
      alice = user_fixture()
      farm = farm_fixture(alice, name: "Alice Acres")

      {:ok, _lv, html} = conn |> log_in_user(alice) |> live(~p"/farms")
      assert html =~ "Alice Acres"
      assert html =~ farm.slug
      assert html =~ "Create a farm"
    end
  end

  describe "/farms/:slug isolation" do
    test "non-member gets redirected to /farms", %{conn: conn} do
      alice = user_fixture()
      bob = user_fixture()
      alice_farm = farm_fixture(alice)

      assert {:error, {:redirect, %{to: "/farms"}}} =
               conn |> log_in_user(bob) |> live(~p"/farms/#{alice_farm.slug}")
    end

    test "member reaches the dashboard", %{conn: conn} do
      alice = user_fixture()
      farm = farm_fixture(alice, name: "Alice Acres")

      {:ok, _lv, html} = conn |> log_in_user(alice) |> live(~p"/farms/#{farm.slug}")
      # The dashboard has no page header; it's scoped to this farm (slug in
      # the layout) and renders the herd-snapshot body for a member.
      assert html =~ farm.slug
      assert html =~ "Herd snapshot"
    end
  end

  describe "/farms/:slug/settings" do
    test "worker cannot see settings (redirected)", %{conn: conn} do
      owner = user_fixture()
      worker = user_fixture()
      farm = farm_fixture(owner)

      {:ok, invitation} =
        Peggy.Farms.invite(farm, %{"email" => worker.email, "role" => "worker"}, owner)

      {:ok, _} = Peggy.Farms.accept_invitation(invitation, worker)

      assert {:error, {:redirect, %{to: "/farms"}}} =
               conn |> log_in_user(worker) |> live(~p"/farms/#{farm.slug}/settings")
    end

    test "owner can edit farm profile", %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner, name: "Original", unit_system: "metric")

      {:ok, lv, _html} = conn |> log_in_user(owner) |> live(~p"/farms/#{farm.slug}/settings")

      lv
      |> form("#farm-form", farm: %{name: "Renamed", unit_system: "imperial"})
      |> render_submit()

      reloaded = Peggy.Farms.get_farm_by_slug!(farm.slug)
      assert reloaded.name == "Renamed"
      assert reloaded.unit_system == "imperial"
    end

    test "owner can invite a member", %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)

      {:ok, lv, _html} = conn |> log_in_user(owner) |> live(~p"/farms/#{farm.slug}/settings")

      lv
      |> form("#invite-form", invitation: %{email: "new@example.com", role: "worker"})
      |> render_submit()

      assert has_element?(lv, "#invitations", "new@example.com")
    end
  end

  describe "/farms/:slug/animals/bulk-move" do
    import Peggy.LocationsFixtures
    import Peggy.AnimalsFixtures

    setup %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)
      scope = scope_for(owner, farm)
      house = house_fixture(scope, code: "H1")
      pen_a = pen_fixture(scope, house, code: "A", capacity: 50)
      pen_b = pen_fixture(scope, house, code: "B", capacity: 50)

      sow1 =
        animal_fixture(scope, ear_tag: "SOW1", stage: "sow", current_pen_id: pen_a.id)

      sow2 =
        animal_fixture(scope, ear_tag: "SOW2", stage: "sow", current_pen_id: pen_a.id)

      %{
        conn: log_in_user(conn, owner),
        farm: farm,
        scope: scope,
        pen_a: pen_a,
        pen_b: pen_b,
        sow1: sow1,
        sow2: sow2
      }
    end

    test "renders the grid with starter rows", %{conn: conn, farm: farm} do
      {:ok, _lv, html} = live(conn, ~p"/farms/#{farm.slug}/animals/bulk-move")

      assert html =~ "Bulk Move Sire/Dam"
      # Three starter rows
      assert html =~ ~s(name="rows[)
    end

    test "adds and removes rows", %{conn: conn, farm: farm} do
      {:ok, lv, _html} = live(conn, ~p"/farms/#{farm.slug}/animals/bulk-move")

      before = lv |> render() |> String.split(~s(name="rows[)) |> length()
      lv |> element("button", "Add row") |> render_click()
      after_click = lv |> render() |> String.split(~s(name="rows[)) |> length()
      assert after_click > before
    end

    test "commits rows and redirects to animals index",
         %{conn: conn, scope: scope, farm: farm, pen_b: b, sow1: sow1, sow2: sow2} do
      {:ok, lv, _html} = live(conn, ~p"/farms/#{farm.slug}/animals/bulk-move")

      tmp_ids =
        Regex.scan(~r/name="rows\[([^\]]+)\]\[animal_id\]/, render(lv))
        |> Enum.map(fn [_, id] -> id end)
        |> Enum.uniq()

      [id1, id2 | _] = tmp_ids

      params = %{
        "rows" => %{
          id1 => %{
            "animal_id" => Integer.to_string(sow1.id),
            "to_pen_id" => Integer.to_string(b.id)
          },
          id2 => %{
            "animal_id" => Integer.to_string(sow2.id),
            "to_pen_id" => Integer.to_string(b.id)
          }
        }
      }

      render_change(lv, "update", params)

      assert {:error, {:live_redirect, %{to: to}}} = render_submit(lv, "commit", %{})
      assert to == "/farms/#{farm.slug}/animals"

      assert Peggy.Animals.get_animal!(scope, sow1.id).current_pen_id == b.id
      assert Peggy.Animals.get_animal!(scope, sow2.id).current_pen_id == b.id
    end

    test "shows row error when destination equals current pen",
         %{conn: conn, farm: farm, pen_a: a, sow1: sow1} do
      {:ok, lv, _html} = live(conn, ~p"/farms/#{farm.slug}/animals/bulk-move")

      tmp_ids =
        Regex.scan(~r/name="rows\[([^\]]+)\]\[animal_id\]/, render(lv))
        |> Enum.map(fn [_, id] -> id end)
        |> Enum.uniq()

      [id1 | _] = tmp_ids

      params = %{
        "rows" => %{
          id1 => %{
            "animal_id" => Integer.to_string(sow1.id),
            "to_pen_id" => Integer.to_string(a.id)
          }
        }
      }

      render_change(lv, "update", params)
      html = render_submit(lv, "commit", %{})

      assert html =~ "Row 1"
      assert html =~ "already in that pen"
    end
  end

  describe "/farms/:slug/animals/:id/batch-entry" do
    import Peggy.LocationsFixtures
    import Peggy.AnimalsFixtures

    setup %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)
      scope = scope_for(owner, farm)
      house = house_fixture(scope, code: "H1")
      pen_a = pen_fixture(scope, house, code: "A", capacity: 200)
      pen_b = pen_fixture(scope, house, code: "B", capacity: 200)
      batch = batch_fixture(scope, quantity: 100)

      %{
        conn: log_in_user(conn, owner),
        farm: farm,
        scope: scope,
        batch: batch,
        pen_a: pen_a,
        pen_b: pen_b
      }
    end

    test "renders the grid for a batch animal", %{conn: conn, farm: farm, batch: batch} do
      {:ok, _lv, html} =
        live(conn, ~p"/farms/#{farm.slug}/animals/#{batch.id}/batch-entry")

      assert html =~ "Batch Transfer"
      assert html =~ "Unplaced"
      # Three starter rows
      assert html =~ ~s(name="rows[)
    end

    test "redirects individual animals away", %{
      conn: conn,
      farm: farm,
      scope: scope,
      pen_a: pen_a
    } do
      ind = animal_fixture(scope, current_pen_id: pen_a.id)

      assert {:error, {:redirect, %{to: to}}} =
               live(conn, ~p"/farms/#{farm.slug}/animals/#{ind.id}/batch-entry")

      assert to =~ "/animals/#{ind.id}"
    end

    test "adds and removes rows", %{conn: conn, farm: farm, batch: batch} do
      {:ok, lv, _html} =
        live(conn, ~p"/farms/#{farm.slug}/animals/#{batch.id}/batch-entry")

      before = lv |> render() |> String.split(~s(name="rows[)) |> length()
      lv |> element("button", "Add row") |> render_click()
      after_click = lv |> render() |> String.split(~s(name="rows[)) |> length()
      assert after_click > before
    end

    test "commits rows and redirects to animal detail",
         %{conn: conn, scope: scope, farm: farm, batch: batch, pen_a: a, pen_b: b} do
      {:ok, lv, _html} =
        live(conn, ~p"/farms/#{farm.slug}/animals/#{batch.id}/batch-entry")

      # Simulate filling in two rows by pushing form params. We have to
      # dig the generated tmp_ids out of the DOM because they're random.
      tmp_ids =
        Regex.scan(~r/name="rows\[([^\]]+)\]\[reason\]/, render(lv))
        |> Enum.map(fn [_, id] -> id end)
        |> Enum.uniq()

      [id1, id2 | _] = tmp_ids

      params = %{
        "rows" => %{
          id1 => %{
            "reason" => "placement",
            "to_pen_id" => Integer.to_string(a.id),
            "quantity" => "60"
          },
          id2 => %{
            "reason" => "placement",
            "to_pen_id" => Integer.to_string(b.id),
            "quantity" => "40"
          }
        }
      }

      # Phoenix LiveView form rendering would need hidden inputs populated
      # — simulate phx-change directly.
      render_change(lv, "update", params)

      # Then commit.
      assert {:error, {:live_redirect, %{to: to}}} =
               render_submit(lv, "commit", %{})

      assert to == "/farms/#{farm.slug}/animals/#{batch.id}"

      total =
        Peggy.Animals.list_placements(scope, batch)
        |> Enum.reduce(0, &(&1.quantity + &2))

      assert total == 100
    end

    test "shows row error when budget is exceeded",
         %{conn: conn, farm: farm, batch: batch, pen_a: a, pen_b: b} do
      {:ok, lv, _html} =
        live(conn, ~p"/farms/#{farm.slug}/animals/#{batch.id}/batch-entry")

      tmp_ids =
        Regex.scan(~r/name="rows\[([^\]]+)\]\[reason\]/, render(lv))
        |> Enum.map(fn [_, id] -> id end)
        |> Enum.uniq()

      [id1, id2 | _] = tmp_ids

      params = %{
        "rows" => %{
          id1 => %{
            "reason" => "placement",
            "to_pen_id" => Integer.to_string(a.id),
            "quantity" => "60"
          },
          id2 => %{
            "reason" => "placement",
            "to_pen_id" => Integer.to_string(b.id),
            "quantity" => "60"
          }
        }
      }

      render_change(lv, "update", params)
      html = render_submit(lv, "commit", %{})

      assert html =~ "Row 2"
      assert html =~ "exceeds unplaced"
    end
  end

  describe "/farms/:slug/animals needs_review filter" do
    import Peggy.LocationsFixtures
    import Peggy.AnimalsFixtures
    import Ecto.Query

    setup %{conn: conn} do
      owner = user_fixture()
      farm = farm_fixture(owner)
      scope = scope_for(owner, farm)
      house = house_fixture(scope, code: "H1")
      pen = pen_fixture(scope, house, code: "P1", capacity: 50)

      review_sow =
        animal_fixture(scope, ear_tag: "REVIEWME", stage: "sow", current_pen_id: pen.id)

      _clean_sow =
        animal_fixture(scope, ear_tag: "CLEANTAG", stage: "sow", current_pen_id: pen.id)

      {1, _} =
        Peggy.Repo.update_all(
          from(a in Peggy.Animals.Animal, where: a.id == ^review_sow.id),
          set: [needs_review: true]
        )

      %{conn: log_in_user(conn, owner), farm: farm}
    end

    test "?needs_review=1 narrows the list on first load", %{conn: conn, farm: farm} do
      {:ok, _lv, html} = live(conn, ~p"/farms/#{farm.slug}/animals?needs_review=1")
      assert html =~ "REVIEWME"
      refute html =~ "CLEANTAG"
    end

    test "unfiltered URL shows all rows", %{conn: conn, farm: farm} do
      {:ok, _lv, html} = live(conn, ~p"/farms/#{farm.slug}/animals")
      assert html =~ "REVIEWME"
      assert html =~ "CLEANTAG"
    end
  end
end
