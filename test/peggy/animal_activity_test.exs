defmodule Peggy.AnimalActivityTest do
  use Peggy.DataCase, async: true

  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures
  import Peggy.BreedingFixtures

  alias Peggy.{Animals, AnimalActivity, Breeding}

  setup do
    user = user_fixture()
    farm = farm_fixture(user)
    scope = scope_for(user, farm)
    house = house_fixture(scope, code: "H1", purpose: "farrowing")
    pen = pen_fixture(scope, house, code: "F1", capacity: 20)
    # Create the sow without `current_pen_id` so the test fixtures don't
    # auto-create a placement movement at moved_at=today, which would
    # otherwise dominate the event-date ordering used by latest_event/2.
    sow = animal_fixture(scope, ear_tag: "S1", stage: "sow")
    %{scope: scope, pen: pen, sow: sow}
  end

  describe "latest_event/2" do
    test "returns nil when the animal has no activity", %{scope: scope} do
      # Animals created without `current_pen_id` skip the auto-placement
      # movement, so there's truly no activity for them.
      bare = animal_fixture(scope, ear_tag: "BARE", stage: "sow")
      assert AnimalActivity.latest_event(scope, bare) == nil
    end

    test "returns the most recently inserted event tagged by kind", %{
      scope: scope,
      sow: sow,
      pen: pen
    } do
      _service = service_fixture(scope, sow, served_at: ~D[2026-01-01], service_type: "ai")

      {:ok, _m} =
        Animals.record_movement(scope, sow, %{
          "reason" => "pen_transfer",
          "moved_at" => "2026-01-15",
          "to_pen_id" => pen.id
        })

      # Bump the movement's inserted_at by a second so it strictly post-
      # dates the service. `:utc_datetime` is second-precision, and tests
      # run fast enough that both rows land in the same wall-clock second.
      Peggy.Repo.update_all(
        Ecto.Query.from(m in Peggy.Animals.Movement,
          where: m.animal_id == ^sow.id and m.reason == "pen_transfer"
        ),
        set: [inserted_at: DateTime.add(DateTime.utc_now(:second), 5, :second)]
      )

      assert {:movement, %Peggy.Animals.Movement{}} = AnimalActivity.latest_event(scope, sow)
    end

    test "skips wean movements (cascade-managed by delete_weaning)", %{scope: scope, sow: sow} do
      farrowing =
        farrowing_fixture(scope, sow,
          farrowed_at: ~D[2026-04-25],
          born_alive: 10,
          service_type: "ai"
        )

      {:ok, _w, _batch} =
        Breeding.record_weaning(scope, farrowing, %{
          weaned_at: ~D[2026-05-15],
          weaned_count: 9,
          batch_tag: "B1"
        })

      # The weaning insert created a `wean` movement on the batch, but
      # latest_event/2 for the *sow* should return the weaning, not the
      # batch's wean movement (we look only at this animal's rows).
      assert {:weaning, %Peggy.Breeding.Weaning{}} = AnimalActivity.latest_event(scope, sow)
    end
  end

  describe "undo_latest/2" do
    test "returns :no_events when nothing exists", %{scope: scope} do
      bare = animal_fixture(scope, ear_tag: "BARE2", stage: "sow")
      assert AnimalActivity.undo_latest(scope, bare) == {:error, :no_events}
    end

    test "undoes a service (sow goes served → open)", %{scope: scope, sow: sow} do
      _service = service_fixture(scope, sow, served_at: ~D[2026-01-01], service_type: "ai")
      sow = Animals.get_animal!(scope, sow.id)
      assert sow.status == "served"

      assert {:ok, :service, _s} = AnimalActivity.undo_latest(scope, sow)

      sow = Animals.get_animal!(scope, sow.id)
      assert sow.status == "open"
    end

    test "undoes a farrowing (sow goes lactating → served, service reopens)", %{
      scope: scope,
      sow: sow
    } do
      farrowing =
        farrowing_fixture(scope, sow,
          farrowed_at: ~D[2026-04-25],
          born_alive: 10,
          service_type: "ai"
        )

      sow = Animals.get_animal!(scope, sow.id)
      assert sow.status == "lactating"

      assert {:ok, :farrowing, _f} = AnimalActivity.undo_latest(scope, sow)

      sow = Animals.get_animal!(scope, sow.id)
      assert sow.status == "served"

      service = Peggy.Repo.get!(Peggy.Breeding.Service, farrowing.service_id)
      assert is_nil(service.result)
      assert is_nil(service.result_at)
    end

    test "undoes a weaning (sow goes dry → lactating, batch quantity decremented)", %{
      scope: scope,
      sow: sow
    } do
      farrowing =
        farrowing_fixture(scope, sow,
          farrowed_at: ~D[2026-04-25],
          born_alive: 10,
          service_type: "ai"
        )

      {:ok, _w, batch} =
        Breeding.record_weaning(scope, farrowing, %{
          weaned_at: ~D[2026-05-15],
          weaned_count: 9,
          batch_tag: "B1"
        })

      sow = Animals.get_animal!(scope, sow.id)
      assert sow.status == "dry"
      assert batch.quantity == 9

      assert {:ok, :weaning, _w} = AnimalActivity.undo_latest(scope, sow)

      sow = Animals.get_animal!(scope, sow.id)
      assert sow.status == "lactating"

      batch = Peggy.Repo.get!(Peggy.Animals.Animal, batch.id)
      assert batch.quantity == 0
    end

    test "refuses to undo a service with a closed outcome", %{scope: scope, sow: sow} do
      _farrowing =
        farrowing_fixture(scope, sow,
          farrowed_at: ~D[2026-04-25],
          born_alive: 10,
          service_type: "ai"
        )

      # Now the latest event should be the farrowing — undoing the
      # service directly would be blocked anyway. Ask for the service
      # via direct delete to confirm precondition.
      service =
        Peggy.Repo.one!(Ecto.Query.from(s in Peggy.Breeding.Service, where: s.sow_id == ^sow.id))

      assert {:error, :service_has_closed_outcome} = Breeding.delete_service(scope, service)
    end
  end
end
