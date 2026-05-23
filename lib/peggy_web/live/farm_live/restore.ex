defmodule PeggyWeb.FarmLive.Restore do
  @moduledoc """
  Standalone restore screen — reachable from the farm index, without
  any farm in scope. The restoring user becomes the owner of the new
  farm created from the backup.

  Counterpart of `PeggyWeb.FarmLive.BackupRestore`, which lives inside
  a farm scope and offers both download + restore. This LV exists so a
  user with zero farms (or on a new account) can still restore.
  """
  use PeggyWeb, :live_view

  alias Peggy.Backup
  alias Peggy.Farms.Farm

  @max_upload_bytes 100 * 1024 * 1024

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl space-y-6">
        <.header>
          {gettext("Restore a farm from backup")}
          <:subtitle>
            {gettext(
              "Upload a Peggy backup file (.json.gz) to create a brand-new farm under your account. You'll become its owner."
            )}
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="restore-form"
          phx-change="validate"
          phx-submit="restore"
          class="space-y-3"
        >
          <.input
            field={@form[:slug]}
            type="text"
            label={gettext("New farm slug")}
            placeholder="lowercase-with-hyphens"
            required
          />
          <.input
            field={@form[:name]}
            type="text"
            label={gettext("New farm name")}
            placeholder="Acme Farm (restored)"
            required
          />

          <div>
            <label class="label">
              <span class="label-text">{gettext("Backup file (.json.gz)")}</span>
            </label>
            <.live_file_input upload={@uploads.backup} class="file-input file-input-sm w-full" />
            <p :for={err <- upload_errors(@uploads.backup)} class="text-error text-xs mt-1">
              {humanize_upload_error(err)}
            </p>
            <p
              :for={entry <- @uploads.backup.entries}
              :if={entry.progress > 0 and entry.progress < 100}
              class="text-xs text-base-content/60 mt-1"
            >
              {entry.client_name} — {entry.progress}%
            </p>
          </div>

          <div class="flex items-center gap-2">
            <button
              type="submit"
              class="btn btn-primary"
              disabled={@uploads.backup.entries == [] or @restoring? or @result != nil}
            >
              <span :if={@restoring?} class="loading loading-spinner loading-xs"></span>
              {if @restoring?,
                do: gettext("Restoring..."),
                else: gettext("Restore into new farm")}
            </button>
            <.link navigate={~p"/farms"} class="btn btn-ghost">{gettext("Cancel")}</.link>
          </div>
        </.form>

        <div
          :if={@restoring?}
          id="restore-progress"
          class="alert alert-info text-sm"
          aria-live="polite"
        >
          <span class="loading loading-spinner loading-sm"></span>
          <div>
            <p class="font-semibold">{gettext("Restoring backup...")}</p>
            <p class="text-xs">
              {gettext(
                "Reading the file and rebuilding the farm. Large backups can take a minute or two — please don't navigate away."
              )}
            </p>
          </div>
        </div>

        <div :if={@result} class="alert alert-info text-sm">
          <div>
            <p class="font-semibold">{gettext("Restore complete")}</p>
            <p>
              {gettext("New farm: %{name} (%{slug})",
                name: @result.name,
                slug: @result.slug
              )}
            </p>
            <.link navigate={~p"/farms/#{@result.slug}"} class="btn btn-sm btn-primary mt-2">
              {gettext("Open new farm")}
            </.link>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Lifecycle ────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:form, to_form(%{"slug" => "", "name" => ""}))
     |> assign(:restoring?, false)
     |> assign(:result, nil)
     |> allow_upload(:backup,
       accept: ~w(.gz application/gzip),
       max_entries: 1,
       max_file_size: @max_upload_bytes
     )}
  end

  # ── Events ───────────────────────────────────────────────────────

  @impl true
  def handle_event("validate", %{"slug" => slug, "name" => name}, socket) do
    {:noreply, assign(socket, :form, to_form(%{"slug" => slug, "name" => name}))}
  end

  def handle_event("restore", %{"slug" => slug, "name" => name}, socket) do
    case consume_one_upload(socket) do
      :no_file ->
        {:noreply, put_flash(socket, :error, gettext("Choose a backup file first."))}

      {:ok, binary} ->
        # Flip the spinner on, then schedule the actual import via
        # handle_info so this callback returns immediately and the
        # client sees the loading state.
        send(self(), {:run_restore, binary, String.trim(slug), String.trim(name)})

        {:noreply,
         socket
         |> assign(:restoring?, true)
         |> assign(:result, nil)
         |> clear_flash()}
    end
  end

  @impl true
  def handle_info({:run_restore, binary, slug, name}, socket) do
    user = socket.assigns.current_scope.user

    case Backup.import_to_new_farm(user, binary, %{"slug" => slug, "name" => name}) do
      {:ok, %Farm{} = farm} ->
        {:noreply,
         socket
         |> assign(:restoring?, false)
         |> assign(:result, %{slug: farm.slug, name: farm.name})
         |> put_flash(:info, gettext("Backup restored into new farm."))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:restoring?, false)
         |> put_flash(:error, restore_error_message(reason))}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp consume_one_upload(socket) do
    case uploaded_entries(socket, :backup) do
      {[_ | _], _} ->
        binaries =
          consume_uploaded_entries(socket, :backup, fn %{path: path}, _entry ->
            {:ok, File.read!(path)}
          end)

        case binaries do
          [bin] -> {:ok, bin}
          _ -> :no_file
        end

      _ ->
        :no_file
    end
  end

  defp humanize_upload_error(:too_large), do: gettext("File is too large.")
  defp humanize_upload_error(:not_accepted), do: gettext("Only .json.gz files are accepted.")
  defp humanize_upload_error(:too_many_files), do: gettext("Upload one file at a time.")
  defp humanize_upload_error(err), do: to_string(err)

  defp restore_error_message(:invalid_gzip),
    do: gettext("File is not a valid gzip archive.")

  defp restore_error_message(:malformed_payload),
    do: gettext("File is not a Peggy backup (missing schema_version or tables).")

  defp restore_error_message({:unsupported_schema_version, v}),
    do: gettext("Backup schema version %{v} is not supported by this app.", v: v)

  defp restore_error_message({:farm, %Ecto.Changeset{} = cs}),
    do: gettext("New farm: %{err}", err: format_changeset_errors(cs))

  defp restore_error_message({:membership, %Ecto.Changeset{} = cs}),
    do: gettext("Membership: %{err}", err: format_changeset_errors(cs))

  defp restore_error_message(other),
    do: gettext("Restore failed: %{err}", err: inspect(other))

  defp format_changeset_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", to_string(v))
      end)
    end)
    |> Enum.map_join(", ", fn {f, msgs} -> "#{f} #{Enum.join(msgs, "; ")}" end)
  end
end
