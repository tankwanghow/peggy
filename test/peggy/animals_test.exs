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
          breed: "Landrace"
        })

      assert animal.tracking_type == "individual"
      assert animal.ear_tag == "A001"
      assert animal.stage == "sow"
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

    test "individual requires ear_tag", %{scope: scope} do
      assert {:error, cs} =
               Animals.create_animal(scope, %{
                 tracking_type: "individual",
                 stage: "grower"
               })

      assert errors_on(cs)[:ear_tag]
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
                 stage: "grower"
               })

      assert errors_on(cs)[:ear_tag]
    end

    test "ear_tag may be reused once the prior animal departs", %{scope: scope} do
      original = animal_fixture(scope, ear_tag: "REUSE1", stage: "sow")

      original
      |> Ecto.Changeset.change(%{status: "sold"})
      |> Peggy.Repo.update!()

      assert {:ok, fresh} =
               Animals.create_animal(scope, %{
                 tracking_type: "individual",
                 ear_tag: "REUSE1",
                 stage: "sow"
               })

      assert fresh.id != original.id
      assert fresh.ear_tag == "REUSE1"
    end

    test "validates stage inclusion", %{scope: scope} do
      assert {:error, cs} =
               Animals.create_animal(scope, %{
                 tracking_type: "individual",
                 ear_tag: "X1",
                 stage: "invalid"
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
      sire = animal_fixture(scope, ear_tag: "SIRE1", stage: "boar")
      dam = animal_fixture(scope, ear_tag: "DAM1", stage: "sow")

      {:ok, offspring_animal} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "GILT1",
          stage: "sow",
          sire_id: sire.id,
          dam_id: dam.id
        })

      loaded = Animals.get_animal!(scope, offspring_animal.id)
      assert loaded.sire.id == sire.id
      assert loaded.dam.id == dam.id

      offspring = Animals.list_offspring(scope, sire)
      assert length(offspring) == 1
      assert hd(offspring).id == offspring_animal.id
    end
  end

  describe "movements" do
    test "records a placement movement on create with pen", %{scope: scope, pen: pen} do
      {:ok, animal} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "M1",
          stage: "grower",
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

  describe "record_batch_movements/3" do
    setup %{scope: scope, house: house} do
      a = pen_fixture(scope, house, code: "A", capacity: 200)
      b = pen_fixture(scope, house, code: "B", capacity: 200)
      c = pen_fixture(scope, house, code: "C", capacity: 200)

      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "weaner",
          quantity: 100
        })

      %{batch: batch, a: a, b: b, c: c}
    end

    test "commits many placements atomically",
         %{scope: scope, batch: batch, a: a, b: b, c: c} do
      assert {:ok, [_, _, _]} =
               Animals.record_batch_movements(scope, batch, [
                 %{reason: "placement", to_pen_id: a.id, quantity: 40},
                 %{reason: "placement", to_pen_id: b.id, quantity: 35},
                 %{reason: "placement", to_pen_id: c.id, quantity: 25}
               ])

      total =
        Animals.list_placements(scope, batch)
        |> Enum.reduce(0, &(&1.quantity + &2))

      assert total == 100
    end

    test "rejects aggregate placement over-subscription",
         %{scope: scope, batch: batch, a: a, b: b} do
      assert {:error, {1, cs}} =
               Animals.record_batch_movements(scope, batch, [
                 %{reason: "placement", to_pen_id: a.id, quantity: 60},
                 %{reason: "placement", to_pen_id: b.id, quantity: 50}
               ])

      assert errors_on(cs)[:quantity]
      assert Animals.list_placements(scope, batch) == []
    end

    test "merges multiple placements into one pen",
         %{scope: scope, batch: batch, a: a} do
      {:ok, _} =
        Animals.record_batch_movements(scope, batch, [
          %{reason: "placement", to_pen_id: a.id, quantity: 20},
          %{reason: "placement", to_pen_id: a.id, quantity: 30}
        ])

      [p] = Animals.list_placements(scope, batch)
      assert p.pen_id == a.id
      assert p.quantity == 50
    end

    test "mixes placements and a pen transfer in one call",
         %{scope: scope, batch: batch, a: a, b: b, c: c} do
      {:ok, _} =
        Animals.record_batch_movements(scope, batch, [
          %{reason: "placement", to_pen_id: a.id, quantity: 60},
          %{reason: "placement", to_pen_id: b.id, quantity: 40},
          %{reason: "pen_transfer", from_pen_id: a.id, to_pen_id: c.id, quantity: 20}
        ])

      placements =
        Animals.list_placements(scope, batch)
        |> Map.new(&{&1.pen_id, &1.quantity})

      assert placements == %{a.id => 40, b.id => 40, c.id => 20}
      assert Animals.get_animal!(scope, batch.id).quantity == 100
    end

    test "rolls back everything when any row fails",
         %{scope: scope, batch: batch, a: a} do
      assert {:error, {1, _cs}} =
               Animals.record_batch_movements(scope, batch, [
                 %{reason: "placement", to_pen_id: a.id, quantity: 40},
                 # missing to_pen_id
                 %{reason: "placement", quantity: 20}
               ])

      assert Animals.list_placements(scope, batch) == []
    end

    test "rejects same-pen transfers", %{scope: scope, batch: batch, a: a} do
      {:ok, _} =
        Animals.record_batch_movements(scope, batch, [
          %{reason: "placement", to_pen_id: a.id, quantity: 50}
        ])

      assert {:error, {0, cs}} =
               Animals.record_batch_movements(scope, batch, [
                 %{reason: "pen_transfer", from_pen_id: a.id, to_pen_id: a.id, quantity: 10}
               ])

      assert errors_on(cs)[:to_pen_id]
    end

    test "rejects transfer from a pen with no placement",
         %{scope: scope, batch: batch, a: a, b: b} do
      assert {:error, {0, cs}} =
               Animals.record_batch_movements(scope, batch, [
                 %{reason: "pen_transfer", from_pen_id: a.id, to_pen_id: b.id, quantity: 10}
               ])

      assert errors_on(cs)[:from_pen_id]
    end

    test "rejects unsupported reasons", %{scope: scope, batch: batch, a: a} do
      assert {:error, {0, cs}} =
               Animals.record_batch_movements(scope, batch, [
                 %{reason: "sale", from_pen_id: a.id, quantity: 5}
               ])

      assert errors_on(cs)[:reason]
    end

    test "rejects individual animals", %{scope: scope, pen: pen} do
      ind = animal_fixture(scope, current_pen_id: pen.id)

      assert {:error, :batch_only} =
               Animals.record_batch_movements(scope, ind, [
                 %{reason: "placement", to_pen_id: pen.id, quantity: 1}
               ])
    end

    test "rejects empty list", %{scope: scope, batch: batch} do
      assert {:error, :no_entries} = Animals.record_batch_movements(scope, batch, [])
    end

    test "writes one audit row per committed movement",
         %{scope: scope, batch: batch, a: a, b: b} do
      before = length(Audit.list(scope))

      {:ok, _} =
        Animals.record_batch_movements(scope, batch, [
          %{reason: "placement", to_pen_id: a.id, quantity: 40},
          %{reason: "placement", to_pen_id: b.id, quantity: 30}
        ])

      assert length(Audit.list(scope)) - before == 2
    end
  end

  describe "record_bulk_individual_moves/2" do
    setup %{scope: scope, house: house, pen: pen} do
      pen2 = pen_fixture(scope, house, code: "P2", capacity: 50)
      pen3 = pen_fixture(scope, house, code: "P3", capacity: 50)

      sow1 = animal_fixture(scope, ear_tag: "S1", stage: "sow", current_pen_id: pen.id)
      sow2 = animal_fixture(scope, ear_tag: "S2", stage: "sow", current_pen_id: pen.id)
      unplaced = animal_fixture(scope, ear_tag: "S3", stage: "sow")

      %{pen2: pen2, pen3: pen3, sow1: sow1, sow2: sow2, unplaced: unplaced}
    end

    test "moves many individual animals atomically",
         %{scope: scope, pen2: pen2, pen3: pen3, sow1: sow1, sow2: sow2} do
      assert {:ok, [m1, m2]} =
               Animals.record_bulk_individual_moves(scope, [
                 %{animal_id: sow1.id, to_pen_id: pen2.id},
                 %{animal_id: sow2.id, to_pen_id: pen3.id}
               ])

      assert m1.reason == "pen_transfer"
      assert m2.reason == "pen_transfer"
      assert Animals.get_animal!(scope, sow1.id).current_pen_id == pen2.id
      assert Animals.get_animal!(scope, sow2.id).current_pen_id == pen3.id
    end

    test "infers placement when animal has no current pen",
         %{scope: scope, pen2: pen2, unplaced: unplaced} do
      assert {:ok, [m]} =
               Animals.record_bulk_individual_moves(scope, [
                 %{animal_id: unplaced.id, to_pen_id: pen2.id}
               ])

      assert m.reason == "placement"
      assert is_nil(m.from_pen_id)
      assert Animals.get_animal!(scope, unplaced.id).current_pen_id == pen2.id
    end

    test "rejects destination equal to current pen",
         %{scope: scope, pen: pen, sow1: sow1} do
      assert {:error, {0, cs}} =
               Animals.record_bulk_individual_moves(scope, [
                 %{animal_id: sow1.id, to_pen_id: pen.id}
               ])

      assert errors_on(cs)[:to_pen_id]
    end

    test "rejects duplicated animal in same batch",
         %{scope: scope, pen2: pen2, pen3: pen3, sow1: sow1} do
      assert {:error, {1, cs}} =
               Animals.record_bulk_individual_moves(scope, [
                 %{animal_id: sow1.id, to_pen_id: pen2.id},
                 %{animal_id: sow1.id, to_pen_id: pen3.id}
               ])

      assert errors_on(cs)[:animal_id]
    end

    test "rejects missing destination",
         %{scope: scope, sow1: sow1} do
      assert {:error, {0, cs}} =
               Animals.record_bulk_individual_moves(scope, [
                 %{animal_id: sow1.id}
               ])

      assert errors_on(cs)[:to_pen_id]
    end

    test "rejects batch animals",
         %{scope: scope, pen2: pen2} do
      batch = batch_fixture(scope, ear_tag: "BATCH1", quantity: 10)

      assert {:error, {0, cs}} =
               Animals.record_bulk_individual_moves(scope, [
                 %{animal_id: batch.id, to_pen_id: pen2.id}
               ])

      assert errors_on(cs)[:animal_id]
    end

    test "rejects animals outside scope", %{scope: scope, pen2: pen2} do
      other_user = user_fixture()
      other_farm = farm_fixture(other_user)
      other_scope = scope_for(other_user, other_farm)
      stranger = animal_fixture(other_scope)

      assert {:error, {0, cs}} =
               Animals.record_bulk_individual_moves(scope, [
                 %{animal_id: stranger.id, to_pen_id: pen2.id}
               ])

      assert errors_on(cs)[:animal_id]
    end

    test "rolls back everything when any row fails",
         %{scope: scope, pen: pen, pen2: pen2, sow1: sow1, sow2: sow2} do
      assert {:error, {1, _cs}} =
               Animals.record_bulk_individual_moves(scope, [
                 %{animal_id: sow1.id, to_pen_id: pen2.id},
                 # sow2 is already in pen (same-pen)
                 %{animal_id: sow2.id, to_pen_id: pen.id}
               ])

      # sow1's first step must not have persisted.
      assert Animals.get_animal!(scope, sow1.id).current_pen_id == pen.id
    end

    test "rejects empty list", %{scope: scope} do
      assert {:error, :no_entries} = Animals.record_bulk_individual_moves(scope, [])
    end

    test "writes one audit row per committed move",
         %{scope: scope, pen2: pen2, pen3: pen3, sow1: sow1, sow2: sow2} do
      before = length(Audit.list(scope))

      {:ok, _} =
        Animals.record_bulk_individual_moves(scope, [
          %{animal_id: sow1.id, to_pen_id: pen2.id},
          %{animal_id: sow2.id, to_pen_id: pen3.id}
        ])

      assert length(Audit.list(scope)) - before == 2
    end
  end

  describe "create_batch_animals/2" do
    test "creates multiple individual animals atomically", %{scope: scope, pen: pen} do
      {:ok, animals} =
        Animals.create_batch_animals(scope, [
          %{ear_tag: "SOW01", stage: "sow", breed: "Landrace"},
          %{
            ear_tag: "SOW02",
            stage: "sow",
            breed: "Yorkshire",
            current_pen_id: pen.id
          },
          %{ear_tag: "BOAR01", stage: "boar"}
        ])

      assert length(animals) == 3

      sow1 = Enum.at(animals, 0)
      assert sow1.ear_tag == "SOW01"
      assert sow1.tracking_type == "individual"
      assert sow1.stage == "sow"

      sow2 = Enum.at(animals, 1)
      assert sow2.ear_tag == "SOW02"
      assert sow2.current_pen_id == pen.id

      boar = Enum.at(animals, 2)
      assert boar.ear_tag == "BOAR01"
      assert boar.stage == "boar"
    end

    test "creates placement movement when pen_id given", %{scope: scope, pen: pen} do
      {:ok, [animal]} =
        Animals.create_batch_animals(scope, [
          %{ear_tag: "SOW10", stage: "sow", current_pen_id: pen.id}
        ])

      movements = Animals.list_movements(scope, animal)
      assert length(movements) == 1
      assert hd(movements).reason == "placement"
      assert hd(movements).to_pen_id == pen.id
    end

    test "rolls back all on validation error in any row", %{scope: scope} do
      result =
        Animals.create_batch_animals(scope, [
          %{ear_tag: "SOW20", stage: "sow"},
          %{ear_tag: "", stage: "sow"}
        ])

      assert {:error, {1, %Ecto.Changeset{}}} = result
      # First row should not have been committed
      assert Animals.list_animals(scope) == []
    end

    test "rejects duplicate ear tags in the same batch", %{scope: scope} do
      result =
        Animals.create_batch_animals(scope, [
          %{ear_tag: "DUP01", stage: "sow"},
          %{ear_tag: "DUP01", stage: "sow"}
        ])

      assert {:error, {1, %Ecto.Changeset{}}} = result
    end

    test "rejects empty list", %{scope: scope} do
      assert {:error, :no_entries} = Animals.create_batch_animals(scope, [])
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

  describe "import_herd/2" do
    test "creates an active individual sow from a single row", %{scope: scope} do
      {:ok, [animal]} =
        Animals.import_herd(scope, [
          %{
            tracking_type: "individual",
            ear_tag: "IMP-001",
            stage: "sow",
            status: "active"
          }
        ])

      assert animal.ear_tag == "IMP-001"
      assert animal.status == "active"
    end

    test "rejects served row without last_served_at", %{scope: scope} do
      assert {:error, {0, reason}} =
               Animals.import_herd(scope, [
                 %{
                   tracking_type: "individual",
                   ear_tag: "IMP-002",
                   stage: "sow",
                   status: "served"
                 }
               ])

      assert reason =~ "last_served_at"
    end

    test "served status creates an open Service", %{scope: scope} do
      {:ok, [animal]} =
        Animals.import_herd(scope, [
          %{
            tracking_type: "individual",
            ear_tag: "IMP-003",
            stage: "sow",
            status: "served",
            service_type: "ai",
            last_served_at: "2026-03-15"
          }
        ])

      assert animal.status == "served"

      service = Peggy.Repo.get_by(Peggy.Breeding.Service, sow_id: animal.id)
      assert service
      assert is_nil(service.result)
      assert service.served_at == ~D[2026-03-15]
    end

    test "lactating status creates closed service + farrowing + litter", %{
      scope: scope,
      pen: pen
    } do
      {:ok, [animal]} =
        Animals.import_herd(scope, [
          %{
            tracking_type: "individual",
            ear_tag: "IMP-004",
            stage: "sow",
            status: "lactating",
            service_type: "ai",
            last_served_at: "2026-01-01",
            last_farrowed_at: "2026-04-25",
            born_alive: 10,
            current_pen_id: pen.id
          }
        ])

      assert animal.status == "lactating"

      service = Peggy.Repo.get_by(Peggy.Breeding.Service, sow_id: animal.id)
      assert service.result == "farrowing"

      farrowing = Peggy.Repo.get_by(Peggy.Breeding.Farrowing, sow_id: animal.id)
      assert farrowing.born_alive == 10
      assert farrowing.farrowed_at == ~D[2026-04-25]

      # No piglet Animal is created — pre-wean piglets live as a count on
      # the farrowing row (+ the LitterEvent ledger), not as Animal rows.
      import Ecto.Query
      refute Peggy.Repo.one(from a in Animals.Animal, where: a.farrowing_id == ^farrowing.id)
    end

    test "rolls back the entire batch on any row failure", %{scope: scope} do
      # Row 0 is valid; row 1 is invalid (missing last_served_at for served)
      assert {:error, {1, _reason}} =
               Animals.import_herd(scope, [
                 %{
                   tracking_type: "individual",
                   ear_tag: "ROLL-1",
                   stage: "sow",
                   status: "active"
                 },
                 %{
                   tracking_type: "individual",
                   ear_tag: "ROLL-2",
                   stage: "sow",
                   status: "served"
                 }
               ])

      # First row must not have been persisted
      refute Peggy.Repo.get_by(Animals.Animal, ear_tag: "ROLL-1")
    end

    test "accepts open/dry/culled statuses directly on new animals", %{scope: scope} do
      {:ok, animals} =
        Animals.import_herd(scope, [
          %{
            tracking_type: "individual",
            ear_tag: "IMP-OPEN",
            stage: "sow",
            status: "open"
          },
          %{
            tracking_type: "individual",
            ear_tag: "IMP-DRY",
            stage: "sow",
            status: "dry"
          },
          %{
            tracking_type: "individual",
            ear_tag: "IMP-CULL",
            stage: "sow",
            status: "culled"
          }
        ])

      assert Enum.map(animals, & &1.status) == ["open", "dry", "culled"]
    end
  end

  describe "undo_last_movement/2" do
    test "undoes a placement — clears current_pen_id for individual", %{
      scope: scope,
      pen: pen
    } do
      animal = animal_fixture(scope, ear_tag: "U1", stage: "sow")

      {:ok, _} =
        Animals.record_movement(scope, animal, %{
          reason: "placement",
          to_pen_id: pen.id,
          moved_at: Date.utc_today()
        })

      animal = Animals.get_animal!(scope, animal.id)
      assert animal.current_pen_id == pen.id

      {:ok, _undone} = Animals.undo_last_movement(scope, animal)

      updated = Animals.get_animal!(scope, animal.id)
      assert is_nil(updated.current_pen_id)
      assert Animals.list_movements(scope, updated) == []
    end

    test "undoes a pen_transfer — restores current_pen_id", %{
      scope: scope,
      house: house,
      pen: pen
    } do
      pen2 = pen_fixture(scope, house, code: "P2", capacity: 50)

      animal =
        animal_fixture(scope, ear_tag: "U2", stage: "sow", current_pen_id: pen.id)

      {:ok, _} =
        Animals.record_movement(scope, animal, %{
          reason: "pen_transfer",
          to_pen_id: pen2.id,
          moved_at: Date.utc_today()
        })

      animal = Animals.get_animal!(scope, animal.id)
      assert animal.current_pen_id == pen2.id

      {:ok, _} = Animals.undo_last_movement(scope, animal)

      updated = Animals.get_animal!(scope, animal.id)
      assert updated.current_pen_id == pen.id
    end

    test "undoes a departure — restores status and current_pen_id", %{
      scope: scope,
      pen: pen
    } do
      animal =
        animal_fixture(scope, ear_tag: "U3", stage: "sow", current_pen_id: pen.id)

      {:ok, _} =
        Animals.record_movement(scope, animal, %{
          reason: "death",
          moved_at: Date.utc_today()
        })

      animal = Animals.get_animal!(scope, animal.id)
      assert animal.status == "deceased"
      assert is_nil(animal.current_pen_id)

      {:ok, _} = Animals.undo_last_movement(scope, animal)

      updated = Animals.get_animal!(scope, animal.id)
      assert updated.status == "active"
      assert updated.current_pen_id == pen.id
    end

    test "undoes a departure — reopens linked breeding service", %{
      scope: scope,
      pen: pen
    } do
      boar = animal_fixture(scope, ear_tag: "B1", stage: "boar")

      sow =
        animal_fixture(scope, ear_tag: "S1", stage: "sow", current_pen_id: pen.id)

      {:ok, service} =
        Peggy.Breeding.record_service(scope, %{
          sow_id: sow.id,
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-01-15]
        })

      {:ok, _} =
        Peggy.Breeding.close_service(scope, service, "death", %{result_at: ~D[2026-03-01]})

      sow = Animals.get_animal!(scope, sow.id)
      assert sow.status == "deceased"

      # Service is closed
      closed = Peggy.Breeding.get_service!(scope, service.id)
      assert closed.result == "death"

      # Undo the departure movement
      {:ok, _} = Animals.undo_last_movement(scope, sow)

      # Sow restored
      updated = Animals.get_animal!(scope, sow.id)
      assert updated.status == "served"
      assert updated.current_pen_id == pen.id

      # Service reopened
      reopened = Peggy.Breeding.get_service!(scope, service.id)
      assert is_nil(reopened.result)
      assert is_nil(reopened.result_at)
    end

    test "returns error when no movements exist", %{scope: scope} do
      animal = animal_fixture(scope, ear_tag: "U5", stage: "sow")
      assert {:error, :no_movements} = Animals.undo_last_movement(scope, animal)
    end

    test "undoes batch placement — removes destination placement", %{scope: scope, pen: pen} do
      batch =
        animal_fixture(scope,
          tracking_type: "batch",
          stage: "grower",
          quantity: 50
        )

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "placement",
          to_pen_id: pen.id,
          quantity: 50,
          moved_at: Date.utc_today()
        })

      assert length(Animals.list_placements(scope, batch)) == 1

      batch = Animals.get_animal!(scope, batch.id)
      {:ok, _} = Animals.undo_last_movement(scope, batch)

      assert Animals.list_placements(scope, batch) == []
    end

    test "undoes batch pen_transfer — reverses placements", %{
      scope: scope,
      house: house,
      pen: pen
    } do
      pen2 = pen_fixture(scope, house, code: "P2", capacity: 50)

      batch =
        animal_fixture(scope,
          tracking_type: "batch",
          stage: "grower",
          quantity: 100,
          current_pen_id: pen.id
        )

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "pen_transfer",
          from_pen_id: pen.id,
          to_pen_id: pen2.id,
          quantity: 40,
          moved_at: Date.utc_today()
        })

      batch = Animals.get_animal!(scope, batch.id)
      {:ok, _} = Animals.undo_last_movement(scope, batch)

      placements = Animals.list_placements(scope, batch)
      # All 100 back in pen, nothing in pen2
      assert length(placements) == 1
      assert hd(placements).pen_id == pen.id
      assert hd(placements).quantity == 100
    end

    test "undoes batch departure — restores quantity and status", %{scope: scope, pen: pen} do
      batch =
        animal_fixture(scope,
          tracking_type: "batch",
          stage: "finisher",
          quantity: 30,
          current_pen_id: pen.id
        )

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "sale",
          from_pen_id: pen.id,
          quantity: 30,
          moved_at: Date.utc_today()
        })

      batch = Animals.get_animal!(scope, batch.id)
      assert batch.status == "sold"
      assert batch.quantity == 0

      {:ok, _} = Animals.undo_last_movement(scope, batch)

      updated = Animals.get_animal!(scope, batch.id)
      assert updated.status == "active"
      assert updated.quantity == 30
    end

    test "writes audit log entry for undo", %{scope: scope, pen: pen} do
      animal =
        animal_fixture(scope, ear_tag: "U9", stage: "sow", current_pen_id: pen.id)

      {:ok, _} =
        Animals.record_movement(scope, animal, %{
          reason: "pen_transfer",
          to_pen_id: pen.id,
          moved_at: Date.utc_today()
        })

      animal = Animals.get_animal!(scope, animal.id)
      {:ok, _} = Animals.undo_last_movement(scope, animal)

      logs = Audit.list(scope, action: "movement.undone")
      assert length(logs) == 1
    end
  end

  describe "mark_reviewed/2" do
    test "clears needs_review and writes an audit row", %{scope: scope} do
      {:ok, animal} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "R1",
          stage: "sow"
        })

      {1, _} =
        Peggy.Repo.update_all(
          Ecto.Query.from(a in Peggy.Animals.Animal, where: a.id == ^animal.id),
          set: [needs_review: true, inferred: true, created_via: "back_fill_from_service"]
        )

      animal = Animals.get_animal!(scope, animal.id)
      assert animal.needs_review

      {:ok, reviewed} = Animals.mark_reviewed(scope, animal)
      refute reviewed.needs_review

      logs = Audit.list(scope, action: "animal.reviewed")
      assert length(logs) == 1
    end

    test "no-op when already reviewed", %{scope: scope} do
      {:ok, animal} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "R2",
          stage: "sow"
        })

      assert {:ok, _} = Animals.mark_reviewed(scope, animal)
      assert Audit.list(scope, action: "animal.reviewed") == []
    end
  end

  describe "list_animals needs_review filter" do
    test "narrows to rows with needs_review = true", %{scope: scope} do
      {:ok, a} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "NR1",
          stage: "sow"
        })

      {:ok, _b} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "NR2",
          stage: "sow"
        })

      {1, _} =
        Peggy.Repo.update_all(
          Ecto.Query.from(x in Peggy.Animals.Animal, where: x.id == ^a.id),
          set: [needs_review: true]
        )

      rows = Animals.list_animals(scope, needs_review: true)
      assert Enum.map(rows, & &1.ear_tag) == ["NR1"]
    end
  end

  describe "suggest_promotions/1" do
    setup %{user: user} do
      today = ~D[2026-05-15]

      farm =
        farm_fixture(user, %{
          slug: "promote-#{System.unique_integer([:positive])}"
        })

      {:ok, farm} =
        farm
        |> Ecto.Changeset.change(%{
          simulated_today: today,
          weaner_to_grower_days: 70,
          grower_to_finisher_days: 120,
          finisher_overdue_days: 200
        })
        |> Peggy.Repo.update()

      scope = scope_for(user, farm)
      %{scope: scope, today: today}
    end

    test "buckets are empty when no batches exist", %{scope: scope} do
      assert %{
               weaner_to_grower: [],
               grower_to_finisher: [],
               finisher_overdue: []
             } = Animals.suggest_promotions(scope)
    end

    test "weaner exactly at threshold is suggested", %{scope: scope, today: today} do
      a = batch_with_dob(scope, "weaner", Date.add(today, -70))
      assert %{weaner_to_grower: [%{animal: %{id: id}}]} = Animals.suggest_promotions(scope)
      assert id == a.id
    end

    test "weaner under threshold is excluded", %{scope: scope, today: today} do
      _a = batch_with_dob(scope, "weaner", Date.add(today, -69))
      assert %{weaner_to_grower: []} = Animals.suggest_promotions(scope)
    end

    test "grower past threshold lands in grower bucket", %{scope: scope, today: today} do
      a = batch_with_dob(scope, "grower", Date.add(today, -120))
      assert %{grower_to_finisher: [%{animal: %{id: id}}]} = Animals.suggest_promotions(scope)
      assert id == a.id
    end

    test "finisher past overdue lands in overdue bucket", %{scope: scope, today: today} do
      a = batch_with_dob(scope, "finisher", Date.add(today, -200))

      assert %{finisher_overdue: [%{animal: %{id: id}, age_days: 200}]} =
               Animals.suggest_promotions(scope)

      assert id == a.id
    end

    test "departed and zero-quantity batches are excluded", %{scope: scope, today: today} do
      old = Date.add(today, -300)
      live = batch_with_dob(scope, "weaner", old)

      empty = batch_with_dob(scope, "weaner", old)
      empty |> Ecto.Changeset.change(%{quantity: 0}) |> Peggy.Repo.update!()

      sold = batch_with_dob(scope, "weaner", old)
      sold |> Ecto.Changeset.change(%{status: "sold"}) |> Peggy.Repo.update!()

      ids =
        scope
        |> Animals.suggest_promotions()
        |> Map.fetch!(:weaner_to_grower)
        |> Enum.map(& &1.animal.id)

      assert ids == [live.id]
    end

    test "individual animals are excluded", %{scope: scope, today: today} do
      _ind =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "IND1",
          stage: "sow",
          dob: Date.add(today, -1000)
        })

      assert %{weaner_to_grower: [], grower_to_finisher: [], finisher_overdue: []} =
               Animals.suggest_promotions(scope)
    end

    test "rows are sorted oldest-first within a bucket", %{scope: scope, today: today} do
      a_younger = batch_with_dob(scope, "weaner", Date.add(today, -75))
      a_oldest = batch_with_dob(scope, "weaner", Date.add(today, -120))

      ids =
        scope
        |> Animals.suggest_promotions()
        |> Map.fetch!(:weaner_to_grower)
        |> Enum.map(& &1.animal.id)

      assert ids == [a_oldest.id, a_younger.id]
    end
  end

  describe "promote_many/3" do
    setup %{user: user} do
      today = ~D[2026-05-15]

      farm =
        farm_fixture(user, %{
          slug: "pm-#{System.unique_integer([:positive])}"
        })

      {:ok, farm} =
        farm
        |> Ecto.Changeset.change(%{simulated_today: today})
        |> Peggy.Repo.update()

      scope = scope_for(user, farm)
      %{scope: scope, today: today}
    end

    test "promotes the listed batches and returns ok rows", %{scope: scope, today: today} do
      a = batch_with_dob(scope, "weaner", Date.add(today, -90))
      b = batch_with_dob(scope, "weaner", Date.add(today, -90))

      result = Animals.promote_many(scope, [a.id, b.id], "grower")
      assert length(result.ok) == 2
      assert result.errors == []
      assert Enum.all?(result.ok, &(&1.stage == "grower"))
    end

    test "per-row partial success: bad row reports an error, good row commits",
         %{scope: scope, today: today} do
      good = batch_with_dob(scope, "weaner", Date.add(today, -90))

      {:ok, ind} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "IND-PM",
          stage: "sow"
        })

      result = Animals.promote_many(scope, [good.id, ind.id], "grower")

      assert [%{id: id, stage: "grower"}] = result.ok
      assert id == good.id
      assert [{ind_id, :batch_only}] = result.errors
      assert ind_id == ind.id
    end

    test "unknown animal id surfaces as :not_found in errors", %{scope: scope} do
      result = Animals.promote_many(scope, [-1], "grower")
      assert result.ok == []
      assert result.errors == [{-1, :not_found}]
    end
  end

  describe "depart_entire_batch/3" do
    setup %{user: user} do
      farm = farm_fixture(user, %{slug: "depart-#{System.unique_integer([:positive])}"})
      scope = scope_for(user, farm)
      house = house_fixture(scope, code: "DH1")
      pen_a = pen_fixture(scope, house, code: "PA", capacity: 100)
      pen_b = pen_fixture(scope, house, code: "PB", capacity: 100)
      %{scope: scope, pen_a: pen_a, pen_b: pen_b}
    end

    test "single-pen batch: one movement, qty drops to 0, status flips to sold",
         %{scope: scope, pen_a: pen_a} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "finisher",
          quantity: 30,
          current_pen_id: pen_a.id
        })

      {:ok, after_dep} = Animals.depart_entire_batch(scope, batch, "sale")

      assert after_dep.quantity == 0
      assert after_dep.status == "sold"

      assert Animals.list_placements(scope, after_dep) == []
    end

    test "multi-pen batch: one movement per placement, status flips on the last one",
         %{scope: scope, pen_a: pen_a, pen_b: pen_b} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "finisher",
          quantity: 30,
          current_pen_id: pen_a.id
        })

      {:ok, _} =
        Animals.record_movement(scope, batch, %{
          reason: "pen_transfer",
          from_pen_id: pen_a.id,
          to_pen_id: pen_b.id,
          quantity: 12,
          moved_at: Date.utc_today()
        })

      batch = Animals.get_animal!(scope, batch.id)
      assert batch.quantity == 30
      assert length(Animals.list_placements(scope, batch)) == 2

      {:ok, after_dep} = Animals.depart_entire_batch(scope, batch, "slaughter")

      assert after_dep.quantity == 0
      assert after_dep.status == "slaughtered"
      assert Animals.list_placements(scope, after_dep) == []
    end

    test "rejects individual animals", %{scope: scope} do
      {:ok, ind} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "DEP-IND",
          stage: "sow"
        })

      assert {:error, :batch_only} = Animals.depart_entire_batch(scope, ind, "sale")
    end

    test "rejects unknown reason", %{scope: scope, pen_a: pen_a} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "finisher",
          quantity: 5,
          current_pen_id: pen_a.id
        })

      assert {:error, :invalid_reason} =
               Animals.depart_entire_batch(scope, batch, "vacation")
    end

    test "legacy batch with no active placement still departs cleanly",
         %{scope: scope} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "finisher",
          quantity: 14
        })

      assert Animals.list_placements(scope, batch) == []

      {:ok, after_dep} = Animals.depart_entire_batch(scope, batch, "sale")

      assert after_dep.quantity == 0
      assert after_dep.status == "sold"

      [movement] = Animals.list_movements(scope, after_dep)
      assert movement.reason == "sale"
      assert movement.from_pen_id == nil
      assert movement.quantity == 14
    end

    test "no-op on already-departed batch", %{scope: scope, pen_a: pen_a} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "finisher",
          quantity: 5,
          current_pen_id: pen_a.id
        })

      {:ok, _} = Animals.depart_entire_batch(scope, batch, "sale")
      reloaded = Animals.get_animal!(scope, batch.id)
      assert {:error, :already_departed} = Animals.depart_entire_batch(scope, reloaded, "sale")
    end
  end

  describe "depart_many/3" do
    setup %{user: user} do
      farm = farm_fixture(user, %{slug: "dm-#{System.unique_integer([:positive])}"})
      scope = scope_for(user, farm)
      house = house_fixture(scope, code: "MH1")
      pen = pen_fixture(scope, house, code: "MP", capacity: 100)
      %{scope: scope, pen: pen}
    end

    test "departs every batch and reports them in :ok", %{scope: scope, pen: pen} do
      {:ok, a} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "finisher",
          quantity: 10,
          current_pen_id: pen.id
        })

      {:ok, b} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "finisher",
          quantity: 8,
          current_pen_id: pen.id
        })

      result = Animals.depart_many(scope, [a.id, b.id], "sale")
      assert length(result.ok) == 2
      assert result.errors == []
      assert Enum.all?(result.ok, &(&1.status == "sold"))
    end

    test "per-row partial success: individual animal errors out, batch commits",
         %{scope: scope, pen: pen} do
      {:ok, batch} =
        Animals.create_animal(scope, %{
          tracking_type: "batch",
          stage: "finisher",
          quantity: 6,
          current_pen_id: pen.id
        })

      {:ok, ind} =
        Animals.create_animal(scope, %{
          tracking_type: "individual",
          ear_tag: "DM-IND",
          stage: "sow"
        })

      result = Animals.depart_many(scope, [batch.id, ind.id], "sale")
      assert [%{id: id, status: "sold"}] = result.ok
      assert id == batch.id
      assert [{ind_id, :batch_only}] = result.errors
      assert ind_id == ind.id
    end
  end

  defp batch_with_dob(scope, stage, dob, extra \\ %{}) do
    {:ok, batch} =
      Animals.create_animal(
        scope,
        Map.merge(
          %{
            tracking_type: "batch",
            stage: stage,
            quantity: 20,
            dob: dob
          },
          extra
        )
      )

    batch
  end
end
