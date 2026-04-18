defmodule Peggy.BreedingTest do
  use Peggy.DataCase, async: true

  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures
  import Peggy.BreedingFixtures

  alias Peggy.{Breeding, Audit}

  setup do
    user = user_fixture()
    farm = farm_fixture(user)
    scope = scope_for(user, farm)
    house = house_fixture(scope, code: "H1", purpose: "farrowing")
    pen = pen_fixture(scope, house, code: "F1", capacity: 20)
    sow = animal_fixture(scope, ear_tag: "SOW1", sex: "female", stage: "sow")
    boar = animal_fixture(scope, ear_tag: "BOAR1", sex: "male", stage: "boar")
    %{scope: scope, house: house, pen: pen, sow: sow, boar: boar}
  end

  describe "record_service/2" do
    test "creates a service with result nil (gestating)", %{scope: scope, sow: sow, boar: boar} do
      {:ok, service} =
        Breeding.record_service(scope, %{
          sow_id: sow.id,
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-01-15]
        })

      assert service.sow_id == sow.id
      assert service.boar_id == boar.id
      assert service.service_type == "natural"
      assert service.served_at == ~D[2026-01-15]
      assert is_nil(service.result)

      # Sow status updated to served
      updated_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert updated_sow.status == "served"
    end

    test "AI service does not require boar_id", %{scope: scope, sow: sow} do
      {:ok, service} =
        Breeding.record_service(scope, %{
          sow_id: sow.id,
          service_type: "ai",
          served_at: ~D[2026-01-15]
        })

      assert is_nil(service.boar_id)
      assert service.service_type == "ai"
    end

    test "natural service requires boar_id", %{scope: scope, sow: sow} do
      {:error, cs} =
        Breeding.record_service(scope, %{
          sow_id: sow.id,
          service_type: "natural",
          served_at: ~D[2026-01-15]
        })

      assert errors_on(cs)[:boar_id]
    end

    test "auto-closes prior open service with re_service", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      {:ok, first} =
        Breeding.record_service(scope, %{
          sow_id: sow.id,
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-01-15]
        })

      assert is_nil(first.result)

      {:ok, second} =
        Breeding.record_service(scope, %{
          sow_id: sow.id,
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-05]
        })

      # First service should now be closed
      first_reloaded = Breeding.get_service!(scope, first.id)
      assert first_reloaded.result == "re_service"
      assert first_reloaded.result_at == ~D[2026-02-05]

      # Second service is the open one
      assert is_nil(second.result)
    end

    test "writes audit log", %{scope: scope, sow: sow, boar: boar} do
      {:ok, _} =
        Breeding.record_service(scope, %{
          sow_id: sow.id,
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-01-15]
        })

      logs = Audit.list(scope, entity_type: "service", action: "service.created")
      assert length(logs) == 1
    end
  end

  describe "record_batch_services/2" do
    test "creates multiple services atomically", %{scope: scope, sow: sow, boar: boar} do
      sow2 = animal_fixture(scope, ear_tag: "SOW2", sex: "female", stage: "sow")

      {:ok, services} =
        Breeding.record_batch_services(scope, [
          %{
            sow_id: sow.id,
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-01-15]
          },
          %{
            sow_id: sow2.id,
            service_type: "ai",
            served_at: ~D[2026-01-15]
          }
        ])

      assert length(services) == 2
      assert Enum.at(services, 0).sow_id == sow.id
      assert Enum.at(services, 1).sow_id == sow2.id
    end

    test "auto-closes prior open services per sow", %{scope: scope, sow: sow, boar: boar} do
      prior = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])
      assert is_nil(prior.result)

      {:ok, [new_service]} =
        Breeding.record_batch_services(scope, [
          %{
            sow_id: sow.id,
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-02-01]
          }
        ])

      reloaded = Breeding.get_service!(scope, prior.id)
      assert reloaded.result == "re_service"
      assert is_nil(new_service.result)
    end

    test "rolls back all on validation error in any row", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      sow2 = animal_fixture(scope, ear_tag: "SOW2", sex: "female", stage: "sow")

      result =
        Breeding.record_batch_services(scope, [
          %{
            sow_id: sow.id,
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-01-15]
          },
          %{
            sow_id: sow2.id,
            service_type: "natural",
            served_at: ~D[2026-01-15]
            # missing boar_id for natural service
          }
        ])

      assert {:error, {1, %Ecto.Changeset{}}} = result
      # First row should not have been committed
      assert Breeding.list_services(scope) == []
    end

    test "rejects empty list", %{scope: scope} do
      assert {:error, :no_entries} = Breeding.record_batch_services(scope, [])
    end

    test "writes audit logs for each service", %{scope: scope, sow: sow, boar: boar} do
      sow2 = animal_fixture(scope, ear_tag: "SOW2", sex: "female", stage: "sow")

      {:ok, _} =
        Breeding.record_batch_services(scope, [
          %{
            sow_id: sow.id,
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-01-15]
          },
          %{
            sow_id: sow2.id,
            service_type: "ai",
            served_at: ~D[2026-01-15]
          }
        ])

      logs = Audit.list(scope, entity_type: "service", action: "service.created")
      assert length(logs) == 2
    end
  end

  describe "close_service/4" do
    test "closes an open service with abortion", %{scope: scope, sow: sow, boar: boar} do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, closed} =
        Breeding.close_service(scope, service, "abortion", %{
          result_at: ~D[2026-03-01],
          result_notes: "Early termination"
        })

      assert closed.result == "abortion"
      assert closed.result_at == ~D[2026-03-01]
      assert closed.result_notes == "Early termination"
    end

    test "closes with death, records departure movement, marks sow deceased", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, closed} =
        Breeding.close_service(scope, service, "death", %{result_at: ~D[2026-03-15]})

      assert closed.result == "death"

      updated_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert updated_sow.status == "deceased"
      assert is_nil(updated_sow.current_pen_id)

      # Departure movement recorded
      movements = Peggy.Animals.list_movements(scope, updated_sow)
      assert length(movements) == 1
      assert hd(movements).reason == "death"
      assert hd(movements).moved_at == ~D[2026-03-15]
    end

    test "closes with cull, records departure movement, marks sow sold", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, closed} =
        Breeding.close_service(scope, service, "cull", %{result_at: ~D[2026-03-15]})

      assert closed.result == "cull"

      updated_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert updated_sow.status == "sold"

      # Departure movement recorded with reason "sale"
      movements = Peggy.Animals.list_movements(scope, updated_sow)
      assert length(movements) == 1
      assert hd(movements).reason == "sale"
    end

    test "abortion moves sow to open", %{scope: scope, sow: sow, boar: boar} do
      service = service_fixture(scope, sow, boar_id: boar.id)

      # After service, sow is "served"
      assert Peggy.Animals.get_animal!(scope, sow.id).status == "served"

      {:ok, _} =
        Breeding.close_service(scope, service, "abortion", %{result_at: ~D[2026-03-01]})

      # After abortion, sow becomes "open" (ready to re-serve)
      updated_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert updated_sow.status == "open"
    end

    test "rejects closing an already closed service", %{scope: scope, sow: sow, boar: boar} do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, closed} =
        Breeding.close_service(scope, service, "abortion", %{result_at: ~D[2026-03-01]})

      assert {:error, :already_closed} =
               Breeding.close_service(scope, closed, "cull", %{result_at: ~D[2026-03-02]})
    end

    test "writes audit log on close", %{scope: scope, sow: sow, boar: boar} do
      service = service_fixture(scope, sow, boar_id: boar.id)
      {:ok, _} = Breeding.close_service(scope, service, "abortion", %{result_at: ~D[2026-03-01]})

      logs = Audit.list(scope, entity_type: "service", action: "service.closed")
      assert length(logs) >= 1
    end
  end

  describe "current_service/2" do
    test "returns the open service for a sow", %{scope: scope, sow: sow, boar: boar} do
      service = service_fixture(scope, sow, boar_id: boar.id)
      current = Breeding.current_service(scope, sow.id)

      assert current.id == service.id
      assert is_nil(current.result)
    end

    test "returns nil when no open service", %{scope: scope, sow: sow, boar: boar} do
      service = service_fixture(scope, sow, boar_id: boar.id)
      Breeding.close_service(scope, service, "abortion", %{result_at: ~D[2026-03-01]})

      assert is_nil(Breeding.current_service(scope, sow.id))
    end
  end

  describe "list_services/2" do
    test "lists all services for the farm", %{scope: scope, sow: sow, boar: boar} do
      service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-15])

      sow2 = animal_fixture(scope, ear_tag: "SOW2", sex: "female", stage: "sow")
      service_fixture(scope, sow2, boar_id: boar.id, served_at: ~D[2026-02-01])

      services = Breeding.list_services(scope)
      assert length(services) == 2
    end

    test "filters by sow_id", %{scope: scope, sow: sow, boar: boar} do
      service_fixture(scope, sow, boar_id: boar.id)

      sow2 = animal_fixture(scope, ear_tag: "SOW2", sex: "female", stage: "sow")
      service_fixture(scope, sow2, boar_id: boar.id)

      services = Breeding.list_services(scope, sow_id: sow.id)
      assert length(services) == 1
      assert hd(services).sow_id == sow.id
    end

    test "filters by result :open", %{scope: scope, sow: sow, boar: boar} do
      service = service_fixture(scope, sow, boar_id: boar.id)

      sow2 = animal_fixture(scope, ear_tag: "SOW2", sex: "female", stage: "sow")
      s2 = service_fixture(scope, sow2, boar_id: boar.id)
      Breeding.close_service(scope, s2, "abortion", %{result_at: ~D[2026-03-01]})

      open = Breeding.list_services(scope, result: :open)
      assert length(open) == 1
      assert hd(open).id == service.id
    end
  end

  describe "gestating sows" do
    test "list_gestating_sows returns sows with open services", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-15])
      gestating = Breeding.list_gestating_sows(scope)

      assert length(gestating) == 1
      entry = hd(gestating)
      assert entry.service.sow_id == sow.id
      assert entry.expected_farrow_date == Date.add(~D[2026-01-15], 114)
    end

    test "excludes closed services", %{scope: scope, sow: sow, boar: boar} do
      service = service_fixture(scope, sow, boar_id: boar.id)
      Breeding.close_service(scope, service, "abortion", %{result_at: ~D[2026-03-01]})

      assert Breeding.list_gestating_sows(scope) == []
    end

    test "filters by sow ear-tag prefix (case-insensitive)",
         %{scope: scope, sow: sow, boar: boar} do
      sow2 = animal_fixture(scope, ear_tag: "SOWB", sex: "female", stage: "sow")
      service_fixture(scope, sow, boar_id: boar.id)
      service_fixture(scope, sow2, boar_id: boar.id)

      assert [%{service: %{sow_id: sid}}] = Breeding.list_gestating_sows(scope, search: "sow1")
      assert sid == sow.id
      assert Breeding.count_gestating_sows(scope, search: "sow1") == 1
      assert Breeding.count_gestating_sows(scope, search: "sow") == 2
    end

    test "filters by service_type", %{scope: scope, sow: sow, boar: boar} do
      sow2 = animal_fixture(scope, ear_tag: "SOWB", sex: "female", stage: "sow")
      service_fixture(scope, sow, boar_id: boar.id, service_type: "natural")
      service_fixture(scope, sow2, service_type: "ai")

      assert [%{service: %{service_type: "ai"}}] =
               Breeding.list_gestating_sows(scope, service_type: "ai")

      assert Breeding.count_gestating_sows(scope, service_type: "natural") == 1
    end

    test "due_window narrows by expected farrow date", %{scope: scope, sow: sow, boar: boar} do
      sow2 = animal_fixture(scope, ear_tag: "SOWB", sex: "female", stage: "sow")
      # Served 110d ago → due in 4d (within 7-day window)
      service_fixture(scope, sow, boar_id: boar.id, served_at: Date.add(Date.utc_today(), -110))
      # Served 30d ago → due in 84d (not in 7d window)
      service_fixture(scope, sow2, boar_id: boar.id, served_at: Date.add(Date.utc_today(), -30))

      assert [%{service: %{sow_id: sid}}] = Breeding.list_gestating_sows(scope, due_window: "7")
      assert sid == sow.id
      assert Breeding.count_gestating_sows(scope, due_window: "7") == 1
      assert Breeding.count_gestating_sows(scope, due_window: "all") == 2
    end

    test "due_window=overdue picks past-due services", %{scope: scope, sow: sow, boar: boar} do
      service_fixture(scope, sow, boar_id: boar.id, served_at: Date.add(Date.utc_today(), -120))

      assert [_] = Breeding.list_gestating_sows(scope, due_window: "overdue")
      assert Breeding.count_gestating_sows(scope, due_window: "overdue") == 1
    end

    test "limit + offset paginate the result", %{scope: scope, boar: boar} do
      sows =
        for i <- 1..5 do
          animal_fixture(scope, ear_tag: "P#{i}", sex: "female", stage: "sow")
        end

      Enum.each(sows, fn s -> service_fixture(scope, s, boar_id: boar.id) end)

      page1 = Breeding.list_gestating_sows(scope, limit: 2, offset: 0)
      page2 = Breeding.list_gestating_sows(scope, limit: 2, offset: 2)
      page3 = Breeding.list_gestating_sows(scope, limit: 2, offset: 4)

      assert length(page1) == 2
      assert length(page2) == 2
      assert length(page3) == 1
      assert Breeding.count_gestating_sows(scope) == 5
    end
  end

  describe "lactating sows filters" do
    test "filters by sow ear-tag prefix", %{scope: scope, sow: sow, boar: boar} do
      sow2 = animal_fixture(scope, ear_tag: "SOWB", sex: "female", stage: "sow")
      farrowing_fixture(scope, sow, boar_id: boar.id)
      farrowing_fixture(scope, sow2, boar_id: boar.id)

      assert [%{sow_id: sid}] = Breeding.list_lactating_sows(scope, search: "sow1")
      assert sid == sow.id
      assert Breeding.count_lactating_sows(scope, search: "sow") == 2
    end

    test "filters by litter age bucket", %{scope: scope, sow: sow, boar: boar} do
      sow2 = animal_fixture(scope, ear_tag: "SOWB", sex: "female", stage: "sow")
      # Recent farrow → week1
      farrowing_fixture(scope, sow, boar_id: boar.id, farrowed_at: Date.add(Date.utc_today(), -2))
      # 25d old → wean_due
      farrowing_fixture(scope, sow2,
        boar_id: boar.id,
        farrowed_at: Date.add(Date.utc_today(), -25)
      )

      assert [%{sow_id: sid}] = Breeding.list_lactating_sows(scope, age_bucket: "week1")
      assert sid == sow.id
      assert [%{sow_id: sid2}] = Breeding.list_lactating_sows(scope, age_bucket: "wean_due")
      assert sid2 == sow2.id
    end

    test "filters by pen_id", %{scope: scope, sow: sow, boar: boar, house: house, pen: pen} do
      sow2 = animal_fixture(scope, ear_tag: "SOWB", sex: "female", stage: "sow")
      pen2 = pen_fixture(scope, house, code: "F2", capacity: 20)
      farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      farrowing_fixture(scope, sow2, boar_id: boar.id, pen_id: pen2.id)

      assert [%{pen_id: pid}] = Breeding.list_lactating_sows(scope, pen_id: pen.id)
      assert pid == pen.id
      assert Breeding.count_lactating_sows(scope, pen_id: pen2.id) == 1
    end

    test "limit + offset paginate the result", %{scope: scope, boar: boar} do
      for i <- 1..4 do
        s = animal_fixture(scope, ear_tag: "L#{i}", sex: "female", stage: "sow")
        farrowing_fixture(scope, s, boar_id: boar.id)
      end

      assert length(Breeding.list_lactating_sows(scope, limit: 2, offset: 0)) == 2
      assert length(Breeding.list_lactating_sows(scope, limit: 2, offset: 2)) == 2
      assert Breeding.count_lactating_sows(scope) == 4
    end
  end

  describe "expected_farrow_date/1" do
    test "returns served_at + 114 days", %{scope: scope, sow: sow, boar: boar} do
      service = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])
      assert Breeding.expected_farrow_date(service) == ~D[2026-04-25]
    end
  end

  describe "record_farrowing/3" do
    test "creates farrowing, litter batch, and closes service", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])

      {:ok, farrowing, litter} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 10,
          stillborn: 1,
          mummified: 0,
          pen_id: pen.id
        })

      assert farrowing.born_alive == 10
      assert farrowing.stillborn == 1
      assert farrowing.sow_id == sow.id
      assert farrowing.service_id == service.id
      assert farrowing.pen_id == pen.id

      # One litter batch created
      assert litter.tracking_type == "batch"
      assert litter.stage == "piglet"
      assert litter.quantity == 10
      assert litter.dam_id == sow.id
      assert litter.sire_id == boar.id
      assert litter.dob == ~D[2026-04-25]
      assert litter.farrowing_id == farrowing.id

      # Batch placed in pen via placement
      placements = Peggy.Animals.list_placements(scope, litter)
      assert length(placements) == 1
      assert hd(placements).pen_id == pen.id
      assert hd(placements).quantity == 10

      # Service closed with farrowing result
      closed = Breeding.get_service!(scope, service.id)
      assert closed.result == "farrowing"
      assert closed.result_at == ~D[2026-04-25]

      # Sow status updated to lactating
      updated_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert updated_sow.status == "lactating"
    end

    test "litter placed via sow's current_pen when no pen_id given", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      {:ok, _} =
        Peggy.Animals.update_animal(scope, sow, %{current_pen_id: pen.id})

      sow = Peggy.Animals.get_animal!(scope, sow.id)
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, farrowing, litter} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 3
        })

      assert farrowing.pen_id == pen.id

      placements = Peggy.Animals.list_placements(scope, litter)
      assert length(placements) == 1
      assert hd(placements).pen_id == pen.id
    end

    test "litter unplaced when sow has no pen and no pen_id given", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, farrowing, litter} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 2
        })

      assert is_nil(farrowing.pen_id)

      placements = Peggy.Animals.list_placements(scope, litter)
      assert placements == []
    end

    test "born_alive=0 creates no litter batch", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, farrowing, litter} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 0,
          stillborn: 5,
          pen_id: pen.id
        })

      assert farrowing.born_alive == 0
      assert is_nil(litter)
    end

    test "auto-promotes sow stage if not already sow", %{scope: scope, boar: boar, pen: pen} do
      gilt = animal_fixture(scope, ear_tag: "GILT1", sex: "female", stage: "grower")
      service = service_fixture(scope, gilt, boar_id: boar.id)

      {:ok, _farrowing, _litter} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 5,
          pen_id: pen.id
        })

      promoted = Peggy.Animals.get_animal!(scope, gilt.id)
      assert promoted.stage == "sow"
      assert promoted.status == "lactating"
    end

    test "rejects farrowing on already-closed service", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)
      Breeding.close_service(scope, service, "abortion", %{result_at: ~D[2026-03-01]})

      closed = Breeding.get_service!(scope, service.id)

      assert {:error, :service_already_closed} =
               Breeding.record_farrowing(scope, closed, %{
                 farrowed_at: ~D[2026-04-25],
                 born_alive: 10,
                 pen_id: pen.id
               })
    end

    test "writes audit log", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, _, _} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 3,
          pen_id: pen.id
        })

      logs = Audit.list(scope, entity_type: "farrowing", action: "farrowing.created")
      assert length(logs) == 1
    end

    test "AI service litter has nil sire_id", %{scope: scope, sow: sow, pen: pen} do
      {:ok, service} =
        Breeding.record_service(scope, %{
          sow_id: sow.id,
          service_type: "ai",
          served_at: ~D[2026-01-01]
        })

      {:ok, _farrowing, litter} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 4,
          pen_id: pen.id
        })

      assert is_nil(litter.sire_id)
    end
  end

  describe "parity/2" do
    test "returns the number of farrowings for a sow", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      assert Breeding.parity(scope, sow.id) == 0

      s1 = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])

      {:ok, f1, _} =
        Breeding.record_farrowing(scope, s1, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 5,
          pen_id: pen.id
        })

      assert Breeding.parity(scope, sow.id) == 1

      # Wean to return sow to a serviceable state (dry) before next service
      {:ok, _, _} =
        Breeding.record_weaning(scope, f1, %{weaned_at: ~D[2026-05-20], weaned_count: 5})

      s2 = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-06-01])

      Breeding.record_farrowing(scope, s2, %{
        farrowed_at: ~D[2026-09-23],
        born_alive: 8,
        pen_id: pen.id
      })

      assert Breeding.parity(scope, sow.id) == 2
    end
  end

  describe "record_weaning/3" do
    test "promotes litter batch to weaner and moves to destination pen", %{
      scope: scope,
      house: house,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      nursery_pen = pen_fixture(scope, house, code: "N1", capacity: 40)

      farrowing =
        farrowing_fixture(scope, sow,
          boar_id: boar.id,
          born_alive: 10,
          pen_id: pen.id
        )

      {:ok, weaning, batch} =
        Breeding.record_weaning(scope, farrowing, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 8,
          destination_pen_id: nursery_pen.id
        })

      assert weaning.weaned_count == 8
      assert weaning.farrowing_id == farrowing.id

      # Litter batch promoted to weaner with updated quantity
      assert batch.tracking_type == "batch"
      assert batch.stage == "weaner"
      assert batch.quantity == 8

      # Old placement closed, new placement in nursery pen
      placements = Peggy.Animals.list_placements(scope, batch)
      assert length(placements) == 1
      assert hd(placements).pen_id == nursery_pen.id
      assert hd(placements).quantity == 8

      # Sow becomes "dry" after weaning (resting before next heat)
      updated_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert updated_sow.status == "dry"
    end

    test "weaned_count == 1 promotes batch to weaner", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      farrowing =
        farrowing_fixture(scope, sow,
          boar_id: boar.id,
          born_alive: 3,
          pen_id: pen.id
        )

      {:ok, weaning, batch} =
        Breeding.record_weaning(scope, farrowing, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 1
        })

      assert weaning.weaned_count == 1
      assert batch.stage == "weaner"
      assert batch.quantity == 1
      assert batch.tracking_type == "batch"
    end

    test "weaned_count == 0 marks batch as deceased", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      farrowing =
        farrowing_fixture(scope, sow,
          boar_id: boar.id,
          born_alive: 5,
          pen_id: pen.id
        )

      {:ok, weaning, batch} =
        Breeding.record_weaning(scope, farrowing, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 0
        })

      assert weaning.weaned_count == 0
      assert batch.status == "deceased"
      assert batch.quantity == 0
    end

    test "weaned_count == 0 with born_alive == 0 returns nil", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      farrowing =
        farrowing_fixture(scope, sow,
          boar_id: boar.id,
          born_alive: 0,
          pen_id: pen.id
        )

      {:ok, weaning, batch} =
        Breeding.record_weaning(scope, farrowing, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 0
        })

      assert weaning.weaned_count == 0
      assert is_nil(batch)
    end

    test "rejects double weaning", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      farrowing =
        farrowing_fixture(scope, sow,
          boar_id: boar.id,
          born_alive: 5,
          pen_id: pen.id
        )

      {:ok, _, _} =
        Breeding.record_weaning(scope, farrowing, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 5
        })

      assert {:error, :already_weaned} =
               Breeding.record_weaning(scope, farrowing, %{
                 weaned_at: ~D[2026-04-18],
                 weaned_count: 5
               })
    end

    test "without destination pen keeps litter in farrowing pen", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      farrowing =
        farrowing_fixture(scope, sow,
          boar_id: boar.id,
          born_alive: 6,
          pen_id: pen.id
        )

      {:ok, _weaning, batch} =
        Breeding.record_weaning(scope, farrowing, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 6
        })

      assert batch.tracking_type == "batch"
      # Placement remains in farrowing pen (not moved)
      placements = Peggy.Animals.list_placements(scope, batch)
      assert length(placements) == 1
      assert hd(placements).pen_id == pen.id
    end

    test "writes audit log", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      farrowing =
        farrowing_fixture(scope, sow,
          boar_id: boar.id,
          born_alive: 5,
          pen_id: pen.id
        )

      {:ok, _, _} =
        Breeding.record_weaning(scope, farrowing, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 5
        })

      logs = Audit.list(scope, entity_type: "weaning", action: "weaning.created")
      assert length(logs) == 1
    end
  end

  describe "surviving_piglet_count/1" do
    test "returns litter batch quantity", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      farrowing =
        farrowing_fixture(scope, sow,
          boar_id: boar.id,
          born_alive: 10,
          pen_id: pen.id
        )

      assert Breeding.surviving_piglet_count(farrowing) == 10

      # Decrement batch quantity (simulating piglet death)
      [litter] = Breeding.list_litter(scope, farrowing)
      Peggy.Repo.update!(Ecto.Changeset.change(litter, quantity: 9))

      assert Breeding.surviving_piglet_count(farrowing) == 9
    end
  end

  describe "list_farrowings/2" do
    test "lists farrowings for the farm", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      service = service_fixture(scope, sow, boar_id: boar.id)

      Breeding.record_farrowing(scope, service, %{
        farrowed_at: ~D[2026-04-25],
        born_alive: 5,
        pen_id: pen.id
      })

      farrowings = Breeding.list_farrowings(scope)
      assert length(farrowings) == 1
      assert hd(farrowings).sow_id == sow.id
    end

    test "filters by sow_id", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      s1 = service_fixture(scope, sow, boar_id: boar.id)

      Breeding.record_farrowing(scope, s1, %{
        farrowed_at: ~D[2026-04-25],
        born_alive: 5,
        pen_id: pen.id
      })

      sow2 = animal_fixture(scope, ear_tag: "SOW2", sex: "female", stage: "sow")
      s2 = service_fixture(scope, sow2, boar_id: boar.id)

      Breeding.record_farrowing(scope, s2, %{
        farrowed_at: ~D[2026-04-26],
        born_alive: 8,
        pen_id: pen.id
      })

      assert length(Breeding.list_farrowings(scope)) == 2
      assert length(Breeding.list_farrowings(scope, sow_id: sow.id)) == 1
    end
  end
end
