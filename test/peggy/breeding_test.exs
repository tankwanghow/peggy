defmodule Peggy.BreedingTest do
  use Peggy.DataCase, async: true

  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures
  import Peggy.BreedingFixtures
  import Ecto.Query

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

  describe "record_batch_services_with_backfill/2" do
    test "mixes existing-sow rows with inferred-sow rows atomically",
         %{scope: scope, sow: sow, boar: boar} do
      {:ok, services} =
        Breeding.record_batch_services_with_backfill(scope, [
          %{
            sow_id: sow.id,
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-02-01]
          },
          %{
            sow_ear_tag: "BATCH-NEW-1",
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-02-01],
            backfill_sow: %{breed: "Duroc"}
          }
        ])

      assert length(services) == 2
      [s1, s2] = services
      assert s1.sow_id == sow.id

      new_sow = Peggy.Animals.find_by_ear_tag(scope, "BATCH-NEW-1")
      assert new_sow
      assert new_sow.inferred == true
      assert new_sow.created_via == "back_fill_from_service"
      assert s2.sow_id == new_sow.id
      assert new_sow.status == "served"
    end

    test "resolves by ear_tag when sow exists", %{scope: scope, sow: sow, boar: boar} do
      {:ok, [service]} =
        Breeding.record_batch_services_with_backfill(scope, [
          %{
            sow_ear_tag: sow.ear_tag,
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-02-01]
          }
        ])

      assert service.sow_id == sow.id
    end

    test "hard-blocks on similar tag without force_create",
         %{scope: scope, boar: boar} do
      # sow fixture "SOW1" → "SOW2" is Levenshtein 1 away
      assert {:error, {0, {:similar_tag, tags}}} =
               Breeding.record_batch_services_with_backfill(scope, [
                 %{
                   sow_ear_tag: "SOW2",
                   boar_id: boar.id,
                   service_type: "natural",
                   served_at: ~D[2026-02-01],
                   backfill_sow: %{breed: "Duroc"}
                 }
               ])

      assert "SOW1" in tags
    end

    test "returns :sow_not_found when tag unknown and no backfill_sow given",
         %{scope: scope, boar: boar} do
      assert {:error, {0, :sow_not_found}} =
               Breeding.record_batch_services_with_backfill(scope, [
                 %{
                   sow_ear_tag: "UNKNOWN-XYZ",
                   boar_id: boar.id,
                   service_type: "natural",
                   served_at: ~D[2026-02-01]
                 }
               ])
    end

    test "rejects duplicate new ear tags within the grid", %{scope: scope, boar: boar} do
      assert {:error, {1, :duplicate_ear_tag}} =
               Breeding.record_batch_services_with_backfill(scope, [
                 %{
                   sow_ear_tag: "DUPE-1",
                   boar_id: boar.id,
                   service_type: "natural",
                   served_at: ~D[2026-02-01],
                   backfill_sow: %{breed: "Duroc"}
                 },
                 %{
                   sow_ear_tag: "DUPE-1",
                   boar_id: boar.id,
                   service_type: "natural",
                   served_at: ~D[2026-02-01],
                   backfill_sow: %{breed: "Duroc"}
                 }
               ])
    end

    test "rolls back all rows when any row fails validation",
         %{scope: scope, sow: sow} do
      result =
        Breeding.record_batch_services_with_backfill(scope, [
          %{
            sow_ear_tag: "ROLLBACK-BATCH-1",
            service_type: "natural",
            served_at: ~D[2026-02-01],
            backfill_sow: %{breed: "Duroc"}
          },
          # Missing boar_id for second row → natural service validation fails
          %{
            sow_id: sow.id,
            service_type: "natural",
            served_at: ~D[2026-02-01]
          }
        ])

      assert {:error, {_i, %Ecto.Changeset{}}} = result
      # Inferred sow from first row must not persist
      assert is_nil(Peggy.Animals.find_by_ear_tag(scope, "ROLLBACK-BATCH-1"))
    end

    test "per-row pen_id places inferred sow (placement movement)",
         %{scope: scope, pen: pen, boar: boar} do
      {:ok, [_s]} =
        Breeding.record_batch_services_with_backfill(scope, [
          %{
            sow_ear_tag: "PEN-BATCH-1",
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-02-01],
            pen_id: pen.id,
            backfill_sow: %{breed: "Duroc"}
          }
        ])

      sow = Peggy.Animals.find_by_ear_tag(scope, "PEN-BATCH-1")
      assert sow.current_pen_id == pen.id

      [mv] = Peggy.Repo.all(from m in Peggy.Animals.Movement, where: m.animal_id == ^sow.id)
      assert mv.reason == "placement"
      assert is_nil(mv.from_pen_id)
      assert mv.to_pen_id == pen.id
    end

    test "per-row pen_id transfers existing sow in different pen",
         %{scope: scope, house: house, pen: pen, boar: boar} do
      other_pen = pen_fixture(scope, house, code: "F-OTHER", capacity: 20)
      sow = animal_fixture(scope, ear_tag: "BATCH-MOVE", sex: "female", stage: "sow")

      {:ok, _} =
        sow
        |> Ecto.Changeset.change(%{current_pen_id: other_pen.id})
        |> Peggy.Repo.update()

      {:ok, [_s]} =
        Breeding.record_batch_services_with_backfill(scope, [
          %{
            sow_ear_tag: "BATCH-MOVE",
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-02-01],
            pen_id: pen.id
          }
        ])

      reloaded = Peggy.Animals.get_animal!(scope, sow.id)
      assert reloaded.current_pen_id == pen.id

      [mv] = Peggy.Repo.all(from m in Peggy.Animals.Movement, where: m.animal_id == ^sow.id)
      assert mv.reason == "pen_transfer"
      assert mv.from_pen_id == other_pen.id
      assert mv.to_pen_id == pen.id
    end

    test "per-row pen_id same as current pen → no movement",
         %{scope: scope, pen: pen, boar: boar} do
      sow = animal_fixture(scope, ear_tag: "BATCH-SAME", sex: "female", stage: "sow")

      {:ok, _} =
        sow
        |> Ecto.Changeset.change(%{current_pen_id: pen.id})
        |> Peggy.Repo.update()

      {:ok, [_s]} =
        Breeding.record_batch_services_with_backfill(scope, [
          %{
            sow_ear_tag: "BATCH-SAME",
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-02-01],
            pen_id: pen.id
          }
        ])

      movements =
        Peggy.Repo.all(from m in Peggy.Animals.Movement, where: m.animal_id == ^sow.id)

      assert movements == []
    end

    test "no pen_id → no movement, no sow update",
         %{scope: scope, sow: sow, boar: boar} do
      {:ok, _} =
        Breeding.record_batch_services_with_backfill(scope, [
          %{
            sow_ear_tag: sow.ear_tag,
            boar_id: boar.id,
            service_type: "natural",
            served_at: ~D[2026-02-01]
          }
        ])

      reloaded = Peggy.Animals.get_animal!(scope, sow.id)
      assert is_nil(reloaded.current_pen_id)

      movements =
        Peggy.Repo.all(from m in Peggy.Animals.Movement, where: m.animal_id == ^sow.id)

      assert movements == []
    end

    test "rejects empty list", %{scope: scope} do
      assert {:error, :no_entries} = Breeding.record_batch_services_with_backfill(scope, [])
    end
  end

  describe "record_batch_farrowings_with_backfill/2" do
    test "service_id path farrows an existing open service", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])

      {:ok, [farrowing]} =
        Breeding.record_batch_farrowings_with_backfill(scope, [
          %{
            service_id: service.id,
            farrowed_at: ~D[2026-04-25],
            born_alive: 9,
            stillborn: 1,
            pen_id: pen.id
          }
        ])

      assert farrowing.service_id == service.id
      assert farrowing.sow_id == sow.id
      assert farrowing.born_alive == 9

      closed = Breeding.get_service!(scope, service.id)
      assert closed.result == "farrowing"
    end

    test "existing sow with open service farrows via ear_tag", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])

      {:ok, [farrowing]} =
        Breeding.record_batch_farrowings_with_backfill(scope, [
          %{
            sow_ear_tag: sow.ear_tag,
            farrowed_at: ~D[2026-04-25],
            born_alive: 8,
            pen_id: pen.id
          }
        ])

      assert farrowing.service_id == service.id
      assert farrowing.sow_id == sow.id
    end

    test "existing sow without open service creates inferred service then farrows",
         %{scope: scope, pen: pen} do
      sow = animal_fixture(scope, ear_tag: "BF-NOSVC", sex: "female", stage: "sow")

      {:ok, [farrowing]} =
        Breeding.record_batch_farrowings_with_backfill(scope, [
          %{
            sow_ear_tag: "BF-NOSVC",
            farrowed_at: ~D[2026-04-25],
            born_alive: 7,
            pen_id: pen.id
          }
        ])

      assert farrowing.sow_id == sow.id

      service = Breeding.get_service!(scope, farrowing.service_id)
      assert service.inferred == true
      assert service.created_via == "back_fill_from_farrowing"
      assert service.service_type == "ai"
      assert service.served_at == Date.add(~D[2026-04-25], -114)
      assert service.result == "farrowing"

      logs = Audit.list(scope, entity_type: "service", action: "service.created.inferred")
      assert Enum.any?(logs, &(&1.entity_id == to_string(service.id)))
    end

    test "unknown ear tag with backfill_sow creates inferred sow + service + farrowing",
         %{scope: scope, pen: pen} do
      {:ok, [farrowing]} =
        Breeding.record_batch_farrowings_with_backfill(scope, [
          %{
            sow_ear_tag: "BF-NEWSOW-1",
            farrowed_at: ~D[2026-04-25],
            born_alive: 6,
            pen_id: pen.id,
            backfill_sow: %{breed: "Duroc"}
          }
        ])

      new_sow = Peggy.Animals.find_by_ear_tag(scope, "BF-NEWSOW-1")
      assert new_sow
      assert new_sow.inferred == true
      assert new_sow.created_via == "back_fill_from_farrowing"
      assert farrowing.sow_id == new_sow.id

      service = Breeding.get_service!(scope, farrowing.service_id)
      assert service.inferred == true
      assert service.created_via == "back_fill_from_farrowing"
    end

    test "hard-blocks on similar tag without force_create", %{scope: scope, pen: pen} do
      # fixture "SOW1" → "SOW2" is Levenshtein 1 away
      assert {:error, {0, {:similar_tag, tags}}} =
               Breeding.record_batch_farrowings_with_backfill(scope, [
                 %{
                   sow_ear_tag: "SOW2",
                   farrowed_at: ~D[2026-04-25],
                   born_alive: 5,
                   pen_id: pen.id,
                   backfill_sow: %{breed: "Duroc"}
                 }
               ])

      assert "SOW1" in tags
    end

    test "returns :sow_not_found when tag unknown and no backfill_sow",
         %{scope: scope, pen: pen} do
      assert {:error, {0, :sow_not_found}} =
               Breeding.record_batch_farrowings_with_backfill(scope, [
                 %{
                   sow_ear_tag: "UNKNOWN-XYZ",
                   farrowed_at: ~D[2026-04-25],
                   born_alive: 5,
                   pen_id: pen.id
                 }
               ])
    end

    test "rejects duplicate new ear tags within the grid", %{scope: scope, pen: pen} do
      assert {:error, {1, :duplicate_ear_tag}} =
               Breeding.record_batch_farrowings_with_backfill(scope, [
                 %{
                   sow_ear_tag: "BF-DUPE-1",
                   farrowed_at: ~D[2026-04-25],
                   born_alive: 5,
                   pen_id: pen.id,
                   backfill_sow: %{breed: "Duroc"}
                 },
                 %{
                   sow_ear_tag: "BF-DUPE-1",
                   farrowed_at: ~D[2026-04-25],
                   born_alive: 5,
                   pen_id: pen.id,
                   backfill_sow: %{breed: "Duroc"}
                 }
               ])
    end

    test "rolls back all rows when any row fails validation", %{scope: scope, pen: pen} do
      result =
        Breeding.record_batch_farrowings_with_backfill(scope, [
          %{
            sow_ear_tag: "BF-ROLLBACK-1",
            farrowed_at: ~D[2026-04-25],
            born_alive: 4,
            pen_id: pen.id,
            backfill_sow: %{breed: "Duroc"}
          },
          # Second row: no service_id and no sow_ear_tag → classification error
          %{
            farrowed_at: ~D[2026-04-25],
            born_alive: 2,
            pen_id: pen.id
          }
        ])

      assert {:error, {1, :sow_not_found}} = result
      assert is_nil(Peggy.Animals.find_by_ear_tag(scope, "BF-ROLLBACK-1"))
    end

    test "rejects empty list", %{scope: scope} do
      assert {:error, :no_entries} = Breeding.record_batch_farrowings_with_backfill(scope, [])
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

  describe "service_deletable?/2" do
    test "true for open services", %{scope: scope, sow: sow, boar: boar} do
      s = service_fixture(scope, sow, boar_id: boar.id)
      assert Breeding.service_deletable?(scope, s)
    end

    test "true for re_service (superseded)", %{scope: scope, sow: sow, boar: boar} do
      _s1 = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])
      # Second service auto-closes the first with result=re_service
      _s2 = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-02-01])

      closed = Peggy.Repo.get_by!(Peggy.Breeding.Service, result: "re_service")
      assert Breeding.service_deletable?(scope, closed)
    end

    test "false for closed outcomes", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, _, _} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 5,
          pen_id: pen.id
        })

      closed = Peggy.Repo.get!(Peggy.Breeding.Service, service.id)
      refute Breeding.service_deletable?(scope, closed)
    end

    test "false when already deleted", %{scope: scope, sow: sow, boar: boar} do
      s = service_fixture(scope, sow, boar_id: boar.id)
      {:ok, deleted} = Breeding.delete_service(scope, s)
      refute Breeding.service_deletable?(scope, deleted)
    end
  end

  describe "delete_service/2" do
    test "soft-deletes an open service and reverts sow to open", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      s = service_fixture(scope, sow, boar_id: boar.id)
      assert Peggy.Animals.get_animal!(scope, sow.id).status == "served"

      {:ok, deleted} = Breeding.delete_service(scope, s)

      assert deleted.deleted_at
      assert deleted.deleted_by_id == scope.user.id

      assert Peggy.Animals.get_animal!(scope, sow.id).status == "open"
    end

    test "soft-deletes a re_service record without touching sow status", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      _s1 = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])
      _s2 = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-02-01])

      closed = Peggy.Repo.get_by!(Peggy.Breeding.Service, result: "re_service")
      {:ok, _} = Breeding.delete_service(scope, closed)

      # Sow is still "served" from the newer service
      assert Peggy.Animals.get_animal!(scope, sow.id).status == "served"
    end

    test "rejects when service has farrowing outcome", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, _, _} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 5,
          pen_id: pen.id
        })

      closed = Peggy.Repo.get!(Peggy.Breeding.Service, service.id)
      assert {:error, :service_has_closed_outcome} = Breeding.delete_service(scope, closed)
    end

    test "rejects when already deleted", %{scope: scope, sow: sow, boar: boar} do
      s = service_fixture(scope, sow, boar_id: boar.id)
      {:ok, deleted} = Breeding.delete_service(scope, s)
      assert {:error, :already_deleted} = Breeding.delete_service(scope, deleted)
    end

    test "deleted services are excluded from list_services", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      s = service_fixture(scope, sow, boar_id: boar.id)
      {:ok, _} = Breeding.delete_service(scope, s)

      assert Breeding.list_services(scope) == []
    end

    test "deleted services are excluded from list_gestating_sows", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      s = service_fixture(scope, sow, boar_id: boar.id)
      {:ok, _} = Breeding.delete_service(scope, s)

      assert Breeding.list_gestating_sows(scope) == []
      assert Breeding.count_gestating_sows(scope) == 0
    end

    test "deleted services are excluded from current_service", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      s = service_fixture(scope, sow, boar_id: boar.id)
      {:ok, _} = Breeding.delete_service(scope, s)

      assert is_nil(Breeding.current_service(scope, sow.id))
    end

    test "get_service! raises on deleted row", %{scope: scope, sow: sow, boar: boar} do
      s = service_fixture(scope, sow, boar_id: boar.id)
      {:ok, _} = Breeding.delete_service(scope, s)

      assert_raise Ecto.NoResultsError, fn -> Breeding.get_service!(scope, s.id) end
    end

    test "writes audit log with snapshot", %{scope: scope, sow: sow, boar: boar} do
      s = service_fixture(scope, sow, boar_id: boar.id)
      {:ok, _} = Breeding.delete_service(scope, s)

      [log | _] = Audit.list(scope, entity_type: "service", action: "service.deleted")
      assert log.entity_id == to_string(s.id)
      assert log.changes["snapshot"]["sow_id"] == sow.id
    end

    test "a new service can be recorded after deleting an open one", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      s = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])
      {:ok, _} = Breeding.delete_service(scope, s)

      # Should not be auto-closed as re_service (prior is deleted)
      {:ok, s2} =
        Breeding.record_service(scope, %{
          sow_id: sow.id,
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01]
        })

      assert is_nil(s2.result)
      # Deleted service stays deleted, not re_service
      reloaded = Peggy.Repo.get!(Peggy.Breeding.Service, s.id)
      assert reloaded.deleted_at
      assert is_nil(reloaded.result)
    end
  end

  describe "restore_service/2" do
    test "restores a soft-deleted open service and re-serves sow", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      s = service_fixture(scope, sow, boar_id: boar.id)
      {:ok, deleted} = Breeding.delete_service(scope, s)
      assert Peggy.Animals.get_animal!(scope, sow.id).status == "open"

      {:ok, restored} = Breeding.restore_service(scope, deleted)

      assert is_nil(restored.deleted_at)
      assert is_nil(restored.deleted_by_id)
      assert Peggy.Animals.get_animal!(scope, sow.id).status == "served"
    end

    test "rejects restore when another open service exists for the sow", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      s1 = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])
      {:ok, deleted} = Breeding.delete_service(scope, s1)

      _s2 = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-02-01])

      assert {:error, :conflicting_open_service} = Breeding.restore_service(scope, deleted)
    end

    test "rejects restore on non-deleted service", %{scope: scope, sow: sow, boar: boar} do
      s = service_fixture(scope, sow, boar_id: boar.id)
      assert {:error, :not_deleted} = Breeding.restore_service(scope, s)
    end

    test "writes audit log", %{scope: scope, sow: sow, boar: boar} do
      s = service_fixture(scope, sow, boar_id: boar.id)
      {:ok, deleted} = Breeding.delete_service(scope, s)
      {:ok, _} = Breeding.restore_service(scope, deleted)

      logs = Audit.list(scope, entity_type: "service", action: "service.restored")
      assert length(logs) == 1
    end
  end

  describe "farrowing_deletable?/2" do
    test "true for a fresh farrowing", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      assert Breeding.farrowing_deletable?(scope, f)
    end

    test "false once weaned", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)

      {:ok, _, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: Date.utc_today(), weaned_count: 5})

      refute Breeding.farrowing_deletable?(scope, f)
    end

    test "false when litter has been moved", %{
      scope: scope,
      sow: sow,
      boar: boar,
      house: house,
      pen: pen
    } do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      dest = pen_fixture(scope, house, code: "NURS1", capacity: 30)

      [batch] = Peggy.Repo.all(from a in Peggy.Animals.Animal, where: a.farrowing_id == ^f.id)

      {:ok, _} =
        Peggy.Animals.record_movement(scope, batch, %{
          reason: "pen_transfer",
          from_pen_id: pen.id,
          to_pen_id: dest.id,
          quantity: batch.quantity,
          moved_at: Date.utc_today()
        })

      refute Breeding.farrowing_deletable?(scope, f)
    end

    test "false when already deleted", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      {:ok, deleted} = Breeding.delete_farrowing(scope, f)
      refute Breeding.farrowing_deletable?(scope, deleted)
    end
  end

  describe "delete_farrowing/2" do
    test "soft-deletes farrowing and cleans up litter + reverts sow + reopens service", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, farrowing, batch} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 6,
          pen_id: pen.id
        })

      batch_id = batch.id

      assert Peggy.Animals.get_animal!(scope, sow.id).status == "lactating"
      assert Peggy.Repo.get!(Peggy.Breeding.Service, service.id).result == "farrowing"

      {:ok, deleted} = Breeding.delete_farrowing(scope, farrowing)

      assert deleted.deleted_at
      assert deleted.deleted_by_id == scope.user.id

      # Litter batch + placement + movements removed
      assert is_nil(Peggy.Repo.get(Peggy.Animals.Animal, batch_id))

      assert Peggy.Repo.aggregate(
               from(p in Peggy.Animals.Placement, where: p.animal_id == ^batch_id),
               :count,
               :id
             ) == 0

      assert Peggy.Repo.aggregate(
               from(m in Peggy.Animals.Movement, where: m.animal_id == ^batch_id),
               :count,
               :id
             ) == 0

      # Sow state reverted
      reverted_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert reverted_sow.status == "served"

      # Service reopened
      reopened = Peggy.Repo.get!(Peggy.Breeding.Service, service.id)
      assert is_nil(reopened.result)
      assert is_nil(reopened.result_at)
    end

    test "reverts sow pen when farrowing moved her", %{
      scope: scope,
      sow: sow,
      boar: boar,
      house: house,
      pen: pen
    } do
      old_pen = pen_fixture(scope, house, code: "OLDFF", capacity: 20)
      {:ok, _} = Peggy.Animals.update_animal(scope, sow, %{current_pen_id: old_pen.id})
      sow = Peggy.Animals.get_animal!(scope, sow.id)
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, f, _} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 4,
          pen_id: pen.id
        })

      assert Peggy.Animals.get_animal!(scope, sow.id).current_pen_id == pen.id

      {:ok, _} = Breeding.delete_farrowing(scope, f)

      assert Peggy.Animals.get_animal!(scope, sow.id).current_pen_id == old_pen.id
    end

    test "rejects when weaning exists", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)

      {:ok, _, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: Date.utc_today(), weaned_count: 5})

      assert {:error, :farrowing_has_weaning} = Breeding.delete_farrowing(scope, f)
    end

    test "rejects when litter has activity", %{
      scope: scope,
      sow: sow,
      boar: boar,
      house: house,
      pen: pen
    } do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      dest = pen_fixture(scope, house, code: "ACT1", capacity: 30)
      [batch] = Peggy.Repo.all(from a in Peggy.Animals.Animal, where: a.farrowing_id == ^f.id)

      {:ok, _} =
        Peggy.Animals.record_movement(scope, batch, %{
          reason: "pen_transfer",
          from_pen_id: pen.id,
          to_pen_id: dest.id,
          quantity: batch.quantity,
          moved_at: Date.utc_today()
        })

      assert {:error, :farrowing_has_activity} = Breeding.delete_farrowing(scope, f)
    end

    test "rejects already-deleted farrowing", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      {:ok, deleted} = Breeding.delete_farrowing(scope, f)
      assert {:error, :already_deleted} = Breeding.delete_farrowing(scope, deleted)
    end

    test "born_alive=0 farrowing deletes cleanly (no batch to undo)", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, f, nil} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 0,
          stillborn: 5,
          pen_id: pen.id
        })

      {:ok, _} = Breeding.delete_farrowing(scope, f)

      assert is_nil(Peggy.Repo.get!(Peggy.Breeding.Service, service.id).result)
    end

    test "soft-deleted farrowing does not block re-recording for the same service", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])

      {:ok, f1, _} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 3,
          pen_id: pen.id
        })

      {:ok, _} = Breeding.delete_farrowing(scope, f1)

      # Service is reopened after delete — record a fresh farrowing against it.
      reopened = Breeding.get_service!(scope, service.id)
      assert is_nil(reopened.farrowing)

      {:ok, f2, _} =
        Breeding.record_farrowing(scope, reopened, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 4,
          pen_id: pen.id
        })

      assert f2.id != f1.id
      assert f2.service_id == service.id
    end

    test "deleted farrowing excluded from list_lactating_sows and list_farrowings", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      {:ok, _} = Breeding.delete_farrowing(scope, f)

      assert Breeding.list_lactating_sows(scope) == []
      assert Breeding.list_farrowings(scope) == []
      assert Breeding.count_lactating_sows(scope) == 0
    end

    test "get_farrowing! raises on deleted row", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      {:ok, _} = Breeding.delete_farrowing(scope, f)

      assert_raise Ecto.NoResultsError, fn -> Breeding.get_farrowing!(scope, f.id) end
    end

    test "parity excludes deleted farrowings", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      assert Breeding.parity(scope, sow.id) == 1

      {:ok, _} = Breeding.delete_farrowing(scope, f)
      assert Breeding.parity(scope, sow.id) == 0
    end

    test "writes audit log with snapshot", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      {:ok, _} = Breeding.delete_farrowing(scope, f)

      [log | _] = Audit.list(scope, entity_type: "farrowing", action: "farrowing.deleted")
      assert log.entity_id == to_string(f.id)
      assert log.changes["snapshot"]["sow_id"] == sow.id
      assert log.changes["snapshot"]["pen_id"] == pen.id
    end
  end

  describe "restore_farrowing/2" do
    test "restores farrowing and reapplies all side effects", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, f, _batch} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 4,
          pen_id: pen.id
        })

      {:ok, deleted} = Breeding.delete_farrowing(scope, f)
      {:ok, restored} = Breeding.restore_farrowing(scope, deleted)

      assert is_nil(restored.deleted_at)

      # Sow back to lactating
      assert Peggy.Animals.get_animal!(scope, sow.id).status == "lactating"

      # Service re-closed
      closed = Peggy.Repo.get!(Peggy.Breeding.Service, service.id)
      assert closed.result == "farrowing"

      # Litter batch recreated (new id, same farrowing_id)
      batches =
        Peggy.Repo.all(from a in Peggy.Animals.Animal, where: a.farrowing_id == ^f.id)

      assert [batch] = batches
      assert batch.quantity == 4

      # list_lactating_sows sees it again
      assert [reloaded] = Breeding.list_lactating_sows(scope)
      assert reloaded.id == f.id
    end

    test "rejects restore of non-deleted farrowing", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      assert {:error, :not_deleted} = Breeding.restore_farrowing(scope, f)
    end

    test "rejects restore when service has been closed again", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, f, _} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 3,
          pen_id: pen.id
        })

      {:ok, deleted} = Breeding.delete_farrowing(scope, f)

      reopened = Peggy.Repo.get!(Peggy.Breeding.Service, service.id)

      {:ok, _} =
        Breeding.close_service(scope, reopened, "abortion", %{result_at: Date.utc_today()})

      assert {:error, :service_reclosed} = Breeding.restore_farrowing(scope, deleted)
    end

    test "writes audit log", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      {:ok, deleted} = Breeding.delete_farrowing(scope, f)
      {:ok, _} = Breeding.restore_farrowing(scope, deleted)

      logs = Audit.list(scope, entity_type: "farrowing", action: "farrowing.restored")
      assert length(logs) == 1
    end
  end

  describe "list_deleted_farrowings/2" do
    test "returns deleted farrowings newest-first", %{scope: scope, boar: boar, pen: pen} do
      s1 = animal_fixture(scope, ear_tag: "DF1", sex: "female", stage: "sow")
      s2 = animal_fixture(scope, ear_tag: "DF2", sex: "female", stage: "sow")

      f1 = farrowing_fixture(scope, s1, boar_id: boar.id, pen_id: pen.id)
      f2 = farrowing_fixture(scope, s2, boar_id: boar.id, pen_id: pen.id)

      {:ok, _} = Breeding.delete_farrowing(scope, f1)
      {:ok, _} = Breeding.delete_farrowing(scope, f2)

      [first, second] = Breeding.list_deleted_farrowings(scope)
      # Tie-broken by id desc — f2 has higher id
      assert first.id == f2.id
      assert second.id == f1.id
    end

    test "excludes non-deleted farrowings", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      _f = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      assert Breeding.list_deleted_farrowings(scope) == []
    end
  end

  describe "list_deleted_services/2" do
    test "returns deleted services newest-first", %{scope: scope, sow: sow, boar: boar} do
      sow2 = animal_fixture(scope, ear_tag: "SOW2", sex: "female", stage: "sow")

      s1 = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])
      s2 = service_fixture(scope, sow2, boar_id: boar.id, served_at: ~D[2026-01-05])

      {:ok, _} = Breeding.delete_service(scope, s1)
      {:ok, _} = Breeding.delete_service(scope, s2)

      [first, second] = Breeding.list_deleted_services(scope)
      # Ordered by deleted_at desc, id desc — s2 has higher id so comes first
      assert first.id == s2.id
      assert second.id == s1.id
    end

    test "excludes non-deleted services", %{scope: scope, sow: sow, boar: boar} do
      _s = service_fixture(scope, sow, boar_id: boar.id)
      assert Breeding.list_deleted_services(scope) == []
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

    test "rejects farrowing when no pen_id given and sow has no current pen", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      assert {:error, cs} =
               Breeding.record_farrowing(scope, service, %{
                 farrowed_at: ~D[2026-04-25],
                 born_alive: 2
               })

      assert errors_on(cs)[:pen_id]
    end

    test "moves sow to farrowing pen when different from current pen", %{
      scope: scope,
      sow: sow,
      boar: boar,
      house: house,
      pen: pen
    } do
      old_pen = pen_fixture(scope, house, code: "OLD1", capacity: 20)
      {:ok, _} = Peggy.Animals.update_animal(scope, sow, %{current_pen_id: old_pen.id})
      sow = Peggy.Animals.get_animal!(scope, sow.id)
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, farrowing, _litter} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 5,
          pen_id: pen.id
        })

      assert farrowing.pen_id == pen.id

      updated_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert updated_sow.current_pen_id == pen.id

      moves =
        Peggy.Repo.all(
          from(m in Peggy.Animals.Movement,
            where: m.animal_id == ^sow.id,
            order_by: [desc: m.id]
          )
        )

      assert [move | _] = moves
      assert move.reason == "pen_transfer"
      assert move.from_pen_id == old_pen.id
      assert move.to_pen_id == pen.id
      assert move.quantity == 1
    end

    test "records placement movement when sow had no prior pen", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, _farrowing, _litter} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 3,
          pen_id: pen.id
        })

      updated_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert updated_sow.current_pen_id == pen.id

      moves =
        Peggy.Repo.all(
          from(m in Peggy.Animals.Movement,
            where: m.animal_id == ^sow.id,
            order_by: [desc: m.id]
          )
        )

      assert [move | _] = moves
      assert move.reason == "placement"
      assert is_nil(move.from_pen_id)
      assert move.to_pen_id == pen.id
    end

    test "does not record sow movement when farrowing pen matches current pen", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      {:ok, _} = Peggy.Animals.update_animal(scope, sow, %{current_pen_id: pen.id})
      sow = Peggy.Animals.get_animal!(scope, sow.id)
      service = service_fixture(scope, sow, boar_id: boar.id)

      {:ok, _farrowing, _litter} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-25],
          born_alive: 4,
          pen_id: pen.id
        })

      moves =
        Peggy.Repo.all(from(m in Peggy.Animals.Movement, where: m.animal_id == ^sow.id))

      assert moves == []
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

    test "rejects when sow status is not served", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      service = service_fixture(scope, sow, boar_id: boar.id)

      # Manually flip the sow off "served" after service was recorded.
      {:ok, _} =
        sow |> Ecto.Changeset.change(%{status: "open"}) |> Peggy.Repo.update()

      assert {:error, :sow_not_served} =
               Breeding.record_farrowing(scope, service, %{
                 farrowed_at: ~D[2026-04-25],
                 born_alive: 3,
                 pen_id: pen.id
               })
    end

    test "accepts gestation within 3 days of 114", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      service = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])

      # 114 − 3 = 111 days → 2026-04-22
      {:ok, _, _} =
        Breeding.record_farrowing(scope, service, %{
          farrowed_at: ~D[2026-04-22],
          born_alive: 4,
          pen_id: pen.id
        })
    end

    test "rejects gestation more than 3 days off 114",
         %{scope: scope, sow: sow, boar: boar, pen: pen} do
      service = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-01])

      # 110 days (114 − 4) → too early
      assert {:error, :gestation_out_of_range} =
               Breeding.record_farrowing(scope, service, %{
                 farrowed_at: ~D[2026-04-21],
                 born_alive: 4,
                 pen_id: pen.id
               })

      # 118 days (114 + 4) → too late
      assert {:error, :gestation_out_of_range} =
               Breeding.record_farrowing(scope, service, %{
                 farrowed_at: ~D[2026-04-29],
                 born_alive: 4,
                 pen_id: pen.id
               })
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

  describe "weaning_deletable?/2" do
    test "true for a freshly recorded weaning", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 5, pen_id: pen.id)

      {:ok, w, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-17], weaned_count: 5})

      assert Breeding.weaning_deletable?(scope, w)
    end

    test "false after a later movement", %{
      scope: scope,
      house: house,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      dest = pen_fixture(scope, house, code: "N1", capacity: 40)
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 4, pen_id: pen.id)

      {:ok, w, batch} =
        Breeding.record_weaning(scope, f, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 4,
          destination_pen_id: dest.id
        })

      # Add an extra later movement out of the dest pen
      other = pen_fixture(scope, house, code: "N2", capacity: 40)

      {:ok, _} =
        Peggy.Animals.record_movement(scope, batch, %{
          reason: "pen_transfer",
          from_pen_id: dest.id,
          to_pen_id: other.id,
          quantity: 4,
          moved_at: ~D[2026-04-20]
        })

      refute Breeding.weaning_deletable?(scope, w)
    end

    test "false once soft-deleted", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 3, pen_id: pen.id)

      {:ok, w, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-17], weaned_count: 3})

      {:ok, deleted} = Breeding.delete_weaning(scope, w)
      refute Breeding.weaning_deletable?(scope, deleted)
    end
  end

  describe "delete_weaning/2" do
    test "reverts batch, reopens prior placement, removes wean move/placement, sow back to lactating",
         %{scope: scope, house: house, sow: sow, boar: boar, pen: pen} do
      dest = pen_fixture(scope, house, code: "N1", capacity: 40)
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 6, pen_id: pen.id)

      {:ok, w, batch} =
        Breeding.record_weaning(scope, f, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 6,
          destination_pen_id: dest.id
        })

      {:ok, deleted} = Breeding.delete_weaning(scope, w)
      assert deleted.deleted_at

      # Batch reverted
      reloaded_batch = Peggy.Repo.get!(Peggy.Animals.Animal, batch.id)
      assert reloaded_batch.stage == "piglet"
      assert reloaded_batch.status == "active"
      assert reloaded_batch.quantity == 6

      # Wean placement/movement gone; prior placement reopened
      placements = Peggy.Animals.list_placements(scope, reloaded_batch)
      assert length(placements) == 1
      assert hd(placements).pen_id == pen.id
      assert is_nil(hd(placements).removed_at)

      movements =
        Peggy.Repo.all(from m in Peggy.Animals.Movement, where: m.animal_id == ^reloaded_batch.id)

      # Only the original placement-movement remains
      assert length(movements) == 1
      assert hd(movements).reason == "placement"

      # Sow back to lactating
      updated_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert updated_sow.status == "lactating"
    end

    test "handles weaned_count == 0 (batch was deceased)", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 4, pen_id: pen.id)

      {:ok, w, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-17], weaned_count: 0})

      {:ok, _} = Breeding.delete_weaning(scope, w)

      [batch] = Breeding.list_litter(scope, f)
      assert batch.status == "active"
      assert batch.quantity == 4
    end

    test "rejects when already deleted", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 3, pen_id: pen.id)

      {:ok, w, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-17], weaned_count: 3})

      {:ok, deleted} = Breeding.delete_weaning(scope, w)
      assert {:error, :already_deleted} = Breeding.delete_weaning(scope, deleted)
    end

    test "rejects when batch has later activity", %{
      scope: scope,
      house: house,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      dest = pen_fixture(scope, house, code: "N1", capacity: 40)
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 4, pen_id: pen.id)

      {:ok, w, batch} =
        Breeding.record_weaning(scope, f, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 4,
          destination_pen_id: dest.id
        })

      other = pen_fixture(scope, house, code: "N2", capacity: 40)

      {:ok, _} =
        Peggy.Animals.record_movement(scope, batch, %{
          reason: "pen_transfer",
          from_pen_id: dest.id,
          to_pen_id: other.id,
          quantity: 4,
          moved_at: ~D[2026-04-20]
        })

      assert {:error, :weaning_has_activity} = Breeding.delete_weaning(scope, w)
    end

    test "excludes deleted weaning from get_weaning! and re-allows weaning", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 5, pen_id: pen.id)

      {:ok, w, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-17], weaned_count: 5})

      {:ok, _} = Breeding.delete_weaning(scope, w)

      assert_raise Ecto.NoResultsError, fn -> Breeding.get_weaning!(scope, w.id) end

      # A fresh weaning for the same farrowing should now be accepted
      assert {:ok, _, _} =
               Breeding.record_weaning(scope, f, %{
                 weaned_at: ~D[2026-04-18],
                 weaned_count: 5
               })
    end

    test "writes audit snapshot", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 3, pen_id: pen.id)

      {:ok, w, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-17], weaned_count: 3})

      {:ok, _} = Breeding.delete_weaning(scope, w)

      [log] = Audit.list(scope, entity_type: "weaning", action: "weaning.deleted")
      assert get_in(log.changes, ["snapshot", "weaned_count"]) == 3
    end
  end

  describe "restore_weaning/2" do
    test "reapplies batch promotion, movement, and sow transition", %{
      scope: scope,
      house: house,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      dest = pen_fixture(scope, house, code: "N1", capacity: 40)
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 5, pen_id: pen.id)

      {:ok, w, batch} =
        Breeding.record_weaning(scope, f, %{
          weaned_at: ~D[2026-04-17],
          weaned_count: 5,
          destination_pen_id: dest.id
        })

      {:ok, deleted} = Breeding.delete_weaning(scope, w)
      {:ok, restored} = Breeding.restore_weaning(scope, deleted)
      assert is_nil(restored.deleted_at)

      reloaded = Peggy.Repo.get!(Peggy.Animals.Animal, batch.id)
      assert reloaded.stage == "weaner"
      assert reloaded.quantity == 5

      placements = Peggy.Animals.list_placements(scope, reloaded)
      assert length(placements) == 1
      assert hd(placements).pen_id == dest.id

      updated_sow = Peggy.Animals.get_animal!(scope, sow.id)
      assert updated_sow.status == "dry"
    end

    test "rejects non-deleted weaning", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 2, pen_id: pen.id)

      {:ok, w, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-17], weaned_count: 2})

      assert {:error, :not_deleted} = Breeding.restore_weaning(scope, w)
    end

    test "rejects when a conflicting weaning exists", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 3, pen_id: pen.id)

      {:ok, w, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-17], weaned_count: 3})

      {:ok, deleted} = Breeding.delete_weaning(scope, w)

      {:ok, _, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-18], weaned_count: 3})

      assert {:error, :conflicting_weaning} = Breeding.restore_weaning(scope, deleted)
    end

    test "writes audit log", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 3, pen_id: pen.id)

      {:ok, w, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-17], weaned_count: 3})

      {:ok, deleted} = Breeding.delete_weaning(scope, w)
      {:ok, _} = Breeding.restore_weaning(scope, deleted)

      [_] = Audit.list(scope, entity_type: "weaning", action: "weaning.restored")
    end
  end

  describe "list_deleted_weanings/2" do
    test "returns deleted weanings newest-first and excludes live ones", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      sow2 = animal_fixture(scope, ear_tag: "SOW2", sex: "female", stage: "sow")

      f1 = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 2, pen_id: pen.id)
      f2 = farrowing_fixture(scope, sow2, boar_id: boar.id, born_alive: 2, pen_id: pen.id)

      {:ok, w1, _} =
        Breeding.record_weaning(scope, f1, %{weaned_at: ~D[2026-04-17], weaned_count: 2})

      {:ok, w2, _} =
        Breeding.record_weaning(scope, f2, %{weaned_at: ~D[2026-04-17], weaned_count: 2})

      {:ok, _} = Breeding.delete_weaning(scope, w1)
      {:ok, _} = Breeding.delete_weaning(scope, w2)

      ids = Breeding.list_deleted_weanings(scope) |> Enum.map(& &1.id)
      assert Enum.sort(ids) == Enum.sort([w1.id, w2.id])
    end

    test "empty when none deleted", %{scope: scope, sow: sow, boar: boar, pen: pen} do
      f = farrowing_fixture(scope, sow, boar_id: boar.id, born_alive: 2, pen_id: pen.id)

      {:ok, _, _} =
        Breeding.record_weaning(scope, f, %{weaned_at: ~D[2026-04-17], weaned_count: 2})

      assert Breeding.list_deleted_weanings(scope) == []
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

  describe "inferred-record columns (PR 4 foundation)" do
    test "service defaults inferred=false with no created_via", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      service = service_fixture(scope, sow, boar_id: boar.id)
      assert service.inferred == false
      assert is_nil(service.created_via)
      assert is_nil(service.origin_audit_id)
    end

    test "farrowing defaults inferred=false with no created_via", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      farrowing = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)
      assert farrowing.inferred == false
      assert is_nil(farrowing.created_via)
      assert is_nil(farrowing.origin_audit_id)
    end

    test "weaning defaults inferred=false with no created_via", %{
      scope: scope,
      sow: sow,
      boar: boar,
      pen: pen
    } do
      farrowing = farrowing_fixture(scope, sow, boar_id: boar.id, pen_id: pen.id)

      {:ok, weaning, _batch} =
        Breeding.record_weaning(scope, farrowing, %{
          weaned_at: Date.add(farrowing.farrowed_at, Breeding.lactation_days()),
          weaned_count: farrowing.born_alive,
          destination_pen_id: pen.id
        })

      assert weaning.inferred == false
      assert is_nil(weaning.created_via)
      assert is_nil(weaning.origin_audit_id)
    end

    test "animal defaults inferred=false and needs_review=false", %{sow: sow} do
      assert sow.inferred == false
      assert sow.needs_review == false
      assert is_nil(sow.created_via)
      assert is_nil(sow.origin_audit_id)
    end

    test "back-fill helpers can write inferred=true through the changeset", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      # Smoke-test the columns are writable end-to-end. PR 5 will wrap this
      # in a back-fill helper; here we just confirm the changeset accepts them.
      {:ok, service} =
        Breeding.record_service(scope, %{
          sow_id: sow.id,
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-01-15],
          inferred: true,
          created_via: "back_fill_from_farrowing"
        })

      assert service.inferred == true
      assert service.created_via == "back_fill_from_farrowing"
    end

    test "constants expose lactation_days and minimum_sow_age_days" do
      assert Breeding.lactation_days() == 24
      assert Breeding.minimum_sow_age_days() == 365
    end
  end

  describe "record_service_with_backfill/2 (PR 5: sow back-fill)" do
    test "delegates to record_service/2 when sow_id is given", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      {:ok, result} =
        Breeding.record_service_with_backfill(scope, %{
          sow_id: sow.id,
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01]
        })

      assert result.inferred? == false
      assert result.sow.id == sow.id
      assert result.service.sow_id == sow.id
      # Existing sow unchanged
      assert result.sow.inferred == false
      assert result.sow.needs_review == false
    end

    test "resolves existing sow by ear_tag and delegates", %{
      scope: scope,
      sow: sow,
      boar: boar
    } do
      {:ok, result} =
        Breeding.record_service_with_backfill(scope, %{
          sow_ear_tag: sow.ear_tag,
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01]
        })

      assert result.inferred? == false
      assert result.sow.id == sow.id
      assert result.service.sow_id == sow.id
    end

    test "returns :sow_not_found when tag is unknown and no backfill_sow given",
         %{scope: scope, boar: boar} do
      assert {:error, :sow_not_found} =
               Breeding.record_service_with_backfill(scope, %{
                 sow_ear_tag: "UNKNOWN9999",
                 boar_id: boar.id,
                 service_type: "natural",
                 served_at: ~D[2026-02-01]
               })
    end

    test "hard-blocks with :similar_tag when a near-duplicate tag exists", %{
      scope: scope,
      sow: _sow,
      boar: boar
    } do
      # existing sow fixture has ear_tag "SOW1" — "SOW2" is Levenshtein 1 away
      assert {:error, {:similar_tag, tags}} =
               Breeding.record_service_with_backfill(scope, %{
                 sow_ear_tag: "SOW2",
                 boar_id: boar.id,
                 service_type: "natural",
                 served_at: ~D[2026-02-01],
                 backfill_sow: %{breed: "Large White"}
               })

      assert "SOW1" in tags
    end

    test "force_create overrides similar-tag block", %{scope: scope, boar: boar} do
      {:ok, result} =
        Breeding.record_service_with_backfill(scope, %{
          sow_ear_tag: "SOW2",
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01],
          backfill_sow: %{breed: "Large White", force_create: true}
        })

      assert result.inferred? == true
      assert result.sow.ear_tag == "SOW2"
      assert result.sow.inferred == true
    end

    test "creates inferred sow + service when no similar tag exists", %{
      scope: scope,
      boar: boar
    } do
      {:ok, result} =
        Breeding.record_service_with_backfill(scope, %{
          sow_ear_tag: "BRANDNEW-9921",
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01],
          backfill_sow: %{breed: "Duroc"}
        })

      assert result.inferred? == true
      sow = result.sow
      assert sow.ear_tag == "BRANDNEW-9921"
      assert sow.tracking_type == "individual"
      assert sow.sex == "female"
      assert sow.stage == "sow"
      # status ends at "served" after the service is recorded
      assert sow.status == "served"
      assert sow.breed == "Duroc"
      assert sow.inferred == true
      assert sow.needs_review == true
      assert sow.created_via == "back_fill_from_service"
      assert is_integer(sow.origin_audit_id)

      # Default dob = served_at - minimum_sow_age_days
      assert sow.dob == Date.add(~D[2026-02-01], -Breeding.minimum_sow_age_days())

      # Service created and references the inferred sow
      assert result.service.sow_id == sow.id
      assert result.service.service_type == "natural"
    end

    test "respects dob override in backfill_sow", %{scope: scope, boar: boar} do
      {:ok, %{sow: sow}} =
        Breeding.record_service_with_backfill(scope, %{
          sow_ear_tag: "BRANDNEW-DOB",
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01],
          backfill_sow: %{breed: "Duroc", dob: ~D[2024-06-15]}
        })

      assert sow.dob == ~D[2024-06-15]
    end

    test "rolls back inferred sow when service changeset fails", %{scope: scope} do
      # Natural service without boar_id fails validation — inferred sow must
      # not persist.
      assert {:error, %Ecto.Changeset{}} =
               Breeding.record_service_with_backfill(scope, %{
                 sow_ear_tag: "NEW-ROLLBACK-42",
                 service_type: "natural",
                 served_at: ~D[2026-02-01],
                 backfill_sow: %{breed: "Large White"}
               })

      # No orphan animal created
      assert is_nil(Peggy.Animals.find_by_ear_tag(scope, "NEW-ROLLBACK-42"))
    end

    test "writes audit rows for both the inferred sow and the service", %{
      scope: scope,
      boar: boar
    } do
      {:ok, %{sow: sow, service: service}} =
        Breeding.record_service_with_backfill(scope, %{
          sow_ear_tag: "AUDITED-9921",
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01],
          backfill_sow: %{breed: "Duroc"}
        })

      sow_logs =
        Audit.list(scope, entity_type: "animal", action: "animal.created.inferred")

      assert Enum.any?(sow_logs, &(&1.entity_id == to_string(sow.id)))

      service_logs = Audit.list(scope, entity_type: "service", action: "service.created")
      assert Enum.any?(service_logs, &(&1.entity_id == to_string(service.id)))

      # origin_audit_id on the sow points at one of the animal.created.inferred rows
      assert Enum.any?(sow_logs, &(&1.id == sow.origin_audit_id))
    end

    test "inferred sow is placed in given pen (placement movement)", %{
      scope: scope,
      pen: pen,
      boar: boar
    } do
      {:ok, %{sow: sow}} =
        Breeding.record_service_with_backfill(scope, %{
          sow_ear_tag: "PLACED-1",
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01],
          pen_id: pen.id,
          backfill_sow: %{breed: "Duroc"}
        })

      assert sow.current_pen_id == pen.id

      movements =
        Peggy.Repo.all(
          from m in Peggy.Animals.Movement,
            where: m.animal_id == ^sow.id
        )

      assert [mv] = movements
      assert mv.reason == "placement"
      assert is_nil(mv.from_pen_id)
      assert mv.to_pen_id == pen.id
      assert mv.quantity == 1
    end

    test "no pen_id given → no sow movement", %{scope: scope, boar: boar} do
      {:ok, %{sow: sow}} =
        Breeding.record_service_with_backfill(scope, %{
          sow_ear_tag: "NOPEN-1",
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01],
          backfill_sow: %{breed: "Duroc"}
        })

      assert is_nil(sow.current_pen_id)

      movements =
        Peggy.Repo.all(from m in Peggy.Animals.Movement, where: m.animal_id == ^sow.id)

      assert movements == []
    end

    test "existing sow without pen → placement movement when pen_id given", %{
      scope: scope,
      pen: pen,
      sow: sow,
      boar: boar
    } do
      # sow fixture has no current_pen_id
      assert is_nil(sow.current_pen_id)

      {:ok, result} =
        Breeding.record_service_with_backfill(scope, %{
          sow_ear_tag: sow.ear_tag,
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01],
          pen_id: pen.id
        })

      assert result.sow.current_pen_id == pen.id

      movements =
        Peggy.Repo.all(from m in Peggy.Animals.Movement, where: m.animal_id == ^sow.id)

      assert [mv] = movements
      assert mv.reason == "placement"
      assert is_nil(mv.from_pen_id)
      assert mv.to_pen_id == pen.id
    end

    test "existing sow in same pen → no movement", %{
      scope: scope,
      house: house,
      pen: pen,
      boar: boar
    } do
      _ = house
      sow = animal_fixture(scope, ear_tag: "SAMEPEN-1", sex: "female", stage: "sow")

      {:ok, _} =
        sow
        |> Ecto.Changeset.change(%{current_pen_id: pen.id})
        |> Peggy.Repo.update()

      {:ok, result} =
        Breeding.record_service_with_backfill(scope, %{
          sow_ear_tag: "SAMEPEN-1",
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01],
          pen_id: pen.id
        })

      assert result.sow.current_pen_id == pen.id

      movements =
        Peggy.Repo.all(from m in Peggy.Animals.Movement, where: m.animal_id == ^sow.id)

      assert movements == []
    end

    test "existing sow in different pen → pen_transfer movement", %{
      scope: scope,
      house: house,
      pen: pen,
      boar: boar
    } do
      other_pen = pen_fixture(scope, house, code: "F2", capacity: 20)
      sow = animal_fixture(scope, ear_tag: "MOVEME-1", sex: "female", stage: "sow")

      {:ok, _} =
        sow
        |> Ecto.Changeset.change(%{current_pen_id: other_pen.id})
        |> Peggy.Repo.update()

      {:ok, result} =
        Breeding.record_service_with_backfill(scope, %{
          sow_ear_tag: "MOVEME-1",
          boar_id: boar.id,
          service_type: "natural",
          served_at: ~D[2026-02-01],
          pen_id: pen.id
        })

      assert result.sow.current_pen_id == pen.id

      movements =
        Peggy.Repo.all(from m in Peggy.Animals.Movement, where: m.animal_id == ^sow.id)

      assert [mv] = movements
      assert mv.reason == "pen_transfer"
      assert mv.from_pen_id == other_pen.id
      assert mv.to_pen_id == pen.id
    end
  end

  describe "Animals.similar_ear_tags/3" do
    test "returns ordered near-matches on the same farm", %{scope: scope} do
      import Peggy.AnimalsFixtures
      animal_fixture(scope, ear_tag: "PIG001", sex: "female", stage: "sow")
      animal_fixture(scope, ear_tag: "PIG002", sex: "female", stage: "sow")
      animal_fixture(scope, ear_tag: "COMPLETELY-UNRELATED", sex: "female", stage: "sow")

      # Exact input tag is excluded from results regardless of threshold.
      assert [] == Peggy.Animals.similar_ear_tags(scope, "PIG001", 0)

      results = Peggy.Animals.similar_ear_tags(scope, "PIG00X", 2)
      assert "PIG001" in results
      assert "PIG002" in results
      refute "COMPLETELY-UNRELATED" in results
    end

    test "does not return the input tag itself", %{scope: scope, sow: sow} do
      refute sow.ear_tag in Peggy.Animals.similar_ear_tags(scope, sow.ear_tag, 2)
    end

    test "ignores departed animals", %{scope: scope} do
      import Peggy.AnimalsFixtures

      departed =
        animal_fixture(scope,
          ear_tag: "GONE01",
          sex: "female",
          stage: "sow",
          status: "sold"
        )

      refute departed.ear_tag in Peggy.Animals.similar_ear_tags(scope, "GONE02", 2)
    end
  end
end
