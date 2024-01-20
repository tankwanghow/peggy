defmodule Peggy.Helpers do
  import Ecto.Query, warn: false
  import Ecto.Changeset
  import PeggyWeb.Gettext

  def last_log_record_for(entity, id, com_id) do
    from(log in Peggy.Sys.Log,
      where: log.entity == ^entity,
      where: log.entity_id == ^id,
      where: log.farm_id == ^com_id,
      preload: [:user],
      order_by: [desc: log.inserted_at],
      limit: 1,
      select: log
    )
    |> Peggy.Repo.one()
  end

  def list_klass_tags(tag \\ "", class, key, com) do
    regexp = "#(\\w+#{tag}$|\\w+)"
    tag = "#%#{tag}%"

    tags =
      from(c in class,
        where: c.farm_id == ^com.id,
        where: ilike(field(c, ^key), ^tag),
        select: fragment("distinct regexp_matches(?, ?, 'g')", field(c, ^key), ^regexp)
      )

    tags
    |> order_by([1])
    |> Peggy.Repo.all()
    |> List.flatten()
  end

  def gen_temp_id(val \\ 6),
    do:
      :crypto.strong_rand_bytes(val)
      |> Base.encode32(case: :lower, padding: false)
      |> binary_part(0, val)

  def similarity_order(fields, terms) do
    texts =
      String.split(terms, " ")
      |> Enum.filter(fn x -> !String.starts_with?(x, "#") end)

    c = Enum.count(fields)

    x =
      for col <- fields, term <- texts do
        m = (c - Enum.find_index(fields, fn x -> x == col end)) |> :math.pow(2)

        dynamic(
          [cont],
          fragment("COALESCE(WORD_SIMILARITY(?,?),0)*?", ^term, field(cont, ^col), ^m)
        )
      end
      |> Enum.reduce(fn a, b -> dynamic(^a + ^b) end)

    [desc: x]
  end

  def to_upcase(cs, field) do
    force_change(cs, field, (fetch_field!(cs, field) || "") |> String.upcase() |> String.trim())
  end

  def get_entity_from_multi_tuple(multi, name) do
    Map.get(
      multi,
      multi
      |> Map.keys()
      |> Enum.filter(fn x -> is_tuple(x) end)
      |> Enum.find(fn {x, _} -> x == name end)
    )
  end

  def key_to_string(attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc -> Map.put(acc, to_string(key), value)
    end)
  end

  def validate_id(changeset, field_name, field_id) do
    if is_nil(fetch_field!(changeset, field_id)) and !is_nil(fetch_field!(changeset, field_name)) do
      changeset |> add_unique_error(field_name, gettext("not in list"))
    else
      changeset
    end
  end

  def get_change_or_data(changeset, detail_name) do
    list =
      if is_nil(get_change(changeset, detail_name)) do
        Map.fetch!(changeset.data, detail_name)
      else
        get_change(changeset, detail_name)
      end

    if is_struct(list, Ecto.Association.NotLoaded), do: [], else: list
  end

  def fill_today(changeset, date_field) do
    if is_nil(fetch_field!(changeset, date_field)) do
      changeset
      |> put_change(date_field, Timex.today())
    else
      changeset
    end
  end

  def validate_date(cs, field, days_before: days) do
    if Timex.diff(Timex.today(), fetch_field!(cs, field) || Timex.today(), :days) <= days do
      cs
    else
      add_unique_error(
        cs,
        field,
        "#{gettext("at or after")} #{Timex.shift(Timex.today(), days: -days)}"
      )
    end
  end

  def validate_date(cs, field, days_after: days) do
    if Timex.diff(fetch_field!(cs, field) || Timex.today(), Timex.today(), :days) <= days do
      cs
    else
      add_unique_error(
        cs,
        field,
        "#{gettext("at or before")} #{Timex.shift(Timex.today(), days: days)}"
      )
    end
  end

  def add_unique_error(cs, field, msg) do
    if !Enum.any?(cs.errors, fn {k, {m, _}} -> k == field and msg == m end) do
      Ecto.Changeset.add_error(cs, field, msg)
    else
      cs
    end
  end

  def clear_error(cs, field) do
    cs =
      Map.replace(
        cs,
        :errors,
        Enum.filter(cs.errors, fn {k, _} -> k != field end)
      )

    if(Enum.count(cs.errors) == 0, do: Map.replace(cs, :valid?, true), else: cs)
  end

  def exec_query(qry) do
    k = Peggy.Repo.query!(qry)

    Enum.map(k.rows, fn r ->
      Enum.zip(k.columns |> Enum.map(fn x -> String.to_atom(x) end), r)
    end)
    |> Enum.map(fn x ->
      Map.new(x, fn {kk, vv} ->
        {kk,
         if(Atom.to_string(kk) |> String.ends_with?("id") and !is_nil(vv),
           do: Ecto.UUID.cast!(vv),
           else: vv
         )}
      end)
    end)
  end
end
