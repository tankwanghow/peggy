defmodule Peggy.Breeding do
  @moduledoc """
  Breeding & reproduction: services, farrowings, weanings.

  Every function takes a `%Scope{}` and enforces `farm_id` isolation.
  Mutations write `audit_logs` rows in the same transaction.

  ## Service result lifecycle

  A service starts with `result = nil` (open — sow is gestating).
  The result is set when the outcome is known:

  * `farrowing` — sow gave birth (set by `record_farrowing/3`)
  * `re_service` — sow returned to heat (auto-set when a new service
    is recorded for the same sow)
  * `abortion` — pregnancy terminated early
  * `death` — sow died during gestation
  * `cull` — sow culled during gestation

  When `result IS NULL`, the sow is considered currently gestating.
  Expected farrowing date is computed as `served_at + 114 days`.
  """

  import Ecto.Query
  alias Ecto.Multi
  alias Peggy.{Repo, Audit}
  alias Peggy.Accounts.Scope
  alias Peggy.Animals.Animal
  alias Peggy.Breeding.{Service, Farrowing, Weaning}
  alias Peggy.Animals.{Movement, Placement}

  @gestation_days 114

  def gestation_days, do: @gestation_days

  # ── Services ──────────────────────────────────────────────────────

  @doc """
  Records a breeding service for a sow.

  If the sow already has an open service (result IS NULL), the previous
  one is auto-closed with `result = re_service`.
  """
  def record_service(%Scope{} = scope, attrs) do
    farm = scope.farm
    attrs = Map.put(attrs, "farm_id", farm.id) |> stringify_keys()

    multi =
      Multi.new()
      |> ensure_sow_serviceable(scope, attrs)
      |> auto_close_prior_service(scope, attrs)
      |> Multi.insert(:service, Service.changeset(%Service{}, attrs))
      |> update_sow_status(attrs["sow_id"], "served")
      |> audit_after(scope, "service.created", :service)

    case Repo.transaction(multi) do
      {:ok, %{service: service}} -> {:ok, service}
      {:error, :service, cs, _} -> {:error, cs}
      {:error, :ensure_serviceable, cs, _} -> {:error, cs}
      {:error, step, cs, _} -> {:error, {step, cs}}
    end
  end

  @doc """
  Records multiple services atomically (batch entry from spreadsheet grid).

  Each entry is a map with `:sow_id`, `:boar_id`, `:service_type`,
  `:served_at`, `:notes`. Keys may be atoms or strings.

  Returns `{:ok, [service, ...]}` on success,
  `{:error, {row_index, changeset}}` on failure.
  Any failure rolls back the entire batch.
  """
  def record_batch_services(%Scope{} = scope, entries)
      when is_list(entries) and entries != [] do
    farm = scope.farm

    multi =
      entries
      |> Enum.with_index()
      |> Enum.reduce(Multi.new(), fn {entry, i}, m ->
        attrs =
          entry
          |> stringify_keys()
          |> Map.put("farm_id", farm.id)

        m
        |> ensure_sow_serviceable_keyed(scope, attrs, i)
        |> auto_close_prior_service_keyed(scope, attrs, i)
        |> Multi.insert({:service, i}, Service.changeset(%Service{}, attrs))
        |> update_sow_status_keyed(attrs["sow_id"], "served", i)
        |> audit_after_keyed(scope, "service.created", {:service, i}, i)
      end)

    case Repo.transaction(multi) do
      {:ok, changes} ->
        services =
          0..(length(entries) - 1)
          |> Enum.map(&Map.fetch!(changes, {:service, &1}))

        {:ok, services}

      {:error, {:service, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, {:ensure_serviceable, i}, cs, _} ->
        {:error, {i, cs}}

      {:error, _op, reason, _} ->
        {:error, reason}
    end
  end

  def record_batch_services(_scope, []), do: {:error, :no_entries}

  # Reject services for sows that aren't biologically eligible:
  # only `active`, `open`, `dry`, or `served` (re-service via auto-close)
  # are allowed. `lactating`, `culled`, and departed statuses error out
  # with a changeset error rather than silently moving the sow to "served".
  @serviceable_for_new_service ~w(active open dry served)

  defp ensure_sow_serviceable(multi, scope, attrs) do
    sow_id = to_int(attrs["sow_id"])

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, :ensure_serviceable, fn repo, _ ->
        check_sow_serviceable(repo, scope, sow_id, attrs)
      end)
    end
  end

  defp ensure_sow_serviceable_keyed(multi, scope, attrs, i) do
    sow_id = to_int(attrs["sow_id"])

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, {:ensure_serviceable, i}, fn repo, _ ->
        check_sow_serviceable(repo, scope, sow_id, attrs)
      end)
    end
  end

  defp check_sow_serviceable(repo, scope, sow_id, attrs) do
    case repo.get(Animal, sow_id) do
      nil ->
        cs =
          %Service{}
          |> Service.changeset(attrs)
          |> Ecto.Changeset.add_error(:sow_id, "does not exist")

        {:error, cs}

      %Animal{farm_id: fid} when fid != scope.farm.id ->
        cs =
          %Service{}
          |> Service.changeset(attrs)
          |> Ecto.Changeset.add_error(:sow_id, "does not exist")

        {:error, cs}

      %Animal{status: status} = sow when status in @serviceable_for_new_service ->
        {:ok, sow}

      %Animal{status: status} ->
        cs =
          %Service{}
          |> Service.changeset(attrs)
          |> Ecto.Changeset.add_error(
            :sow_id,
            "cannot service a sow with status \"#{status}\""
          )

        {:error, cs}
    end
  end

  # Keyed variant of auto_close_prior_service for batch entry
  defp auto_close_prior_service_keyed(multi, scope, attrs, i) do
    sow_id = to_int(attrs["sow_id"])

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, {:close_prior, i}, fn repo, _ ->
        case repo.one(
               from(s in Service,
                 where:
                   s.farm_id == ^scope.farm.id and
                     s.sow_id == ^sow_id and
                     is_nil(s.result),
                 lock: "FOR UPDATE"
               )
             ) do
          nil ->
            {:ok, nil}

          prior ->
            result_at = attrs["served_at"] || to_string(Date.utc_today())

            prior
            |> Service.close_changeset(%{"result" => "re_service", "result_at" => result_at})
            |> repo.update()
        end
      end)
      |> Multi.run({:audit_close_prior, i}, fn _repo, changes ->
        prior = Map.get(changes, {:close_prior, i})

        if prior do
          Audit.log_now!(scope, "service.closed",
            entity_type: :service,
            entity_id: prior.id
          )
        end

        {:ok, nil}
      end)
    end
  end

  defp audit_after_keyed(multi, scope, action, key, i) do
    Multi.run(multi, {:audit, action, i}, fn _repo, changes ->
      row = Map.fetch!(changes, key)

      Audit.log_now!(scope, action,
        entity_type: :service,
        entity_id: row.id
      )

      {:ok, :logged}
    end)
  end

  # Auto-close any prior open service for the same sow.
  defp auto_close_prior_service(multi, scope, attrs) do
    sow_id = to_int(attrs["sow_id"])

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, :close_prior, fn repo, _ ->
        case repo.one(
               from(s in Service,
                 where:
                   s.farm_id == ^scope.farm.id and
                     s.sow_id == ^sow_id and
                     is_nil(s.result),
                 lock: "FOR UPDATE"
               )
             ) do
          nil ->
            {:ok, nil}

          prior ->
            result_at = attrs["served_at"] || to_string(Date.utc_today())

            prior
            |> Service.close_changeset(%{"result" => "re_service", "result_at" => result_at})
            |> repo.update()
        end
      end)
      |> Multi.run(:audit_close_prior, fn _repo, %{close_prior: prior} ->
        if prior do
          Audit.log_now!(scope, "service.closed",
            entity_type: :service,
            entity_id: prior.id
          )
        end

        {:ok, nil}
      end)
    end
  end

  @doc """
  Closes an open service with a result (abortion, death, cull).

  Use `record_farrowing/3` instead when the result is a farrowing.

  For death/cull, a departure movement is recorded and the sow's status
  is set via the movement system (deceased/sold). For abortion, the sow
  returns to `active`.
  """
  @sow_departure_statuses %{
    "death" => "deceased",
    "cull" => "sold"
  }

  @sow_departure_reasons %{
    "death" => "death",
    "cull" => "sale"
  }

  def close_service(%Scope{} = scope, %Service{} = service, result, attrs \\ %{}) do
    if service.result do
      {:error, :already_closed}
    else
      attrs =
        attrs
        |> stringify_keys()
        |> Map.merge(%{"result" => result})

      multi =
        Multi.new()
        |> Multi.update(:service, Service.close_changeset(service, attrs))
        |> handle_sow_after_close(scope, service.sow_id, result, attrs)
        |> audit_after(scope, "service.closed", :service)

      case Repo.transaction(multi) do
        {:ok, %{service: service}} -> {:ok, service}
        {:error, :service, cs, _} -> {:error, cs}
      end
    end
  end

  # Sow becomes "open" after abortion — ready to be re-served
  defp handle_sow_after_close(multi, _scope, sow_id, "abortion", _attrs) do
    Multi.run(multi, :update_sow, fn _repo, _ ->
      sow = Repo.get!(Animal, sow_id)
      sow |> Ecto.Changeset.change(%{status: "open"}) |> Repo.update()
    end)
  end

  # Sow departs via death or cull — record departure movement
  defp handle_sow_after_close(multi, scope, sow_id, result, attrs)
       when result in ["death", "cull"] do
    Multi.run(multi, :depart_sow, fn _repo, _ ->
      sow = Repo.get!(Animal, sow_id)
      reason = Map.fetch!(@sow_departure_reasons, result)
      moved_at = attrs["result_at"] || to_string(Date.utc_today())

      with {:ok, _movement} <-
             Repo.insert(
               Movement.changeset(%Movement{}, %{
                 "farm_id" => scope.farm.id,
                 "animal_id" => sow.id,
                 "from_pen_id" => sow.current_pen_id,
                 "reason" => reason,
                 "quantity" => 1,
                 "moved_at" => moved_at,
                 "previous_status" => sow.status
               })
             ) do
        status = Map.fetch!(@sow_departure_statuses, result)
        sow |> Ecto.Changeset.change(%{status: status, current_pen_id: nil}) |> Repo.update()
      end
    end)
  end

  defp handle_sow_after_close(multi, _scope, _sow_id, _result, _attrs), do: multi

  @doc """
  Returns the current open service for a sow, or nil.
  """
  def current_service(%Scope{farm: farm}, sow_id) do
    Repo.one(
      from(s in Service,
        where: s.farm_id == ^farm.id and s.sow_id == ^sow_id and is_nil(s.result),
        order_by: [desc: s.served_at, desc: s.id],
        limit: 1,
        preload: [:sow, :boar]
      )
    )
  end

  @doc """
  Lists all services for a farm, newest first.
  Supports optional filters: `sow_id`, `result`.
  """
  def list_services(%Scope{farm: farm}, opts \\ []) do
    from(s in Service,
      where: s.farm_id == ^farm.id,
      order_by: [desc: s.served_at, desc: s.id],
      preload: [:sow, :boar]
    )
    |> maybe_filter_service(:sow_id, Keyword.get(opts, :sow_id))
    |> maybe_filter_service(:result, Keyword.get(opts, :result))
    |> Repo.all()
  end

  @doc """
  Lists services for a specific sow, newest first.
  """
  def list_services_for_sow(%Scope{} = scope, sow_id) do
    list_services(scope, sow_id: sow_id)
  end

  @doc """
  Gets a service by id, scoped to the farm.
  """
  def get_service!(%Scope{farm: farm}, id) do
    Repo.get_by!(Service, id: id, farm_id: farm.id)
    |> Repo.preload([:sow, :boar, farrowing: [:weaning]])
  end

  @doc """
  Returns a changeset for tracking service form changes.
  """
  def change_service(%Service{} = service, attrs \\ %{}) do
    Service.changeset(service, attrs)
  end

  # ── Gestating sows (read helpers) ──────────────────────────────────

  @doc """
  Lists sows currently gestating (services with `result IS NULL`).

  Options:
    * `:search` — case-insensitive ear-tag prefix (matches sow ear tag)
    * `:due_window` — `"all"` (default) | `"7"` | `"14"` | `"overdue"`
    * `:service_type` — `"all"` (default) | `"natural"` | `"ai"`
    * `:limit` — defaults to 25; pass `:all` to disable pagination
    * `:offset` — defaults to 0

  Returns a list of maps shaped `%{service: s, expected_farrow_date: d}`.
  """
  def list_gestating_sows(scope, opts \\ [])

  def list_gestating_sows(%Scope{farm: farm}, opts) do
    farm
    |> gestating_query(opts)
    |> apply_pagination(opts)
    |> Repo.all()
    |> Enum.map(&with_expected_farrow_date/1)
  end

  @doc """
  Counts gestating sows matching the same filter opts as
  `list_gestating_sows/2` (ignores `:limit`/`:offset`).
  """
  def count_gestating_sows(%Scope{farm: farm}, opts \\ []) do
    farm |> gestating_query(opts) |> exclude(:order_by) |> Repo.aggregate(:count, :id)
  end

  defp gestating_query(farm, opts) do
    today = Date.utc_today()
    search = opts |> Keyword.get(:search) |> normalize_search()
    service_type = Keyword.get(opts, :service_type, "all")
    due_window = Keyword.get(opts, :due_window, "all")

    q =
      from(s in Service,
        join: sow in assoc(s, :sow),
        where: s.farm_id == ^farm.id and is_nil(s.result),
        order_by: [asc: s.served_at],
        preload: [:sow, :boar]
      )

    q =
      if search do
        like = "#{search}%"
        from [s, sow] in q, where: ilike(sow.ear_tag, ^like)
      else
        q
      end

    q =
      case service_type do
        t when t in ["natural", "ai"] -> from s in q, where: s.service_type == ^t
        _ -> q
      end

    case due_window do
      "7" ->
        cutoff = Date.add(today, 7 - @gestation_days)
        from s in q, where: s.served_at <= ^cutoff

      "14" ->
        cutoff = Date.add(today, 14 - @gestation_days)
        from s in q, where: s.served_at <= ^cutoff

      "overdue" ->
        cutoff = Date.add(today, -@gestation_days)
        from s in q, where: s.served_at <= ^cutoff

      _ ->
        q
    end
  end

  @doc """
  Lists gestating sows due to farrow within `days_ahead` days.
  """
  def list_due_farrowings(%Scope{farm: farm}, days_ahead \\ 7) do
    # Services served before this date have expected farrowing within the window
    served_before = Date.add(Date.utc_today(), days_ahead - @gestation_days)

    from(s in Service,
      where:
        s.farm_id == ^farm.id and
          is_nil(s.result) and
          s.served_at <= ^served_before,
      order_by: [asc: s.served_at],
      preload: [:sow, :boar]
    )
    |> Repo.all()
    |> Enum.map(&with_expected_farrow_date/1)
  end

  @doc """
  Computes the expected farrowing date for a service.
  """
  def expected_farrow_date(%Service{served_at: served_at}) do
    Date.add(served_at, @gestation_days)
  end

  defp with_expected_farrow_date(%Service{} = s) do
    %{service: s, expected_farrow_date: expected_farrow_date(s)}
  end

  # ── Farrowings ──────────────────────────────────────────────────────

  @doc """
  Records a farrowing event for a gestating sow.

  In one atomic transaction:
  1. Inserts the farrowing row
  2. Closes the service with `result = "farrowing"`
  3. Creates `born_alive` piglet animals with `stage=piglet`, `sex=unknown`,
     `dam_id=sow`, `sire_id=service.boar_id`, `dob=farrowed_at`
  4. Sets piglets' `current_pen_id` to `farrowing.pen_id || sow.current_pen_id`
  5. Auto-promotes sow stage to `"sow"` if not already
  6. Audits the farrowing

  If the sow has no `current_pen_id` and no `pen_id` is given in attrs,
  piglets are created unplaced (`current_pen_id = nil`).
  """
  def record_farrowing(%Scope{} = scope, %Service{} = service, attrs) do
    if service.result do
      {:error, :service_already_closed}
    else
      do_record_farrowing(scope, service, stringify_keys(attrs))
    end
  end

  defp do_record_farrowing(scope, service, attrs) do
    farm = scope.farm
    sow = Repo.get!(Animal, service.sow_id)
    pen_id = to_int(attrs["pen_id"]) || sow.current_pen_id
    born_alive = to_int(attrs["born_alive"]) || 0
    farrowed_at = attrs["farrowed_at"]

    farrowing_attrs =
      attrs
      |> Map.merge(%{
        "farm_id" => farm.id,
        "service_id" => service.id,
        "sow_id" => sow.id
      })
      |> then(fn a -> if pen_id, do: Map.put(a, "pen_id", pen_id), else: a end)

    multi =
      Multi.new()
      |> Multi.insert(:farrowing, Farrowing.changeset(%Farrowing{}, farrowing_attrs))
      |> Multi.update(
        :close_service,
        Service.close_changeset(service, %{
          "result" => "farrowing",
          "result_at" => farrowed_at
        })
      )
      |> insert_piglets(farm.id, sow, service.boar_id, pen_id, born_alive, farrowed_at)
      |> update_sow_for_farrowing(sow)
      |> audit_after(scope, "farrowing.created", :farrowing)

    case Repo.transaction(multi) do
      {:ok, %{farrowing: farrowing} = results} ->
        litter = Map.get(results, :litter_batch)
        {:ok, farrowing, litter}

      {:error, :farrowing, cs, _} ->
        {:error, cs}

      {:error, step, cs, _} ->
        {:error, {step, cs}}
    end
  end

  defp insert_piglets(multi, _farm_id, _sow, _boar_id, _pen_id, 0, _farrowed_at), do: multi

  defp insert_piglets(multi, farm_id, sow, boar_id, pen_id, count, farrowed_at) do
    multi
    |> Multi.run(:litter_batch, fn _repo, %{farrowing: farrowing} ->
      Repo.insert(
        Animal.piglet_changeset(%Animal{}, %{
          "tracking_type" => "batch",
          "stage" => "piglet",
          "status" => "active",
          "quantity" => count,
          "dob" => farrowed_at,
          "dam_id" => sow.id,
          "sire_id" => boar_id,
          "farrowing_id" => farrowing.id,
          "farm_id" => farm_id
        })
      )
    end)
    |> maybe_place_litter_batch(farm_id, pen_id, farrowed_at)
  end

  defp maybe_place_litter_batch(multi, _farm_id, nil, _date), do: multi

  defp maybe_place_litter_batch(multi, farm_id, pen_id, farrowed_at) do
    placed_at = farrowed_at || Date.utc_today()

    multi
    |> Multi.run(:litter_placement, fn _repo, %{litter_batch: batch} ->
      Repo.insert(
        Placement.changeset(%Placement{}, %{
          animal_id: batch.id,
          pen_id: pen_id,
          quantity: batch.quantity,
          placed_at: placed_at
        })
      )
    end)
    |> Multi.run(:litter_movement, fn _repo, %{litter_batch: batch} ->
      Repo.insert(
        Movement.changeset(%Movement{}, %{
          "farm_id" => farm_id,
          "animal_id" => batch.id,
          "to_pen_id" => pen_id,
          "reason" => "placement",
          "quantity" => batch.quantity,
          "moved_at" => placed_at
        })
      )
    end)
  end

  defp update_sow_for_farrowing(multi, sow) do
    changes = %{status: "lactating"}
    changes = if sow.stage != "sow", do: Map.put(changes, :stage, "sow"), else: changes
    Multi.update(multi, :update_sow, Ecto.Changeset.change(sow, changes))
  end

  @doc """
  Lists farrowings for a farm, newest first.
  Supports optional filter: `sow_id`.
  """
  def list_farrowings(%Scope{farm: farm}, opts \\ []) do
    q =
      from(f in Farrowing,
        where: f.farm_id == ^farm.id,
        order_by: [desc: f.farrowed_at, desc: f.id],
        preload: [:sow, [pen: :house], service: [:boar]]
      )

    q =
      case Keyword.get(opts, :sow_id) do
        nil -> q
        sow_id -> where(q, [f], f.sow_id == ^sow_id)
      end

    Repo.all(q)
  end

  @doc """
  Gets a farrowing by id, scoped to the farm.
  """
  def get_farrowing!(%Scope{farm: farm}, id) do
    Repo.get_by!(Farrowing, id: id, farm_id: farm.id)
    |> Repo.preload([:sow, :pen, :weaning, :piglets, service: [:boar]])
  end

  @doc """
  Returns a changeset for tracking farrowing form changes.
  """
  def change_farrowing(%Farrowing{} = farrowing, attrs \\ %{}) do
    Farrowing.changeset(farrowing, attrs)
  end

  @doc """
  Returns the parity (number of farrowings) for a sow.
  """
  def parity(%Scope{farm: farm}, sow_id) do
    Repo.aggregate(
      from(f in Farrowing, where: f.farm_id == ^farm.id and f.sow_id == ^sow_id),
      :count
    )
  end

  @doc """
  Lists farrowings that have not yet been weaned (sow is lactating).

  Options:
    * `:search` — case-insensitive ear-tag prefix (matches sow ear tag)
    * `:age_bucket` — `"all"` (default) | `"week1"` (0-6d) |
      `"week2"` (7-13d) | `"week3"` (14-20d) | `"wean_due"` (21d+)
    * `:pen_id` — restrict to farrowings in a single pen
    * `:limit` — defaults to 25; pass `:all` to disable pagination
    * `:offset` — defaults to 0
  """
  def list_lactating_sows(scope, opts \\ [])

  def list_lactating_sows(%Scope{farm: farm}, opts) do
    farm
    |> lactating_query(opts)
    |> apply_pagination(opts)
    |> Repo.all()
  end

  @doc """
  Counts lactating farrowings matching the same filter opts as
  `list_lactating_sows/2` (ignores `:limit`/`:offset`).
  """
  def count_lactating_sows(%Scope{farm: farm}, opts \\ []) do
    farm |> lactating_query(opts) |> exclude(:order_by) |> Repo.aggregate(:count, :id)
  end

  defp lactating_query(farm, opts) do
    today = Date.utc_today()
    search = opts |> Keyword.get(:search) |> normalize_search()
    age_bucket = Keyword.get(opts, :age_bucket, "all")
    pen_id = Keyword.get(opts, :pen_id)

    q =
      from(f in Farrowing,
        join: sow in assoc(f, :sow),
        left_join: w in Weaning,
        on: w.farrowing_id == f.id,
        where: f.farm_id == ^farm.id and is_nil(w.id),
        order_by: [asc: f.farrowed_at],
        preload: [:sow, [pen: :house], service: [:boar]]
      )

    q =
      if search do
        like = "#{search}%"
        from [f, sow, w] in q, where: ilike(sow.ear_tag, ^like)
      else
        q
      end

    q =
      case parse_pen_id(pen_id) do
        nil -> q
        id -> from f in q, where: f.pen_id == ^id
      end

    case age_bucket do
      "week1" ->
        from f in q, where: f.farrowed_at > ^Date.add(today, -7)

      "week2" ->
        from f in q,
          where: f.farrowed_at <= ^Date.add(today, -7) and f.farrowed_at > ^Date.add(today, -14)

      "week3" ->
        from f in q,
          where: f.farrowed_at <= ^Date.add(today, -14) and f.farrowed_at > ^Date.add(today, -21)

      "wean_due" ->
        from f in q, where: f.farrowed_at <= ^Date.add(today, -21)

      _ ->
        q
    end
  end

  defp apply_pagination(query, opts) do
    case Keyword.get(opts, :limit, 25) do
      :all ->
        query

      limit when is_integer(limit) and limit > 0 ->
        offset = Keyword.get(opts, :offset, 0)
        from q in query, limit: ^limit, offset: ^offset

      _ ->
        query
    end
  end

  defp normalize_search(nil), do: nil

  defp normalize_search(term) when is_binary(term) do
    case String.trim(term) do
      "" -> nil
      t -> t
    end
  end

  defp normalize_search(_), do: nil

  defp parse_pen_id(nil), do: nil
  defp parse_pen_id(""), do: nil
  defp parse_pen_id(id) when is_integer(id), do: id

  defp parse_pen_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  # ── Weanings ──────────────────────────────────────────────────────

  @doc """
  Records a weaning event for a farrowed litter.

  In one atomic transaction:
  1. Inserts the weaning row
  2. For `weaned_count >= 1`:
     - Updates the litter batch: `stage → "weaner"`, `quantity → weaned_count`
     - If `destination_pen_id` is given, closes old placement and moves batch
  3. For `weaned_count == 0`:
     - Marks the litter batch as `status = "deceased"`, `quantity = 0`
  4. Audits the weaning

  Returns `{:ok, weaning, batch}` on success.
  The third element is the updated batch animal, or nil if no litter exists.
  """
  def record_weaning(%Scope{} = scope, %Farrowing{} = farrowing, attrs) do
    if Repo.get_by(Weaning, farrowing_id: farrowing.id) do
      {:error, :already_weaned}
    else
      do_record_weaning(scope, farrowing, stringify_keys(attrs))
    end
  end

  defp do_record_weaning(scope, farrowing, attrs) do
    farm = scope.farm
    weaned_count = to_int(attrs["weaned_count"]) || 0
    dest_pen_id = to_int(attrs["destination_pen_id"])
    weaned_at = attrs["weaned_at"]
    sow = Repo.get!(Animal, farrowing.sow_id)

    weaning_attrs =
      attrs
      |> Map.merge(%{
        "farm_id" => farm.id,
        "farrowing_id" => farrowing.id
      })

    multi =
      Multi.new()
      |> Multi.insert(:weaning, Weaning.changeset(%Weaning{}, weaning_attrs))
      |> consolidate_piglets(farm.id, farrowing, sow, weaned_count, dest_pen_id, weaned_at)
      |> update_sow_after_weaning(sow)
      |> audit_after(scope, "weaning.created", :weaning)

    case Repo.transaction(multi) do
      {:ok, %{weaning: weaning} = results} ->
        batch = Map.get(results, :batch)
        {:ok, weaning, batch}

      {:error, :weaning, cs, _} ->
        {:error, cs}

      {:error, step, cs, _} ->
        {:error, {step, cs}}
    end
  end

  # weaned_count >= 1: promote litter batch to weaner, update quantity
  defp consolidate_piglets(multi, farm_id, farrowing, _sow, count, dest_pen_id, weaned_at)
       when count >= 1 do
    multi
    |> Multi.run(:batch, fn repo, _ ->
      case repo.one(
             from(a in Animal,
               where:
                 a.farrowing_id == ^farrowing.id and
                   a.tracking_type == "batch" and
                   a.status == "active"
             )
           ) do
        nil ->
          {:ok, nil}

        batch ->
          batch
          |> Ecto.Changeset.change(%{stage: "weaner", quantity: count})
          |> repo.update()
      end
    end)
    |> maybe_move_weaned_batch(farm_id, dest_pen_id, weaned_at)
  end

  # weaned_count == 0: all piglets died, mark batch as deceased
  defp consolidate_piglets(multi, _farm_id, farrowing, _sow, 0, _dest_pen_id, _weaned_at) do
    Multi.run(multi, :batch, fn repo, _ ->
      case repo.one(
             from(a in Animal,
               where:
                 a.farrowing_id == ^farrowing.id and
                   a.tracking_type == "batch"
             )
           ) do
        nil ->
          {:ok, nil}

        batch ->
          batch
          |> Ecto.Changeset.change(%{status: "deceased", quantity: 0})
          |> repo.update()
      end
    end)
  end

  defp maybe_move_weaned_batch(multi, _farm_id, nil, _weaned_at), do: multi

  defp maybe_move_weaned_batch(multi, farm_id, dest_pen_id, weaned_at) do
    moved = weaned_at || Date.utc_today()

    multi
    |> Multi.run(:close_old_placement, fn repo, %{batch: batch} ->
      case batch do
        nil ->
          {:ok, nil}

        batch ->
          now = DateTime.truncate(DateTime.utc_now(), :second)

          repo.update_all(
            from(p in Placement,
              where: p.animal_id == ^batch.id and is_nil(p.removed_at)
            ),
            set: [removed_at: moved, updated_at: now]
          )

          {:ok, :closed}
      end
    end)
    |> Multi.run(:wean_placement, fn repo, %{batch: batch} ->
      case batch do
        nil ->
          {:ok, nil}

        batch ->
          repo.insert(
            Placement.changeset(%Placement{}, %{
              animal_id: batch.id,
              pen_id: dest_pen_id,
              quantity: batch.quantity,
              placed_at: moved
            })
          )
      end
    end)
    |> Multi.run(:wean_movement, fn repo, %{batch: batch} ->
      case batch do
        nil ->
          {:ok, nil}

        batch ->
          repo.insert(
            Movement.changeset(%Movement{}, %{
              "farm_id" => farm_id,
              "animal_id" => batch.id,
              "to_pen_id" => dest_pen_id,
              "reason" => "pen_transfer",
              "quantity" => batch.quantity,
              "moved_at" => moved
            })
          )
      end
    end)
  end

  @doc """
  Returns a changeset for tracking weaning form changes.
  """
  def change_weaning(%Weaning{} = weaning, attrs \\ %{}) do
    Weaning.changeset(weaning, attrs)
  end

  @doc """
  Returns the count of surviving piglets for a farrowing.
  Reads the litter batch's current quantity.
  """
  def surviving_piglet_count(%Farrowing{} = farrowing) do
    case Repo.one(
           from(a in Animal,
             where:
               a.farrowing_id == ^farrowing.id and
                 a.tracking_type == "batch" and
                 a.status == "active"
           )
         ) do
      nil -> 0
      batch -> batch.quantity
    end
  end

  @doc """
  Lists all piglets (any status) for a farrowing.
  """
  def list_litter(%Scope{farm: farm}, %Farrowing{} = farrowing) do
    Repo.all(
      from(a in Animal,
        where: a.farm_id == ^farm.id and a.farrowing_id == ^farrowing.id,
        order_by: [asc: a.id],
        preload: [:current_pen]
      )
    )
  end

  # ── Sow status helpers ─────────────────────────────────────────────

  defp update_sow_status(multi, sow_id, new_status) do
    sow_id = to_int(sow_id)

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, :update_sow_status, fn _repo, _ ->
        sow = Repo.get!(Animal, sow_id)
        sow |> Ecto.Changeset.change(%{status: new_status}) |> Repo.update()
      end)
    end
  end

  defp update_sow_status_keyed(multi, sow_id, new_status, i) do
    sow_id = to_int(sow_id)

    if is_nil(sow_id) do
      multi
    else
      Multi.run(multi, {:update_sow_status, i}, fn _repo, _ ->
        sow = Repo.get!(Animal, sow_id)
        sow |> Ecto.Changeset.change(%{status: new_status}) |> Repo.update()
      end)
    end
  end

  # After weaning piglets the sow moves to "dry" — resting before next heat.
  # Only transition from "lactating" (the expected source state); leave
  # already-departed or otherwise-transitioned sows untouched.
  defp update_sow_after_weaning(multi, sow) do
    if sow.status == "lactating" do
      Multi.update(multi, :sow_dry, Ecto.Changeset.change(sow, %{status: "dry"}))
    else
      multi
    end
  end

  # ── Private helpers ────────────────────────────────────────────────

  defp maybe_filter_service(query, :sow_id, nil), do: query
  defp maybe_filter_service(query, :sow_id, id), do: where(query, [s], s.sow_id == ^id)

  defp maybe_filter_service(query, :result, nil), do: query
  defp maybe_filter_service(query, :result, :open), do: where(query, [s], is_nil(s.result))

  defp maybe_filter_service(query, :result, val),
    do: where(query, [s], s.result == ^to_string(val))

  defp audit_after(multi, scope, action, key) do
    Multi.run(multi, {:audit, action}, fn _repo, changes ->
      row = Map.fetch!(changes, key)

      Audit.log_now!(scope, action,
        entity_type: key,
        entity_id: row.id
      )

      {:ok, :logged}
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp to_int(nil), do: nil
  defp to_int(""), do: nil
  defp to_int(i) when is_integer(i), do: i

  defp to_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, ""} -> i
      _ -> nil
    end
  end
end
