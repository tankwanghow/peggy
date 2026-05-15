defmodule Peggy.ImportsTest do
  use Peggy.DataCase, async: true

  import Peggy.AccountsFixtures
  import Peggy.FarmsFixtures
  import Peggy.LocationsFixtures
  import Peggy.AnimalsFixtures

  alias Peggy.Imports

  setup do
    user = user_fixture()
    farm = farm_fixture(user)
    scope = scope_for(user, farm)
    house = house_fixture(scope, code: "EB")
    pen = pen_fixture(scope, house, code: "12", capacity: 50)
    %{scope: scope, house: house, pen: pen}
  end

  describe "parse_and_validate/2 — sows.csv" do
    test "happy path: all rows clean", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag,breed,dob,status
        SOW001,Landrace,2024-03-15,active
        SOW002,Yorkshire,2024-05-20,open
        """)

      result = Imports.parse_and_validate(scope, %{sows: sows_path})

      assert length(result.sows.ok) == 2
      assert result.sows.warn == []
      assert result.sows.err == []
      assert result.summary.sows_importable == 2
      assert result.summary.blocking_errors == 0
    end

    test "missing required column blocks the file", %{scope: scope} do
      # No ear_tag column at all.
      sows_path =
        write_csv("""
        breed,dob
        Landrace,2024-03-15
        """)

      result = Imports.parse_and_validate(scope, %{sows: sows_path})

      assert [%{kind: :missing_columns, msg: msg}] = result.sows.err
      assert msg =~ "ear_tag"
    end

    test "blank ear_tag is a row-level error", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag,breed
        ,Landrace
        SOW001,Yorkshire
        """)

      result = Imports.parse_and_validate(scope, %{sows: sows_path})

      assert length(result.sows.ok) == 1
      assert [%{line: 2, issues: issues}] = result.sows.err
      assert Enum.any?(issues, &(&1.kind == :missing))
    end

    test "duplicate ear_tag in same CSV is an error", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag
        SOW001
        SOW001
        """)

      result = Imports.parse_and_validate(scope, %{sows: sows_path})

      assert length(result.sows.ok) == 1
      assert [%{line: 3, issues: issues}] = result.sows.err
      assert Enum.any?(issues, &(&1.kind == :duplicate))
    end

    test "bad date format is an error", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag,dob
        SOW001,2024/03/15
        """)

      result = Imports.parse_and_validate(scope, %{sows: sows_path})

      assert [%{issues: issues}] = result.sows.err
      assert Enum.any?(issues, &(&1.kind == :bad_date))
    end

    test "unknown status is an error", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag,status
        SOW001,gestating
        """)

      result = Imports.parse_and_validate(scope, %{sows: sows_path})

      assert [%{issues: issues}] = result.sows.err
      assert Enum.any?(issues, &(&1.kind == :bad_status))
    end

    test "unknown pen on movements.csv is a warning, not an error", %{scope: scope} do
      sows_path = write_csv("ear_tag\nSOW001\n")

      movements_path =
        write_csv("""
        ear_tag,moved_at,house_code,pen_code
        SOW001,2026-01-15,QQ,99
        """)

      result =
        Imports.parse_and_validate(scope, %{sows: sows_path, movements: movements_path})

      assert result.movements.ok == []
      assert [%{issues: issues}] = result.movements.warn
      assert Enum.any?(issues, &(&1.kind == :unknown_pen))
      assert result.movements.err == []
    end

    test "pen lookup is case-insensitive (movements.csv)", %{scope: scope} do
      sows_path = write_csv("ear_tag\nSOW001\n")

      movements_path =
        write_csv("""
        ear_tag,moved_at,house_code,pen_code
        SOW001,2026-01-15,eb,12
        """)

      result =
        Imports.parse_and_validate(scope, %{sows: sows_path, movements: movements_path})

      assert length(result.movements.ok) == 1
      assert result.movements.warn == []
    end

    test "headers are normalised (case + whitespace)", %{scope: scope} do
      sows_path =
        write_csv("""
        Ear_Tag, Breed
        SOW001,Landrace
        """)

      result = Imports.parse_and_validate(scope, %{sows: sows_path})

      assert length(result.sows.ok) == 1
    end

    test "missing file path is treated as empty (no error)", %{scope: scope} do
      result = Imports.parse_and_validate(scope, %{})

      assert result.sows.rows == []
      assert result.summary.sows_in == 0
    end
  end

  describe "parse_and_validate/2 — services.csv" do
    test "service for a sow defined in sows.csv resolves cleanly", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag
        SOW001
        """)

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        SOW001,2026-01-15,ai
        """)

      result =
        Imports.parse_and_validate(scope, %{sows: sows_path, services: services_path})

      assert length(result.services.ok) == 1
      assert result.services.warn == []
    end

    test "service for an unknown sow is a warning (auto-backfill)", %{scope: scope} do
      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        UNKNOWN1,2026-01-15,ai
        """)

      result = Imports.parse_and_validate(scope, %{services: services_path})

      assert [%{issues: issues}] = result.services.warn
      assert Enum.any?(issues, &(&1.kind == :unknown_sow))
    end

    test "bad service_type is an error", %{scope: scope} do
      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        SOW001,2026-01-15,laser
        """)

      result = Imports.parse_and_validate(scope, %{services: services_path})

      assert [%{issues: issues}] = result.services.err
      assert Enum.any?(issues, &(&1.kind == :bad_value))
    end

    test "missing served_at is an error", %{scope: scope} do
      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        SOW001,,ai
        """)

      result = Imports.parse_and_validate(scope, %{services: services_path})

      assert [%{issues: issues}] = result.services.err
      assert Enum.any?(issues, &(&1.kind == :missing))
    end

    test "service for an existing DB sow resolves cleanly", %{scope: scope} do
      _sow = animal_fixture(scope, ear_tag: "EXISTING", stage: "sow")

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        EXISTING,2026-01-15,ai
        """)

      result = Imports.parse_and_validate(scope, %{services: services_path})

      assert length(result.services.ok) == 1
      assert result.services.warn == []
    end
  end

  describe "parse_and_validate/2 — farrowings.csv" do
    test "happy path", %{scope: scope} do
      sows_path = write_csv("ear_tag\nSOW001\n")

      farrowings_path =
        write_csv("""
        sow_ear_tag,farrowed_at,born_alive,stillborn,mummified
        SOW001,2026-04-15,12,1,0
        """)

      result =
        Imports.parse_and_validate(scope, %{sows: sows_path, farrowings: farrowings_path})

      assert length(result.farrowings.ok) == 1
    end

    test "negative born_alive is an error", %{scope: scope} do
      farrowings_path =
        write_csv("""
        sow_ear_tag,farrowed_at,born_alive
        SOW001,2026-04-15,-3
        """)

      result = Imports.parse_and_validate(scope, %{farrowings: farrowings_path})

      assert [%{issues: issues}] = result.farrowings.err
      assert Enum.any?(issues, &(&1.kind == :bad_int))
    end
  end

  describe "parse_and_validate/2 — weanings.csv" do
    test "happy path", %{scope: scope} do
      sows_path = write_csv("ear_tag\nSOW001\n")

      weanings_path =
        write_csv("""
        sow_ear_tag,weaned_at,weaned_count
        SOW001,2026-05-15,11
        """)

      result =
        Imports.parse_and_validate(scope, %{sows: sows_path, weanings: weanings_path})

      assert length(result.weanings.ok) == 1
    end

    test "missing weaned_count is an error", %{scope: scope} do
      weanings_path =
        write_csv("""
        sow_ear_tag,weaned_at,weaned_count
        SOW001,2026-05-15,
        """)

      result = Imports.parse_and_validate(scope, %{weanings: weanings_path})

      assert [%{issues: issues}] = result.weanings.err
      assert Enum.any?(issues, &(&1.kind == :missing))
    end

    test "weaned_count = 0 is a warning; negative is an error",
         %{scope: scope} do
      weanings_path =
        write_csv("""
        sow_ear_tag,weaned_at,weaned_count
        SOW001,2026-05-15,0
        SOW002,2026-05-15,-3
        """)

      result = Imports.parse_and_validate(scope, %{weanings: weanings_path})

      assert [%{issues: warn_issues}] = result.weanings.warn
      assert Enum.any?(warn_issues, &(&1.kind == :empty_wean and &1.level == :warn))

      assert [%{issues: err_issues}] = result.weanings.err
      assert Enum.any?(err_issues, &(&1.kind == :bad_int))
    end
  end

  describe "parse_and_validate/2 — locations.csv" do
    test "happy path", %{scope: scope} do
      locations_path =
        write_csv("""
        house_code,house_purpose,pen_code,capacity
        FA,farrowing,01,12
        FA,farrowing,02,12
        DA,nursery,A1,40
        """)

      result = Imports.parse_and_validate(scope, %{locations: locations_path})

      assert length(result.locations.ok) == 3
      assert result.locations.warn == []
      assert result.locations.err == []
    end

    test "missing house_purpose is an error", %{scope: scope} do
      locations_path =
        write_csv("""
        house_code,pen_code
        FA,01
        """)

      result = Imports.parse_and_validate(scope, %{locations: locations_path})

      assert [%{kind: :missing_columns}] = result.locations.err
    end

    test "bad house_purpose enum is an error", %{scope: scope} do
      locations_path =
        write_csv("""
        house_code,house_purpose,pen_code
        FA,sleeping,01
        """)

      result = Imports.parse_and_validate(scope, %{locations: locations_path})

      assert [%{issues: issues}] = result.locations.err
      assert Enum.any?(issues, &(&1.kind == :bad_value))
    end

    test "duplicate pen+house in same CSV is an error", %{scope: scope} do
      locations_path =
        write_csv("""
        house_code,house_purpose,pen_code
        FA,farrowing,01
        FA,farrowing,01
        """)

      result = Imports.parse_and_validate(scope, %{locations: locations_path})

      assert length(result.locations.ok) == 1
      assert [%{issues: issues}] = result.locations.err
      assert Enum.any?(issues, &(&1.kind == :duplicate))
    end

    test "negative capacity is an error", %{scope: scope} do
      locations_path =
        write_csv("""
        house_code,house_purpose,pen_code,capacity
        FA,farrowing,01,-5
        """)

      result = Imports.parse_and_validate(scope, %{locations: locations_path})

      assert [%{issues: issues}] = result.locations.err
      assert Enum.any?(issues, &(&1.kind == :bad_int))
    end

    test "duplicate detection is case-insensitive on the combined key", %{scope: scope} do
      locations_path =
        write_csv("""
        house_code,house_purpose,pen_code
        fa,farrowing,01
        FA,farrowing,01
        """)

      result = Imports.parse_and_validate(scope, %{locations: locations_path})

      assert [%{issues: issues}] = result.locations.err
      assert Enum.any?(issues, &(&1.kind == :duplicate))
    end

    test "bad pen status is an error", %{scope: scope} do
      locations_path =
        write_csv("""
        house_code,house_purpose,pen_code,status
        FA,farrowing,01,broken
        """)

      result = Imports.parse_and_validate(scope, %{locations: locations_path})

      assert [%{issues: issues}] = result.locations.err
      assert Enum.any?(issues, &(&1.kind == :bad_value))
    end

    test "pens declared in locations.csv satisfy sows.csv references (no warning)", %{
      scope: scope
    } do
      locations_path =
        write_csv("""
        house_code,house_purpose,pen_code
        QQ,farrowing,99
        """)

      sows_path =
        write_csv("""
        ear_tag
        SOW001,QQ-99
        """)

      result =
        Imports.parse_and_validate(scope, %{locations: locations_path, sows: sows_path})

      assert length(result.sows.ok) == 1
      assert result.sows.warn == []
    end
  end

  describe "parse_and_validate/2 — summary aggregation" do
    test "rolls up counts and blocking errors across all files", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag
        SOW001
        SOW002
        SOW001
        """)

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        SOW001,2026-01-15,ai
        UNKNOWN,2026-01-16,ai
        SOW002,bad-date,ai
        """)

      result =
        Imports.parse_and_validate(scope, %{sows: sows_path, services: services_path})

      assert result.summary.sows_in == 3
      # 2 ok (SOW001, SOW002), 1 dup error
      assert result.summary.sows_importable == 2
      assert result.summary.sows_errors == 1

      assert result.summary.services_in == 3
      # 1 ok + 1 warn = 2 importable; 1 bad-date error
      assert result.summary.services_importable == 2
      assert result.summary.services_errors == 1

      assert result.summary.blocking_errors == 2
    end
  end

  describe "commit/2" do
    test "refuses to run when blocking errors exist", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag
        ,oops
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path})

      assert {:error, :blocking_errors} = Imports.commit(scope, report)
    end

    test "commits a clean sows.csv only run", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag,breed,dob,status
        SOW001,Landrace,2024-03-15,active
        SOW002,Yorkshire,2024-05-20,open
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path})
      assert {:ok, outcome} = Imports.commit(scope, report)

      assert outcome.sows.ok == 2
      assert outcome.sows.failed == 0
      assert outcome.run_id =~ ~r/^\d+-[a-f0-9]+$/

      # Verify rows landed and got tagged. Sows arrive pen-less; pens
      # come from movements.csv when supplied.
      assert sow1 = Peggy.Animals.find_by_ear_tag(scope, "SOW001")
      assert sow1.created_via == "csv_import:#{outcome.run_id}"
      assert is_nil(sow1.current_pen_id)
    end

    test "commits locations.csv before movements.csv so pen lookups succeed", %{scope: scope} do
      locations_path =
        write_csv("""
        house_code,house_purpose,pen_code,capacity
        FA,farrowing,01,12
        """)

      sows_path = write_csv("ear_tag\nSOW100\n")

      movements_path =
        write_csv("""
        ear_tag,moved_at,house_code,pen_code
        SOW100,2026-01-15,FA,01
        """)

      report =
        Imports.parse_and_validate(scope, %{
          locations: locations_path,
          sows: sows_path,
          movements: movements_path
        })

      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.locations.ok == 1
      assert outcome.sows.ok == 1
      assert outcome.movements.ok == 1

      sow = Peggy.Animals.find_by_ear_tag(scope, "SOW100")
      assert sow.current_pen_id != nil
    end

    test "service for an existing sow lands cleanly", %{scope: scope} do
      sows_path = write_csv("ear_tag\nSOW200\n")

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        SOW200,2026-01-15,ai
        """)

      report =
        Imports.parse_and_validate(scope, %{sows: sows_path, services: services_path})

      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.sows.ok == 1
      assert outcome.services.ok == 1
      assert outcome.services.failed == 0
    end

    test "import.run audit entry is recorded", %{scope: scope} do
      sows_path = write_csv("ear_tag\nSOW300\n")
      report = Imports.parse_and_validate(scope, %{sows: sows_path})
      assert {:ok, outcome} = Imports.commit(scope, report)

      [audit | _] = Peggy.Audit.list(scope, action: "import.run", limit: 1)
      assert audit.entity_id == outcome.run_id
      assert audit.changes["sows_ok"] == 1
    end
  end

  describe "list_runs/1 + rollback/2" do
    test "list_runs returns committed imports newest first", %{scope: scope} do
      r1 = commit_simple_import(scope, "RUN_A")
      Process.sleep(1100)
      r2 = commit_simple_import(scope, "RUN_B")

      runs = Imports.list_runs(scope)
      assert [latest, older | _] = runs
      assert latest.run_id == r2.run_id
      assert older.run_id == r1.run_id
      assert latest.counts.sows == 1
    end

    test "list_runs excludes rolled-back imports", %{scope: scope} do
      r1 = commit_simple_import(scope, "KEEP_ME")
      r2 = commit_simple_import(scope, "GONE_ME")

      assert {:ok, _} = Imports.rollback(scope, r2.run_id)

      run_ids = Imports.list_runs(scope) |> Enum.map(& &1.run_id)
      assert r1.run_id in run_ids
      refute r2.run_id in run_ids
    end

    test "rollback deletes tagged animals and logs the rollback", %{scope: scope} do
      outcome = commit_simple_import(scope, "ROLL_ME")
      assert Peggy.Animals.find_by_ear_tag(scope, "ROLL_ME")

      assert {:ok, counts} = Imports.rollback(scope, outcome.run_id)
      assert counts.animals == 1
      assert counts.services == 0
      refute Peggy.Animals.find_by_ear_tag(scope, "ROLL_ME")

      [audit | _] = Peggy.Audit.list(scope, action: "import.rollback", limit: 1)
      assert audit.entity_id == outcome.run_id
      assert audit.changes["animals"] == 1
    end

    test "rollback also removes services / farrowings / weanings", %{scope: scope} do
      sows_path = write_csv("ear_tag\nSOW_FULL\n")

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        SOW_FULL,2026-01-15,ai
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path, services: services_path})
      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.services.ok == 1

      assert {:ok, counts} = Imports.rollback(scope, outcome.run_id)
      assert counts.services == 1
      assert counts.animals == 1
    end

    test "rollback for unknown run_id returns zero counts (no error)", %{scope: scope} do
      assert {:ok, counts} = Imports.rollback(scope, "does-not-exist")

      assert counts == %{weanings: 0, farrowings: 0, services: 0, movements: 0, animals: 0}
    end
  end

  describe "commit/2 — service ↔ farrowing ↔ weaning matching" do
    test "farrowing attaches to existing service from services.csv (no duplicate)", %{
      scope: scope
    } do
      sows_path =
        write_csv("""
        ear_tag
        MATCH1
        """)

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        MATCH1,2026-01-01,ai
        """)

      farrowings_path =
        write_csv("""
        sow_ear_tag,farrowed_at,born_alive,pen
        MATCH1,2026-04-25,11,EB-12
        """)

      report =
        Imports.parse_and_validate(scope, %{
          sows: sows_path,
          services: services_path,
          farrowings: farrowings_path
        })

      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.services.ok == 1
      assert outcome.farrowings.ok == 1

      sow = Peggy.Animals.find_by_ear_tag(scope, "MATCH1")

      services =
        Peggy.Repo.all(Ecto.Query.from(s in Peggy.Breeding.Service, where: s.sow_id == ^sow.id))

      farrowings =
        Peggy.Repo.all(Ecto.Query.from(f in Peggy.Breeding.Farrowing, where: f.sow_id == ^sow.id))

      # One service (closed by the farrowing), one farrowing.
      assert length(services) == 1
      assert length(farrowings) == 1
      assert hd(services).result == "farrowing"
      assert hd(farrowings).service_id == hd(services).id
    end

    test "weaning attaches to existing farrowing from farrowings.csv", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag
        MATCH2
        """)

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        MATCH2,2026-01-01,ai
        """)

      farrowings_path =
        write_csv("""
        sow_ear_tag,farrowed_at,born_alive,pen
        MATCH2,2026-04-25,10,EB-12
        """)

      weanings_path =
        write_csv("""
        sow_ear_tag,weaned_at,weaned_count
        MATCH2,2026-05-19,9
        """)

      report =
        Imports.parse_and_validate(scope, %{
          sows: sows_path,
          services: services_path,
          farrowings: farrowings_path,
          weanings: weanings_path
        })

      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.services.ok == 1
      assert outcome.farrowings.ok == 1
      assert outcome.weanings.ok == 1

      sow = Peggy.Animals.find_by_ear_tag(scope, "MATCH2")

      services =
        Peggy.Repo.all(Ecto.Query.from(s in Peggy.Breeding.Service, where: s.sow_id == ^sow.id))

      farrowings =
        Peggy.Repo.all(Ecto.Query.from(f in Peggy.Breeding.Farrowing, where: f.sow_id == ^sow.id))

      weanings =
        Peggy.Repo.all(
          Ecto.Query.from(w in Peggy.Breeding.Weaning,
            where: w.farrowing_id in ^Enum.map(farrowings, & &1.id)
          )
        )

      assert length(services) == 1
      assert length(farrowings) == 1
      assert length(weanings) == 1
      assert hd(weanings).farrowing_id == hd(farrowings).id
    end

    test "two cycles for same sow: prior service closes as farrowing, second remains open", %{
      scope: scope
    } do
      sows_path =
        write_csv("""
        ear_tag
        CYCLES
        """)

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        CYCLES,2026-01-01,ai
        CYCLES,2026-06-10,ai
        """)

      farrowings_path =
        write_csv("""
        sow_ear_tag,farrowed_at,born_alive,pen
        CYCLES,2026-04-25,12,EB-12
        """)

      weanings_path =
        write_csv("""
        sow_ear_tag,weaned_at,weaned_count
        CYCLES,2026-05-19,11
        """)

      report =
        Imports.parse_and_validate(scope, %{
          sows: sows_path,
          services: services_path,
          farrowings: farrowings_path,
          weanings: weanings_path
        })

      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.services.ok == 2
      assert outcome.farrowings.ok == 1
      assert outcome.weanings.ok == 1

      sow = Peggy.Animals.find_by_ear_tag(scope, "CYCLES")

      services =
        Peggy.Repo.all(
          Ecto.Query.from(s in Peggy.Breeding.Service,
            where: s.sow_id == ^sow.id,
            order_by: [asc: s.served_at]
          )
        )

      assert length(services) == 2
      [first, second] = services
      # First service closed by the farrowing, NOT auto-classified as re_service.
      assert first.result == "farrowing"
      # Second service is open (no later event to close it).
      assert second.result == nil
    end

    test "auto re_service: two services >7d apart with no farrowing between", %{scope: scope} do
      sows_path = write_csv("ear_tag\nRESERV1\n")

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        RESERV1,2026-01-01,ai
        RESERV1,2026-01-22,ai
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path, services: services_path})
      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.services.ok == 2

      sow = Peggy.Animals.find_by_ear_tag(scope, "RESERV1")

      services =
        Peggy.Repo.all(
          Ecto.Query.from(s in Peggy.Breeding.Service,
            where: s.sow_id == ^sow.id,
            order_by: [asc: s.served_at]
          )
        )

      assert length(services) == 2
      [first, second] = services
      assert first.result == "re_service"
      assert second.result == nil
    end

    test "two services within 7d collapse into a single row (mounting_count bumped)", %{
      scope: scope
    } do
      sows_path = write_csv("ear_tag\nCOLL1\n")

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        COLL1,2026-01-01,ai
        COLL1,2026-01-04,ai
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path, services: services_path})
      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.services.ok == 2

      sow = Peggy.Animals.find_by_ear_tag(scope, "COLL1")

      services =
        Peggy.Repo.all(Ecto.Query.from(s in Peggy.Breeding.Service, where: s.sow_id == ^sow.id))

      assert [service] = services
      assert service.mounting_count == 2
      assert service.last_serviced_at == ~D[2026-01-04]
    end

    test "explicit result=re_service is treated as a hint — auto-resolver closes it on next service",
         %{scope: scope} do
      sows_path = write_csv("ear_tag\nHIST1\n")

      # Explicit `result=re_service` on the first row is dropped; the
      # second row triggers the auto-close with result_at=its served_at.
      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type,result,result_at
        HIST1,2026-01-01,ai,re_service,2026-01-22
        HIST1,2026-01-22,ai,,
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path, services: services_path})
      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.services.ok == 2

      sow = Peggy.Animals.find_by_ear_tag(scope, "HIST1")

      services =
        Peggy.Repo.all(
          Ecto.Query.from(s in Peggy.Breeding.Service,
            where: s.sow_id == ^sow.id,
            order_by: [asc: s.served_at]
          )
        )

      assert [first, second] = services
      assert first.result == "re_service"
      assert first.result_at == ~D[2026-01-22]
      assert second.result == nil
    end

    test "explicit result=farrowing is treated as a hint — farrowings.csv closes the service",
         %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag
        HINT2
        """)

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type,result,result_at
        HINT2,2026-01-01,ai,farrowing,2026-04-25
        """)

      farrowings_path =
        write_csv("""
        sow_ear_tag,farrowed_at,born_alive,pen
        HINT2,2026-04-25,10,EB-12
        """)

      report =
        Imports.parse_and_validate(scope, %{
          sows: sows_path,
          services: services_path,
          farrowings: farrowings_path
        })

      # No collision warning — the result hint is dropped silently.
      assert report.services.warn == []
      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.services.ok == 1
      assert outcome.farrowings.ok == 1

      sow = Peggy.Animals.find_by_ear_tag(scope, "HINT2")

      [service] =
        Peggy.Repo.all(Ecto.Query.from(s in Peggy.Breeding.Service, where: s.sow_id == ^sow.id))

      assert service.result == "farrowing"
      assert service.result_at == ~D[2026-04-25]

      [farrowing] =
        Peggy.Repo.all(Ecto.Query.from(f in Peggy.Breeding.Farrowing, where: f.sow_id == ^sow.id))

      assert farrowing.service_id == service.id
    end

    test "explicit result=abortion is honored as a pre-closed historic row", %{scope: scope} do
      sows_path = write_csv("ear_tag\nABORT1\n")

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type,result,result_at
        ABORT1,2026-01-01,ai,abortion,2026-02-15
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path, services: services_path})
      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.services.ok == 1

      sow = Peggy.Animals.find_by_ear_tag(scope, "ABORT1")

      [service] =
        Peggy.Repo.all(Ecto.Query.from(s in Peggy.Breeding.Service, where: s.sow_id == ^sow.id))

      assert service.result == "abortion"
      assert service.result_at == ~D[2026-02-15]
    end

    test "result_at earlier than served_at falls back to served_at", %{scope: scope} do
      sows_path = write_csv("ear_tag\nLEGACY1\n")

      # Legacy CSV exports the prior-event date in result_at; the value
      # is before served_at and would otherwise fail the changeset.
      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type,result,result_at
        LEGACY1,2026-01-01,ai,abortion,2025-09-01
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path, services: services_path})
      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.services.ok == 1

      sow = Peggy.Animals.find_by_ear_tag(scope, "LEGACY1")

      [service] =
        Peggy.Repo.all(Ecto.Query.from(s in Peggy.Breeding.Service, where: s.sow_id == ^sow.id))

      assert service.result_at == ~D[2026-01-01]
    end
  end

  describe "culls.csv" do
    test "parse_and_validate flags missing ear_tag, bad date, bad reason", %{scope: scope} do
      culls_path =
        write_csv("""
        ear_tag,culled_at,reason
        ,2026-01-01,cull
        S1,bad-date,cull
        S1,2026-01-01,leftforanotherfarm
        """)

      result = Imports.parse_and_validate(scope, %{culls: culls_path})

      assert length(result.culls.err) == 3
      assert result.summary.culls_errors == 3
    end

    test "unknown sow is a warning (skipped at commit)", %{scope: scope} do
      culls_path =
        write_csv("""
        ear_tag,culled_at
        GHOST,2026-01-01
        """)

      result = Imports.parse_and_validate(scope, %{culls: culls_path})

      assert [%{issues: issues}] = result.culls.warn
      assert Enum.any?(issues, &(&1.kind == :unknown_sow))
    end

    test "duplicate ear_tag in culls.csv is an error", %{scope: scope} do
      culls_path =
        write_csv("""
        ear_tag,culled_at
        DUP,2026-01-01
        DUP,2026-02-01
        """)

      result = Imports.parse_and_validate(scope, %{culls: culls_path})

      assert [%{line: 3, issues: issues}] = result.culls.err
      assert Enum.any?(issues, &(&1.kind == :duplicate))
    end

    test "commit closes the open service as cull and marks sow culled", %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag
        OUT1
        """)

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        OUT1,2026-01-01,ai
        """)

      culls_path =
        write_csv("""
        ear_tag,culled_at,reason
        OUT1,2026-02-15,cull
        """)

      report =
        Imports.parse_and_validate(scope, %{
          sows: sows_path,
          services: services_path,
          culls: culls_path
        })

      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.culls.ok == 1

      sow = Peggy.Animals.find_by_ear_tag(scope, "OUT1")
      assert sow.status == "culled"

      [service] =
        Peggy.Repo.all(Ecto.Query.from(s in Peggy.Breeding.Service, where: s.sow_id == ^sow.id))

      assert service.result == "cull"
      assert service.result_at == ~D[2026-02-15]
    end

    test "reason=death closes service with result=death and sets sow status=deceased", %{
      scope: scope
    } do
      sows_path = write_csv("ear_tag\nDEAD1\n")

      services_path =
        write_csv("""
        sow_ear_tag,served_at,service_type
        DEAD1,2026-01-01,ai
        """)

      culls_path =
        write_csv("""
        ear_tag,culled_at,reason
        DEAD1,2026-01-20,death
        """)

      report =
        Imports.parse_and_validate(scope, %{
          sows: sows_path,
          services: services_path,
          culls: culls_path
        })

      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.culls.ok == 1

      sow = sow_by_tag_any_status(scope, "DEAD1")
      assert sow.status == "deceased"

      [service] =
        Peggy.Repo.all(Ecto.Query.from(s in Peggy.Breeding.Service, where: s.sow_id == ^sow.id))

      assert service.result == "death"
    end

    test "cull with no open service still updates sow status", %{scope: scope} do
      sows_path = write_csv("ear_tag\nNOSVC\n")

      culls_path =
        write_csv("""
        ear_tag,culled_at,reason
        NOSVC,2026-02-01,sold
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path, culls: culls_path})

      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.culls.ok == 1

      sow = sow_by_tag_any_status(scope, "NOSVC")
      assert sow.status == "sold"
    end

    test "departure reasons (sold/slaughtered/transferred/death) record a movement",
         %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag
        SELL1
        SLAY1
        XFER1
        DEAD2
        """)

      culls_path =
        write_csv("""
        ear_tag,culled_at,reason
        SELL1,2026-02-01,sold
        SLAY1,2026-02-02,slaughtered
        XFER1,2026-02-03,transferred
        DEAD2,2026-02-04,death
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path, culls: culls_path})

      assert {:ok, outcome} = Imports.commit(scope, report)
      assert outcome.culls.ok == 4

      cases = [
        {"SELL1", "sold", "sale", ~D[2026-02-01]},
        {"SLAY1", "slaughtered", "slaughter", ~D[2026-02-02]},
        {"XFER1", "transferred", "farm_transfer", ~D[2026-02-03]},
        {"DEAD2", "deceased", "death", ~D[2026-02-04]}
      ]

      for {tag, expected_status, expected_reason, expected_date} <- cases do
        sow = sow_by_tag_any_status(scope, tag)
        assert sow.status == expected_status
        assert is_nil(sow.current_pen_id)

        [movement] =
          Peggy.Repo.all(
            Ecto.Query.from(m in Peggy.Animals.Movement,
              where: m.animal_id == ^sow.id and m.reason == ^expected_reason
            )
          )

        assert movement.moved_at == expected_date
        assert movement.previous_status == "active"
      end
    end

    test "reason=cull (default) does NOT create a movement",
         %{scope: scope} do
      sows_path =
        write_csv("""
        ear_tag
        MARK1
        """)

      culls_path =
        write_csv("""
        ear_tag,culled_at,reason
        MARK1,2026-02-01,cull
        """)

      report = Imports.parse_and_validate(scope, %{sows: sows_path, culls: culls_path})
      assert {:ok, _} = Imports.commit(scope, report)

      sow = sow_by_tag_any_status(scope, "MARK1")
      assert sow.status == "culled"

      movements =
        Peggy.Repo.all(
          Ecto.Query.from(m in Peggy.Animals.Movement, where: m.animal_id == ^sow.id)
        )

      assert movements == []
    end

    test "cull for unknown sow is recorded as failed with sow_not_found", %{scope: scope} do
      culls_path =
        write_csv("""
        ear_tag,culled_at
        GHOST,2026-01-01
        """)

      report = Imports.parse_and_validate(scope, %{culls: culls_path})
      assert {:ok, outcome} = Imports.commit(scope, report)

      assert outcome.culls.ok == 0
      assert outcome.culls.failed == 1
    end
  end

  defp sow_by_tag_any_status(%{farm: farm}, ear_tag) do
    Peggy.Repo.one(
      Ecto.Query.from(a in Peggy.Animals.Animal,
        where: a.farm_id == ^farm.id and a.ear_tag == ^ear_tag
      )
    )
  end

  defp commit_simple_import(scope, ear_tag) do
    sows_path = write_csv("ear_tag\n#{ear_tag}\n")
    report = Imports.parse_and_validate(scope, %{sows: sows_path})
    {:ok, outcome} = Imports.commit(scope, report)
    outcome
  end

  describe "parse_and_validate/2 — file-level errors" do
    test "missing file path on disk surfaces a single error", %{scope: scope} do
      result =
        Imports.parse_and_validate(scope, %{
          sows: "/tmp/does-not-exist-#{System.unique_integer()}.csv"
        })

      assert [%{kind: :missing_file}] = result.sows.err
    end

    test "completely empty CSV surfaces an error", %{scope: scope} do
      sows_path = write_csv("")
      result = Imports.parse_and_validate(scope, %{sows: sows_path})

      assert [%{kind: :empty}] = result.sows.err
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp write_csv(contents) do
    path = Path.join(System.tmp_dir!(), "imports_test_#{System.unique_integer([:positive])}.csv")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
