defmodule PeggyWeb.FarmLive.Breeding.Shared do
  @moduledoc """
  Shared helpers and components for the breeding tab LiveViews
  (Gestating / Lactating / Weaned / Deleted).
  """
  use PeggyWeb, :html

  alias Peggy.{Animals, Locations}

  @per_page 25
  def per_page, do: @per_page

  # ── Modal component ─────────────────────────────────────────────────

  attr :title, :string, required: true
  attr :on_cancel, :string, required: true
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id="breeding-modal"
      class="fixed inset-0 bg-black/40 flex items-center justify-center z-50"
    >
      <div
        class="bg-base-100 rounded p-4 sm:p-6 w-full max-w-2xl mx-4 max-h-[85vh] overflow-y-auto"
        phx-click-away={@on_cancel}
        phx-window-keydown={@on_cancel}
        phx-key="escape"
      >
        <h3 class="text-lg font-semibold mb-3">{@title}</h3>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ── Path helpers ────────────────────────────────────────────────────

  @doc """
  Builds a URL for the given `tab` (\"gestating\", \"lactating\", etc.),
  merging the current query with overrides and pruning defaults.
  """
  def tab_path(socket, tab, overrides \\ %{}) do
    slug = socket.assigns.current_scope.farm.slug
    existing = current_query(socket)
    merged = existing |> Map.merge(overrides) |> prune_query()
    base = tab_base(slug, tab)

    case merged do
      m when map_size(m) == 0 -> base
      m -> base <> "?" <> URI.encode_query(m)
    end
  end

  defp tab_base(slug, "gestating"), do: ~p"/farms/#{slug}/breeding/gestating"
  defp tab_base(slug, "lactating"), do: ~p"/farms/#{slug}/breeding/lactating"
  defp tab_base(slug, "weaned"), do: ~p"/farms/#{slug}/breeding/weaned"
  defp tab_base(slug, "deleted"), do: ~p"/farms/#{slug}/breeding/deleted"

  defp current_query(%{assigns: assigns}) do
    filters = Map.get(assigns, :filters, %{})

    %{"page" => Map.get(assigns, :page, 1)}
    |> Map.put("q", Map.get(filters, :q, ""))
    |> Map.put("window", Map.get(filters, :window, "all"))
    |> Map.put("service_type", Map.get(filters, :service_type, "all"))
    |> Map.put("age", Map.get(filters, :age, "all"))
    |> Map.put("pen_id", Map.get(filters, :pen_id, ""))
    |> Map.put("pen_search", Map.get(filters, :pen_search, ""))
    |> Map.put("min_parity", Map.get(filters, :min_parity, ""))
    |> Map.put("max_parity", Map.get(filters, :max_parity, ""))
  end

  def prune_query(q) do
    q
    |> Enum.reject(fn
      {_k, nil} -> true
      {_k, ""} -> true
      {"page", 1} -> true
      {"page", "1"} -> true
      {"window", "all"} -> true
      {"service_type", "all"} -> true
      {"age", "all"} -> true
      _ -> false
    end)
    |> Map.new()
  end

  # ── Param parsers ───────────────────────────────────────────────────

  def param_window(w) when w in ["7", "14", "overdue"], do: w
  def param_window(_), do: "all"

  def param_service_type(t) when t in ["natural", "ai"], do: t
  def param_service_type(_), do: "all"

  def param_age(a) when a in ["week1", "week2", "week3", "wean_due"], do: a
  def param_age(_), do: "all"

  def param_page(p) when is_binary(p) do
    case Integer.parse(p) do
      {n, ""} when n >= 1 -> n
      _ -> 1
    end
  end

  def param_page(_), do: 1

  # ── Autocomplete state ──────────────────────────────────────────────

  def default_ac(scope) do
    animals = Animals.list_animals(scope, status: "present")
    pens = Locations.list_all_pens(scope)

    pen_items = Enum.map(pens, &%{id: &1.id, label: "#{&1.house.code}-#{&1.code}"})

    %{
      sow_items: animal_items(animals, "sow"),
      sow_label: nil,
      boar_items: animal_items(animals, "boar"),
      boar_label: nil,
      pen_items: pen_items,
      pen_label: nil,
      dest_pen_label: nil,
      foster_dest_items: [],
      foster_dest_label: nil
    }
  end

  def animal_items(animals, stage) do
    animals
    |> Enum.filter(&(&1.stage == stage and &1.ear_tag != nil))
    |> Enum.map(&%{id: &1.id, label: &1.ear_tag})
  end

  def maybe_preselect_pen(ac, scope, %{current_pen_id: pen_id}) when not is_nil(pen_id) do
    pen = Locations.get_pen!(scope, pen_id) |> Peggy.Repo.preload(:house)
    %{ac | pen_label: "#{pen.house.code}-#{pen.code}"}
  end

  def maybe_preselect_pen(ac, _, _), do: ac

  # ── Small helpers ───────────────────────────────────────────────────

  def fv(form, field), do: Phoenix.HTML.Form.input_value(form, field)

  def presence(nil), do: nil
  def presence(""), do: nil

  def presence(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      v -> v
    end
  end

  def truthy?("true"), do: true
  def truthy?(true), do: true
  def truthy?(_), do: false

  def parse_int(nil), do: nil
  def parse_int(""), do: nil
  def parse_int(n) when is_integer(n), do: n

  def parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, _} -> i
      :error -> nil
    end
  end

  def format_cs_error(%Ecto.Changeset{errors: errors}) do
    case errors do
      [{field, {msg, _}} | _] -> "#{field}: #{msg}"
      _ -> gettext("Validation failed")
    end
  end
end
