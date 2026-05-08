defmodule PeggyWeb.FarmLive.DataImport do
  @moduledoc """
  Owner-only legacy CSV importer. Three steps:

    :upload  → file slots + Validate button
    :review  → per-file report; Commit button (disabled if errors > 0)
    :done    → outcome screen with per-file counts

  See `Peggy.Imports` for the underlying parse / validate / commit
  pipeline and `IMPORT_LEGACY_DATA.md` for the user-facing CSV spec.
  """
  use PeggyWeb, :live_view

  alias Peggy.{Imports, Policy}

  @file_kinds ~w(locations sows services farrowings weanings culls)a
  # 5 MB per file ≈ ~50k typical sow rows. Hard limit on rows is
  # enforced inside Imports.parse_and_validate (10k per file).
  @max_file_size 5 * 1024 * 1024

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl">
        <.header>
          {gettext("Import legacy data")}
          <:subtitle>
            {gettext("Upload CSVs from another farm-management system. Owner-only.")}
          </:subtitle>
        </.header>

        <%!-- Step indicator --%>
        <ol class="mt-4 flex items-center gap-2 text-sm">
          <.step active={@step == :upload} done={@step in [:review, :done]} label="1. Upload" />
          <span class="text-base-content/30">→</span>
          <.step active={@step == :review} done={@step == :done} label="2. Review" />
          <span class="text-base-content/30">→</span>
          <.step active={@step == :done} done={false} label="3. Commit" />
        </ol>

        <section :if={@step == :upload} class="mt-6 space-y-4">
          <p class="text-sm text-base-content/70">
            {gettext(
              "Required: sows.csv. Other files are optional. Column specs are in IMPORT_LEGACY_DATA.md (or download a header-only template below)."
            )}
          </p>

          <form id="import-upload" phx-change="validate_upload" phx-submit="run_validation">
            <div :for={kind <- @file_kinds} class="rounded-md border border-base-200 p-3 mb-3">
              <div class="flex items-baseline justify-between gap-3">
                <label for={"upload-#{kind}"} class="font-mono font-semibold">
                  {kind}.csv <span :if={kind == :sows} class="text-error ml-1">*</span>
                </label>
                <.link
                  href={~p"/farms/#{@current_scope.farm.slug}/admin/import/template/#{kind}"}
                  class="text-xs text-primary underline"
                >
                  {gettext("Download template")}
                </.link>
              </div>

              <.live_file_input upload={@uploads[kind]} class="file-input file-input-sm w-full mt-2" />

              <div :for={entry <- @uploads[kind].entries} class="mt-2 text-xs flex items-center gap-2">
                <.icon name="hero-document-micro" class="size-4 text-base-content/60" />
                <span>{entry.client_name}</span>
                <span class="text-base-content/40">{entry.client_size} bytes</span>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-kind={kind}
                  phx-value-ref={entry.ref}
                  class="ml-auto text-error/70 underline"
                >
                  {gettext("remove")}
                </button>
              </div>

              <p :for={err <- upload_errors(@uploads[kind])} class="mt-1 text-xs text-error">
                {error_to_string(err)}
              </p>
            </div>

            <div class="mt-4 flex gap-2 justify-end">
              <.button
                class="btn btn-primary"
                phx-disable-with={gettext("Validating...")}
                disabled={not has_sows_upload?(@uploads)}
              >
                {gettext("Validate")}
              </.button>
            </div>
          </form>

          <%!-- Past runs --%>
          <div :if={@runs != []} class="mt-8">
            <h3 class="font-semibold mb-2">{gettext("Past imports")}</h3>
            <p class="text-xs text-base-content/60 mb-2">
              {gettext(
                "Rolling back deletes all rows tagged with the run id (animals, services, farrowings, weanings). Houses and pens are not removed. Rollback fails if any tagged row has post-import dependencies (e.g. a farrowing recorded by hand against an imported sow)."
              )}
            </p>
            <ul class="rounded-md border border-base-200 divide-y divide-base-200">
              <li :for={run <- @runs} class="px-3 py-2 text-sm">
                <div class="flex items-center justify-between gap-2">
                  <div>
                    <span class="font-mono">{run.run_id}</span>
                    <span class="text-base-content/60 text-xs ml-2">
                      {Calendar.strftime(run.inserted_at, "%Y-%m-%d %H:%M")} UTC
                    </span>
                    <span :if={run.actor_email} class="text-base-content/60 text-xs ml-2">
                      {gettext("by")} {run.actor_email}
                    </span>
                  </div>
                  <button
                    type="button"
                    phx-click="rollback"
                    phx-value-run-id={run.run_id}
                    data-confirm={
                      gettext(
                        "Roll back this import? This deletes %{a} animals, %{s} services, %{f} farrowings, %{w} weanings.",
                        a: run.counts.sows,
                        s: run.counts.services,
                        f: run.counts.farrowings,
                        w: run.counts.weanings
                      )
                    }
                    class="btn btn-ghost btn-xs text-error"
                  >
                    <.icon name="hero-arrow-uturn-left-micro" class="size-3" />
                    {gettext("Rollback")}
                  </button>
                </div>
                <div class="text-xs text-base-content/60 mt-1">
                  {run.counts.locations} {gettext("locations")} · {run.counts.sows} {gettext("sows")} · {run.counts.services} {gettext(
                    "services"
                  )} · {run.counts.farrowings} {gettext("farrowings")} · {run.counts.weanings} {gettext(
                    "weanings"
                  )}
                </div>
              </li>
            </ul>
          </div>
        </section>

        <section :if={@step == :review} class="mt-6 space-y-4">
          <div class="rounded-md border border-base-200 bg-base-100 p-4">
            <h3 class="font-semibold mb-2">{gettext("Validation summary")}</h3>
            <dl class="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
              <dt class="text-base-content/60">{gettext("Locations")}</dt>
              <dd>
                {@report.summary.locations_in} {gettext("rows")} ·
                <span class="text-success">
                  {@report.summary.locations_importable} {gettext("ok")}
                </span>
                ·
                <span :if={@report.summary.locations_errors > 0} class="text-error">
                  {@report.summary.locations_errors} {gettext("errors")}
                </span>
              </dd>
              <dt class="text-base-content/60">{gettext("Sows")}</dt>
              <dd>
                {@report.summary.sows_in} {gettext("rows")} ·
                <span class="text-success">{@report.summary.sows_importable} {gettext("ok")}</span>
                ·
                <span :if={@report.summary.sows_errors > 0} class="text-error">
                  {@report.summary.sows_errors} {gettext("errors")}
                </span>
              </dd>
              <dt class="text-base-content/60">{gettext("Services")}</dt>
              <dd>
                {@report.summary.services_in} {gettext("rows")} ·
                <span class="text-success">
                  {@report.summary.services_importable} {gettext("ok")}
                </span>
                ·
                <span :if={@report.summary.services_errors > 0} class="text-error">
                  {@report.summary.services_errors} {gettext("errors")}
                </span>
              </dd>
              <dt class="text-base-content/60">{gettext("Farrowings")}</dt>
              <dd>
                {@report.summary.farrowings_in} {gettext("rows")} ·
                <span class="text-success">
                  {@report.summary.farrowings_importable} {gettext("ok")}
                </span>
                ·
                <span :if={@report.summary.farrowings_errors > 0} class="text-error">
                  {@report.summary.farrowings_errors} {gettext("errors")}
                </span>
              </dd>
              <dt class="text-base-content/60">{gettext("Weanings")}</dt>
              <dd>
                {@report.summary.weanings_in} {gettext("rows")} ·
                <span class="text-success">
                  {@report.summary.weanings_importable} {gettext("ok")}
                </span>
                ·
                <span :if={@report.summary.weanings_errors > 0} class="text-error">
                  {@report.summary.weanings_errors} {gettext("errors")}
                </span>
              </dd>
              <dt class="text-base-content/60">{gettext("Removals")}</dt>
              <dd>
                {@report.summary.culls_in} {gettext("rows")} ·
                <span class="text-success">{@report.summary.culls_importable} {gettext("ok")}</span>
                ·
                <span :if={@report.summary.culls_errors > 0} class="text-error">
                  {@report.summary.culls_errors} {gettext("errors")}
                </span>
              </dd>
            </dl>
          </div>

          <.report_block label="locations.csv" file={@report.locations} />
          <.report_block label="sows.csv" file={@report.sows} />
          <.report_block label="services.csv" file={@report.services} />
          <.report_block label="farrowings.csv" file={@report.farrowings} />
          <.report_block label="weanings.csv" file={@report.weanings} />
          <.report_block label="culls.csv" file={@report.culls} />

          <%!-- Legacy-batch lifecycle inference --%>
          <div
            :if={@report.summary.weanings_importable > 0}
            class="rounded-md border border-base-200 bg-base-100 p-4"
          >
            <h3 class="font-semibold">{gettext("Legacy batch lifecycle")}</h3>
            <p class="text-sm text-base-content/70 mt-1">
              {gettext(
                "Each weaning row creates a weaner batch. Based on the litter's age (today − farrowed_at) the importer will promote it to grower / finisher, and any batch older than the finisher max is recorded as already sold (sale movement dated at farrowed_at + finisher max)."
              )}
            </p>

            <form
              id="legacy-thresholds"
              phx-change="update_thresholds"
              phx-submit="update_thresholds"
              class="mt-3 grid sm:grid-cols-3 gap-3"
            >
              <label class="form-control">
                <div class="label py-1">
                  <span class="label-text text-xs">{gettext("Weaner max (days)")}</span>
                </div>
                <input
                  type="number"
                  name="thresholds[weaner_max]"
                  value={@legacy_thresholds.weaner_max}
                  min="14"
                  max="120"
                  class="input input-sm input-bordered"
                />
                <p class="text-xs text-base-content/60 mt-1">
                  {gettext("Default 70. Age ≤ this → weaner.")}
                </p>
              </label>
              <label class="form-control">
                <div class="label py-1">
                  <span class="label-text text-xs">{gettext("Grower max (days)")}</span>
                </div>
                <input
                  type="number"
                  name="thresholds[grower_max]"
                  value={@legacy_thresholds.grower_max}
                  min="30"
                  max="200"
                  class="input input-sm input-bordered"
                />
                <p class="text-xs text-base-content/60 mt-1">
                  {gettext("Default 130. Weaner-max < age ≤ this → grower.")}
                </p>
              </label>
              <label class="form-control">
                <div class="label py-1">
                  <span class="label-text text-xs">{gettext("Finisher max (days)")}</span>
                </div>
                <input
                  type="number"
                  name="thresholds[finisher_max]"
                  value={@legacy_thresholds.finisher_max}
                  min="60"
                  max="365"
                  class="input input-sm input-bordered"
                />
                <p class="text-xs text-base-content/60 mt-1">
                  {gettext("Default 200. Grower-max < age ≤ this → finisher; older → sold.")}
                </p>
              </label>
            </form>

            <div :if={@legacy_preview} class="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-2 text-sm">
              <div class="rounded border border-base-200 px-3 py-2">
                <div class="text-xs text-base-content/60">{gettext("Weaner")}</div>
                <div class="font-mono font-bold text-lg">{@legacy_preview.weaner}</div>
              </div>
              <div class="rounded border border-base-200 px-3 py-2">
                <div class="text-xs text-base-content/60">{gettext("Grower")}</div>
                <div class="font-mono font-bold text-lg">{@legacy_preview.grower}</div>
              </div>
              <div class="rounded border border-base-200 px-3 py-2">
                <div class="text-xs text-base-content/60">{gettext("Finisher")}</div>
                <div class="font-mono font-bold text-lg">{@legacy_preview.finisher}</div>
              </div>
              <div class="rounded border border-warning/40 bg-warning/5 px-3 py-2">
                <div class="text-xs text-base-content/60">{gettext("Finisher (sold)")}</div>
                <div class="font-mono font-bold text-lg text-warning">
                  {@legacy_preview.sold_finisher}
                </div>
              </div>
            </div>
          </div>

          <div class="flex gap-2 justify-end">
            <button type="button" phx-click="back_to_upload" class="btn btn-ghost">
              {gettext("Back to upload")}
            </button>
            <button
              type="button"
              phx-click="commit"
              phx-disable-with={gettext("Committing...")}
              disabled={@report.summary.blocking_errors > 0}
              class="btn btn-primary"
            >
              {gettext("Commit import")}
              <span :if={@report.summary.blocking_errors > 0} class="text-xs ml-1">
                ({gettext("fix errors first")})
              </span>
            </button>
          </div>
        </section>

        <section :if={@step == :done} class="mt-6 space-y-4">
          <div class="alert alert-success">
            <.icon name="hero-check-circle" class="size-5" />
            <div>
              <div class="font-semibold">{gettext("Import committed.")}</div>
              <div class="text-xs">
                {gettext("Run id")}: <span class="font-mono">{@outcome.run_id}</span>
              </div>
            </div>
          </div>

          <div class="rounded-md border border-base-200 p-4 text-sm">
            <h3 class="font-semibold mb-2">{gettext("Per-file outcomes")}</h3>
            <ul class="space-y-1">
              <.outcome_row label="locations.csv" file={@outcome.locations} />
              <.outcome_row label="sows.csv" file={@outcome.sows} />
              <.outcome_row label="services.csv" file={@outcome.services} />
              <.outcome_row label="farrowings.csv" file={@outcome.farrowings} />
              <.outcome_row label="weanings.csv" file={@outcome.weanings} />
              <.outcome_row label="culls.csv" file={@outcome.culls} />
            </ul>
          </div>

          <div class="flex gap-2 justify-end">
            <.link
              navigate={~p"/farms/#{@current_scope.farm.slug}/animals"}
              class="btn btn-ghost"
            >
              {gettext("View animals")}
            </.link>
            <button type="button" phx-click="restart" class="btn btn-primary">
              {gettext("Run another import")}
            </button>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :active, :boolean, default: false
  attr :done, :boolean, default: false
  attr :label, :string, required: true

  defp step(assigns) do
    ~H"""
    <span class={[
      "px-3 py-1 rounded-full text-xs",
      @active && "bg-primary text-primary-content font-semibold",
      @done && "bg-success/20 text-success",
      not (@active or @done) && "bg-base-200 text-base-content/50"
    ]}>
      {@label}
    </span>
    """
  end

  attr :label, :string, required: true
  attr :file, :map, required: true

  defp report_block(assigns) do
    ~H"""
    <div
      :if={@file.rows != [] or @file.err != []}
      class="rounded-md border border-base-200 p-3 text-sm"
    >
      <div class="font-mono font-semibold mb-1">{@label}</div>

      <p :if={@file.rows == [] and @file.err != []} class="text-xs text-error">
        {file_level_error_message(@file)}
      </p>

      <details :if={@file.warn != []} class="mt-1">
        <summary class="text-xs cursor-pointer text-warning">
          ⚠ {length(@file.warn)} {gettext("warnings")}
        </summary>
        <ul class="mt-1 ml-4 space-y-0.5 text-xs text-base-content/70">
          <li :for={row <- Enum.take(@file.warn, 50)}>
            <span class="font-mono">row {row[:line]}</span>
            — {row.issues |> Enum.map(& &1.msg) |> Enum.join("; ")}
          </li>
          <li :if={length(@file.warn) > 50} class="text-base-content/50">
            … {length(@file.warn) - 50} {gettext("more")}
          </li>
        </ul>
      </details>

      <details :if={@file.err != [] and @file.rows != []} class="mt-1" open>
        <summary class="text-xs cursor-pointer text-error">
          ✗ {length(@file.err)} {gettext("errors")}
        </summary>
        <ul class="mt-1 ml-4 space-y-0.5 text-xs text-error">
          <li :for={row <- Enum.take(@file.err, 50)}>
            <span class="font-mono">row {row[:line]}</span>
            — {(row[:issues] || []) |> Enum.map(& &1.msg) |> Enum.join("; ")}
          </li>
          <li :if={length(@file.err) > 50} class="text-base-content/50">
            … {length(@file.err) - 50} {gettext("more")}
          </li>
        </ul>
      </details>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :file, :map, required: true

  defp outcome_row(assigns) do
    ~H"""
    <li class="flex items-center justify-between">
      <span class="font-mono">{@label}</span>
      <span>
        <span class="text-success">{@file.ok} {gettext("ok")}</span>
        <span :if={@file.failed > 0} class="text-error ml-2">
          {@file.failed} {gettext("failed")}
        </span>
      </span>
    </li>
    """
  end

  # ── Mount ──────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Policy.can?(scope, :import_data) do
      [weaner_max: w, grower_max: g, finisher_max: f] = Imports.default_legacy_thresholds()

      socket =
        socket
        |> assign(
          page_title: gettext("Import legacy data"),
          file_kinds: @file_kinds,
          step: :upload,
          report: nil,
          outcome: nil,
          runs: Imports.list_runs(scope),
          legacy_thresholds: %{weaner_max: w, grower_max: g, finisher_max: f},
          legacy_preview: nil
        )
        |> allow_uploads()

      {:ok, socket}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Owner-only."))
       |> redirect(to: ~p"/farms/#{scope.farm.slug}")}
    end
  end

  defp allow_uploads(socket) do
    Enum.reduce(@file_kinds, socket, fn kind, acc ->
      allow_upload(acc, kind,
        accept: ~w(.csv text/csv text/plain),
        max_entries: 1,
        max_file_size: @max_file_size
      )
    end)
  end

  # ── Events ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"kind" => kind, "ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, String.to_existing_atom(kind), ref)}
  end

  def handle_event("run_validation", _params, socket) do
    paths = consume_uploads_to_temp(socket)
    scope = socket.assigns.current_scope
    report = Imports.parse_and_validate(scope, paths)
    preview = legacy_preview(scope, report, socket.assigns.legacy_thresholds)

    {:noreply, assign(socket, step: :review, report: report, legacy_preview: preview)}
  end

  def handle_event("update_thresholds", %{"thresholds" => params}, socket) do
    thresholds = parse_thresholds(params, socket.assigns.legacy_thresholds)
    scope = socket.assigns.current_scope

    preview =
      case socket.assigns.report do
        nil -> nil
        report -> legacy_preview(scope, report, thresholds)
      end

    {:noreply, assign(socket, legacy_thresholds: thresholds, legacy_preview: preview)}
  end

  def handle_event("back_to_upload", _, socket),
    do: {:noreply, assign(socket, step: :upload, report: nil)}

  def handle_event("commit", _, socket) do
    scope = socket.assigns.current_scope
    opts = Map.to_list(socket.assigns.legacy_thresholds)

    case Imports.commit(scope, socket.assigns.report, opts) do
      {:ok, outcome} ->
        {:noreply,
         socket
         |> assign(step: :done, outcome: outcome, runs: Imports.list_runs(scope))
         |> put_flash(:info, gettext("Import committed."))}

      {:error, :blocking_errors} ->
        {:noreply, put_flash(socket, :error, gettext("Cannot commit — blocking errors remain."))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Commit failed: #{inspect(reason)}")}
    end
  end

  def handle_event("rollback", %{"run-id" => run_id}, socket) do
    scope = socket.assigns.current_scope

    case Imports.rollback(scope, run_id) do
      {:ok, counts} ->
        msg =
          gettext(
            "Rolled back %{a} animals, %{s} services, %{f} farrowings, %{w} weanings.",
            a: counts.animals,
            s: counts.services,
            f: counts.farrowings,
            w: counts.weanings
          )

        {:noreply,
         socket
         |> assign(runs: Imports.list_runs(scope))
         |> put_flash(:info, msg)}

      {:error, {:fk_violation, msg}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "Rollback failed: post-import dependencies block deletion (%{msg}).",
             msg: msg
           )
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Rollback failed: #{inspect(reason)}")}
    end
  end

  def handle_event("restart", _, socket) do
    {:noreply,
     socket
     |> assign(
       step: :upload,
       report: nil,
       outcome: nil,
       runs: Imports.list_runs(socket.assigns.current_scope)
     )
     |> allow_uploads()}
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp consume_uploads_to_temp(socket) do
    Enum.reduce(@file_kinds, %{}, fn kind, acc ->
      case socket.assigns.uploads[kind].entries do
        [] ->
          acc

        [_ | _] ->
          [path] =
            consume_uploaded_entries(socket, kind, fn %{path: src}, _entry ->
              dst =
                Path.join(
                  System.tmp_dir!(),
                  "import_#{kind}_#{System.unique_integer([:positive])}.csv"
                )

              File.cp!(src, dst)
              {:ok, dst}
            end)

          Map.put(acc, kind, path)
      end
    end)
  end

  defp has_sows_upload?(uploads), do: uploads[:sows].entries != []

  defp file_level_error_message(%{err: errs}) do
    errs
    |> Enum.map(& &1.msg)
    |> Enum.join("; ")
  end

  defp error_to_string(:too_large), do: gettext("file is too large (max 5 MB)")
  defp error_to_string(:not_accepted), do: gettext("not a CSV file")
  defp error_to_string(:too_many_files), do: gettext("only one file per slot")
  defp error_to_string(other), do: to_string(other)

  # ── Legacy-batch threshold helpers ─────────────────────────────────

  defp legacy_preview(scope, report, thresholds) do
    Imports.preview_legacy_batches(scope, report, Map.to_list(thresholds))
  end

  defp parse_thresholds(params, current) do
    %{
      weaner_max: clamp_threshold(params["weaner_max"], current.weaner_max, 14, 120),
      grower_max: clamp_threshold(params["grower_max"], current.grower_max, 30, 200),
      finisher_max: clamp_threshold(params["finisher_max"], current.finisher_max, 60, 365)
    }
  end

  defp clamp_threshold(value, fallback, min, max) do
    case Integer.parse(to_string(value || "")) do
      {n, _} when n >= min and n <= max -> n
      _ -> fallback
    end
  end
end
