defmodule Peggy.AnimalsTest do
  use Peggy.DataCase, async: true

  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures

  alias Peggy.{Animals, Audit}

  setup do
    user = user_fixture()
    farm = farm_fixture(user)
    scope = scope_for(user, farm)
    house = house_fixture(scope, code: "H1")
    pen = pen_fixture(scope, house, code: "P1", capacity: 50)
    %{user: user, farm: farm, scope: scope, house: house, pen: pen}
  end

  describe "animals CRUD" do
    test "creates an individual animal", %{scope: scope} do
      {:ok, animal} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "A001",
          stage: "sow",
          sex: "female",
          breed: "Landrace"
        })

      assert animal.tracking_type == "individual"
      assert animal.ear_tag == "A001"
      assert animal.stage == "sow"
      assert animal.sex == "female"
      assert animal.quantity == 1
    end

    test "creates a batch animal", %{scope: scope} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 30
        })

      assert batch.tracking_type == "batch"
      assert batch.quantity == 30
    end

    test "individual requires ear_tag and sex", %{scope: scope} do
      assert {:error, cs} =
               Animals.create_animal(scope, %{
                 tracking_type: "individual",
                 stage: "grower"
               })

      errors = errors_on(cs)
      assert errors[:ear_tag]
      assert errors[:sex]
    end

    test "batch requires quantity > 1", %{scope: scope} do
      assert {:error, cs} =
               Animals.create_animal(scope, %{
                 tracking_type: "batch",
                 stage: "weaner",
                 quantity: 1
               })

      assert errors_on(cs)[:quantity]
    end

    test "ear_tag must be unique per farm", %{scope: scope} do
      animal_fixture(scope, ear_tag: "DUP1")

      assert {:error, cs} =
               Animals.create_animal(scope, %{
                 tracking_type: "individual",
                 ear_tag: "DUP1",
                 stage: "grower",
                 sex: "male"
               })

      assert errors_on(cs)[:ear_tag]
    end

    test "validates stage inclusion", %{scope: scope} do
      assert {:error, cs} =
               Animals.create_animal(scope, %{
                 tracking_type: "individual",
                 ear_tag: "X1",
                 stage: "invalid",
                 sex: "male"
               })

      assert errors_on(cs)[:stage]
    end

    test "lists and filters animals", %{scope: scope} do
      animal_fixture(scope, ear_tag: "G1", stage: "grower")
      animal_fixture(scope, ear_tag: "S1", stage: "sow")

      all = Animals.list_animals(scope)
      assert length(all) == 2

      growers = Animals.list_animals(scope, stage: "grower")
      assert length(growers) == 1
      assert hd(growers).ear_tag == "G1"
    end

    test "updates an animal", %{scope: scope} do
      animal = animal_fixture(scope)
      {:ok, updated} = Animals.update_animal(scope, animal, %{breed: "Duroc"})
      assert updated.breed == "Duroc"
    end

    test "updates stage", %{scope: scope} do
      animal = animal_fixture(scope, stage: "grower")
      {:ok, updated} = Animals.update_stage(scope, animal, "finisher")
      assert updated.stage == "finisher"
    end
  end

  describe "parentage" do
    test "tracks sire and dam", %{scope: scope} do
      sire = animal_fixture(scope, ear_tag: "SIRE1", sex: "male", stage: "boar")
      dam = animal_fixture(scope, ear_tag: "DAM1", sex: "female", stage: "sow")

      {:ok, piglet} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "PIG1",
          stage: "piglet",
          sex: "female",
          sire_id: sire.id,
          dam_id: dam.id
        })

      loaded = Animals.get_animal!(scope, piglet.id)
      assert loaded.sire.id == sire.id
      assert loaded.dam.id == dam.id

      offspring = Animals.list_offspring(scope, sire)
      assert length(offspring) == 1
      assert hd(offspring).id == piglet.id
    end
  end

  describe "movements" do
    test "records a placement movement on create with pen", %{scope: scope, pen: pen} do
      {:ok, animal} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "M1",
          stage: "grower",
          sex: "male",
          current_pen_id: pen.id
        })

      assert animal.current_pen_id == pen.id
      movements = Animals.list_movements(scope, animal)
      assert length(movements) == 1
      assert hd(movements).reason == "placement"
      assert hd(movements).to_pen_id == pen.id
    end

    test "records a pen transfer", %{scope: scope, house: house, pen: pen} do
      animal = animal_fixture(scope, current_pen_id: pen.id)
      pen2 = pen_fixture(scope, house, code: "P2", capacity: 50)

      {:ok, movement} =
        Animals.record_movement(scope, animal, %{
          reason: "pen_transfer",
          to_pen_id: pen2.id,
          moved_at: Date.utc_today()
        })

      assert movement.to_pen_id == pen2.id

      updated = Animals.get_animal!(scope, animal.id)
      assert updated.current_pen_id == pen2.id
    end

    test "departure sets status and clears pen", %{scope: scope, pen: pen} do
      animal = animal_fixture(scope, current_pen_id: pen.id)

      {:ok, _movement} =
        Animals.record_movement(scope, animal, %{
          reason: "sale",
          moved_at: Date.utc_today()
        })

      updated = Animals.get_animal!(scope, animal.id)
      assert updated.status == "sold"
      assert updated.current_pen_id == nil
    end

    test "death sets status to deceased", %{scope: scope, pen: pen} do
      animal = animal_fixture(scope, current_pen_id: pen.id)

      {:ok, _} =
        Animals.record_movement(scope, animal, %{
          reason: "death",
          moved_at: Date.utc_today(),
          notes: "Found dead in pen"
        })

      updated = Animals.get_animal!(scope, animal.id)
      assert updated.status == "deceased"
    end
  end

  describe "batch placements" do
    test "creating a batch with a pen seeds one placement for the full quantity",
         %{scope: scope, pen: pen} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 100,
          current_pen_id: pen.id
        })

      # Batches don't populate current_pen_id — location lives on the placement.
      assert batch.current_pen_id == nil

      placements = Animals.list_placements(scope, batch)
      assert [p] = placements
      assert p.pen_id == pen.id
      assert p.quantity == 100
      assert p.removed_at == nil
    end

    test "pen_transfer for a batch splits or moves the placement",
         %{scope: scope, house: house, pen: pen} do
      pen2 = pen_fixture(scope, house, code: "P2", capacity: 100)

      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 100,
          current_pen_id: pen.id
        })

      # Move 40 of 100 to pen2 — source should shrink, destination should open.
      {:ok, _mv} =
        Animals.record_movement(scope, batch, %{
          reason: "pen_transfer",
          from_pen_id: pen.id,
          to_pen_id: pen2.id,
          quantity: 40,
          moved_at: Date.utc_today()
        })

      placements = Animals.list_placements(scope, batch) |> Enum.sort_by(& &1.pen_id)

      assert [%{pen_id: p1_id, quantity: 60}, %{pen_id: p2_id, quantity: 40}] =
               placements

      assert Enum.sort([p1_id, p2_id]) == Enum.sort([pen.id, pen2.id])

      # Batch total must remain constant after an internal transfer.
      assert Animals.get_animal!(scope, batch.id).quantity == 100
    end

    test "pen_transfer merges into an existing destination placement",
         %{scope: scope, house: house, pen: pen} do
      pen2 = pen_fixture(scope, house, code: "P2", capacity: 100)

      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 100,
          current_pen_id: pen.id
        })

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "pen_transfer",
          from_pen_id: pen.id,
          to_pen_id: pen2.id,
          quantity: 30,
          moved_at: Date.utc_today()
        })

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "pen_transfer",
          from_pen_id: pen.id,
          to_pen_id: pen2.id,
          quantity: 20,
          moved_at: Date.utc_today()
        })

      placements = Animals.list_placements(scope, batch) |> Enum.sort_by(& &1.pen_id)
      qtys = Enum.map(placements, & &1.quantity) |> Enum.sort()
      # 100 - 30 - 20 = 50 left in pen, 30 + 20 = 50 in pen2
      assert qtys == [50, 50]
    end

    test "a full transfer closes the source placement",
         %{scope: scope, house: house, pen: pen} do
      pen2 = pen_fixture(scope, house, code: "P2", capacity: 100)

      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 50,
          current_pen_id: pen.id
        })

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "pen_transfer",
          from_pen_id: pen.id,
          to_pen_id: pen2.id,
          quantity: 50,
          moved_at: Date.utc_today()
        })

      assert [%{pen_id: p2_id, quantity: 50}] = Animals.list_placements(scope, batch)
      assert p2_id == pen2.id
    end

    test "batch departure decrements quantity and doesn't change other pens",
         %{scope: scope, pen: pen} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 40,
          current_pen_id: pen.id
        })

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "sale",
          from_pen_id: pen.id,
          quantity: 15,
          moved_at: Date.utc_today()
        })

      updated = Animals.get_animal!(scope, batch.id)
      assert updated.quantity == 25
      assert updated.status == "active"

      assert [%{quantity: 25}] = Animals.list_placements(scope, batch)
    end

    test "selling the entire batch flips status",
         %{scope: scope, pen: pen} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "finisher",
          quantity: 10,
          current_pen_id: pen.id
        })

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "sale",
          from_pen_id: pen.id,
          quantity: 10,
          moved_at: Date.utc_today()
        })

      updated = Animals.get_animal!(scope, batch.id)
      assert updated.status == "sold"
      assert updated.quantity == 0
      assert Animals.list_placements(scope, batch) == []
    end

    test "batch movement rejects a quantity larger than the source placement",
         %{scope: scope, house: house, pen: pen} do
      pen2 = pen_fixture(scope, house, code: "P2", capacity: 100)

      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 20,
          current_pen_id: pen.id
        })

      assert {:error, :insufficient_quantity} =
               Animals.record_movement(scope, batch, %{
                 reason: "pen_transfer",
                 from_pen_id: pen.id,
                 to_pen_id: pen2.id,
                 quantity: 999,
                 moved_at: Date.utc_today()
               })

      # Original placement should be untouched.
      assert [%{quantity: 20}] = Animals.list_placements(scope, batch)
    end

    test "batch can be created without a pen and placed later",
         %{scope: scope, pen: pen} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 50
        })

      assert batch.current_pen_id == nil
      assert Animals.list_placements(scope, batch) == []

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "placement",
          to_pen_id: pen.id,
          quantity: 30,
          moved_at: Date.utc_today()
        })

      assert [%{pen_id: p_id, quantity: 30}] = Animals.list_placements(scope, batch)
      assert p_id == pen.id

      # Batch total unchanged — placement just locates animals that
      # already exist in the batch.
      assert Animals.get_animal!(scope, batch.id).quantity == 50
    end

    test "placement cannot exceed the batch's unplaced quantity",
         %{scope: scope, pen: pen} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 20
        })

      assert {:error, cs} =
               Animals.record_movement(scope, batch, %{
                 reason: "placement",
                 to_pen_id: pen.id,
                 quantity: 30,
                 moved_at: Date.utc_today()
               })

      assert errors_on(cs)[:quantity]
    end

    test "update_animal ignores quantity changes for batches",
         %{scope: scope, pen: pen} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 50,
          current_pen_id: pen.id
        })

      # Attempts to hand-edit the batch total are silently dropped —
      # quantity is owned by the context (create + departure movements).
      assert {:ok, updated} =
               Animals.update_animal(scope, batch, %{breed: "Duroc", quantity: 999})

      assert updated.breed == "Duroc"
      assert updated.quantity == 50
    end

    test "adjustment_loss decrements placement + batch total, keeps status",
         %{scope: scope, pen: pen} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 100,
          current_pen_id: pen.id
        })

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "adjustment_loss",
          from_pen_id: pen.id,
          quantity: 5,
          moved_at: Date.utc_today(),
          notes: "miscount at arrival"
        })

      updated = Animals.get_animal!(scope, batch.id)
      assert updated.quantity == 95
      # adjustments never flip status, even when qty hits zero — only
      # real departure events (sale/slaughter/death/farm_transfer) do.
      assert updated.status == "active"
      assert [%{quantity: 95}] = Animals.list_placements(scope, batch)
    end

    test "adjustment_gain increments placement + batch total",
         %{scope: scope, pen: pen} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 30,
          current_pen_id: pen.id
        })

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "adjustment_gain",
          to_pen_id: pen.id,
          quantity: 2,
          moved_at: Date.utc_today(),
          notes: "found two unrecorded piglets"
        })

      updated = Animals.get_animal!(scope, batch.id)
      assert updated.quantity == 32
      assert [%{quantity: 32}] = Animals.list_placements(scope, batch)
    end

    test "adjustment_gain into a new pen opens a fresh placement",
         %{scope: scope, house: house, pen: pen} do
      pen2 = pen_fixture(scope, house, code: "P2", capacity: 50)

      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 10,
          current_pen_id: pen.id
        })

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "adjustment_gain",
          to_pen_id: pen2.id,
          quantity: 3,
          moved_at: Date.utc_today()
        })

      assert Animals.get_animal!(scope, batch.id).quantity == 13

      placements = Animals.list_placements(scope, batch) |> Enum.sort_by(& &1.pen_id)
      qtys = Enum.map(placements, & &1.quantity) |> Enum.sort()
      assert qtys == [3, 10]
    end

    test "adjustments are rejected for individual animals", %{scope: scope, pen: pen} do
      animal = animal_fixture(scope, current_pen_id: pen.id)

      assert {:error, cs} =
               Animals.record_movement(scope, animal, %{
                 reason: "adjustment_loss",
                 from_pen_id: pen.id,
                 quantity: 1,
                 moved_at: Date.utc_today()
               })

      assert errors_on(cs)[:reason]
    end

    test "count_animals_in_pen aggregates individuals and batches",
         %{scope: scope, house: house, pen: pen} do
      animal_fixture(scope, ear_tag: "IND1", current_pen_id: pen.id)
      animal_fixture(scope, ear_tag: "IND2", current_pen_id: pen.id)

      pen2 = pen_fixture(scope, house, code: "P2", capacity: 100)

      {:ok, _batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 50,
          current_pen_id: pen.id
        })

      _other_batch =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 10,
          current_pen_id: pen2.id
        })

      assert Animals.count_animals_in_pen(scope, pen.id) == 52
      assert Animals.count_animals_in_pen(scope, pen2.id) == 10
    end
  end

  describe "scope isolation" do
    test "animals are scoped to the farm", %{scope: scope} do
      animal = animal_fixture(scope)

      other_user = user_fixture()
      other_farm = farm_fixture(other_user)
      other_scope = scope_for(other_user, other_farm)

      assert_raise Ecto.NoResultsError, fn ->
        Animals.get_animal!(other_scope, animal.id)
      end

      assert Animals.list_animals(other_scope) == []
    end
  end

  describe "audit" do
    test "mutations write audit log rows", %{scope: scope, pen: pen, house: house} do
      animal = animal_fixture(scope, current_pen_id: pen.id)
      pen2 = pen_fixture(scope, house, code: "P3", capacity: 50)

      {:ok, _} = Animals.update_animal(scope, animal, %{breed: "Duroc"})

      {:ok, _} =
        Animals.record_movement(scope, animal, %{
          reason: "pen_transfer",
          to_pen_id: pen2.id,
          moved_at: Date.utc_today()
        })

      rows = Audit.list(scope)
      actions = Enum.map(rows, & &1.action)
      assert "animal.created" in actions
      assert "animal.updated" in actions
      assert "movement.recorded" in actions
    end
  end
end
