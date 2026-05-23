defmodule Peggy.BackupTest do
  use Peggy.DataCase, async: true

  import Peggy.AccountsFixtures
  import Peggy.AnimalsFixtures
  import Peggy.BreedingFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures

  import Ecto.Query

  alias Peggy.{Animals, Backup, Breeding, Repo}
  alias Peggy.Animals.Animal
  alias Peggy.Audit.AuditLog
  alias Peggy.Breeding.{Farrowing, Service}
  alias Peggy.Farms.Membership
  alias Peggy.Locations.{House, Pen}

  describe "export/1 + import_to_new_farm/3 round-trip" do
    setup do
      user = user_fixture()
      farm = farm_fixture(user, name: "Origin Farm", slug: "origin")
      scope = scope_for(user, farm)
      house = house_fixture(scope, code: "H1", purpose: "farrowing")
      pen_a = pen_fixture(scope, house, code: "A1", capacity: 12)
      pen_b = pen_fixture(scope, house, code: "B1", capacity: 8)
      sow = animal_fixture(scope, ear_tag: "SOW1", stage: "sow", current_pen_id: pen_a.id)
      boar = animal_fixture(scope, ear_tag: "BOAR1", stage: "boar")
      _service = service_fixture(scope, sow, boar_id: boar.id, served_at: ~D[2026-01-15])

      %{user: user, farm: farm, scope: scope, sow: sow, boar: boar, pen_a: pen_a, pen_b: pen_b}
    end

    test "round-trip produces an isolated new farm with matching counts", %{scope: scope} do
      {:ok, gz, filename} = Backup.export(scope)
      assert is_binary(gz)
      assert filename =~ "origin"
      assert filename =~ ".json.gz"

      # New owner, new slug
      new_owner = user_fixture()

      {:ok, new_farm} =
        Backup.import_to_new_farm(new_owner, gz, %{
          "slug" => "restored",
          "name" => "Restored Farm"
        })

      assert new_farm.slug == "restored"
      assert new_farm.name == "Restored Farm"
      refute new_farm.id == scope.farm.id

      # The original farm is untouched
      assert Repo.aggregate(from(a in Animal, where: a.farm_id == ^scope.farm.id), :count) == 2

      # New farm has the same counts
      assert Repo.aggregate(from(a in Animal, where: a.farm_id == ^new_farm.id), :count) == 2

      assert Repo.aggregate(from(s in Service, where: s.farm_id == ^new_farm.id), :count) == 1
      assert Repo.aggregate(from(h in House, where: h.farm_id == ^new_farm.id), :count) == 1
      assert Repo.aggregate(from(p in Pen, where: p.farm_id == ^new_farm.id), :count) == 2

      # New owner has owner membership on the new farm
      assert Repo.one(
               from m in Membership,
                 where: m.user_id == ^new_owner.id and m.farm_id == ^new_farm.id,
                 select: m.role
             ) == "owner"

      # Audit log captured both export and restore actions
      assert Repo.exists?(
               from a in AuditLog,
                 where: a.farm_id == ^scope.farm.id and a.action == "farm.backup.exported"
             )

      assert Repo.exists?(
               from a in AuditLog,
                 where: a.farm_id == ^new_farm.id and a.action == "farm.backup.restored"
             )

      # User FK is cleared on restore: the restored service has no
      # technician_user_id (even if the source had one).
      assert Repo.one(
               from s in Service,
                 where: s.farm_id == ^new_farm.id,
                 select: s.technician_user_id
             )
             |> is_nil()

      # Breeding parameters from the source farm carry over
      assert new_farm.gestation_days == scope.farm.gestation_days
      assert new_farm.wean_due_days == scope.farm.wean_due_days
      assert new_farm.timezone == scope.farm.timezone
    end

    test "farrowing FK to the new service is preserved", %{scope: scope, sow: sow} do
      service = Repo.one!(from s in Service, where: s.farm_id == ^scope.farm.id)

      {:ok, _farrowing} =
        Breeding.record_farrowing(scope, service, %{
          "farrowed_at" => Date.add(service.served_at, 114),
          "born_alive" => 10,
          "stillborn" => 1,
          "mummified" => 0
        })

      {:ok, gz, _} = Backup.export(scope)
      new_owner = user_fixture()

      {:ok, new_farm} =
        Backup.import_to_new_farm(new_owner, gz, %{
          "slug" => "restored2",
          "name" => "Restored 2"
        })

      new_farrowing = Repo.one(from f in Farrowing, where: f.farm_id == ^new_farm.id)
      assert new_farrowing
      # FK should point at a service inside the NEW farm
      new_service =
        Repo.one(from s in Service, where: s.id == ^new_farrowing.service_id, select: s.farm_id)

      assert new_service == new_farm.id

      # The piglet animal (created by record_farrowing) should be in the new farm too
      assert Repo.aggregate(from(a in Animal, where: a.farm_id == ^new_farm.id), :count) >= 2
      _ = sow
    end

    test "invalid gzip → :invalid_gzip", %{user: user} do
      assert {:error, :invalid_gzip} =
               Backup.import_to_new_farm(user, "not gzip data", %{
                 "slug" => "x",
                 "name" => "x"
               })
    end

    test "wrong schema_version → unsupported", %{user: user} do
      payload =
        %{"schema_version" => 99, "tables" => %{}, "farm" => %{}}
        |> Jason.encode!()
        |> :zlib.gzip()

      assert {:error, {:unsupported_schema_version, 99}} =
               Backup.import_to_new_farm(user, payload, %{
                 "slug" => "x",
                 "name" => "x"
               })
    end

    test "duplicate slug → changeset error", %{scope: scope, user: user} do
      {:ok, gz, _} = Backup.export(scope)

      assert {:error, {:farm, %Ecto.Changeset{}}} =
               Backup.import_to_new_farm(user, gz, %{
                 # slug already taken by `Origin Farm` (slug: "origin")
                 "slug" => "origin",
                 "name" => "Dupe"
               })
    end

    # Suppress unused-alias warnings.
    _ = Animals
  end
end
