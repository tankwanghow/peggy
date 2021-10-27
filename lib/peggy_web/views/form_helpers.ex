defmodule PeggyWeb.FormHelpers do
  @moduledoc """
  Conveniences for translating and building form elements.
  """
  use Phoenix.HTML
  import PeggyWeb.ErrorHelpers
  import PeggyWeb.Gettext

  def peggy_text(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :text, class: "input"] ++ opts)
  end

  def peggy_date(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :date, class: "input"] ++ opts)
  end

  def peggy_number(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :number, class: "input"] ++ opts)
  end

  def peggy_email(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :email, class: "input"] ++ opts)
  end

  def peggy_password(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :password, class: "input"] ++ opts)
  end

  def peggy_select(form, field, values, opts \\ []) do
    content_tag(
      :div,
      [
        select(form, field, values, peggy_field(form, field, "", opts)),
        error_tag(form, field)
      ], class: "control field select"
    )
  end

  def datalist(list, id) do
    content_tag(:datalist, options(list), id: id)
  end

  def ago(date) do
    if date do
      days = round(NaiveDateTime.diff(NaiveDateTime.utc_now(), date) / 24 / 60 / 60)
      if(days == 0, do: gettext("today"), else: ago_words(days))
    else
      gettext("never")
    end
  end

  defp ago_words(days) when days == 1, do: "yesterday"

  defp ago_words(days) when days > 1 and days <= 14 do
    "#{days}" <> gettext(" days ago")
  end

  defp ago_words(days) when days > 14 and days <= 59 do
    "#{round(days / 7)}" <> gettext(" weeks ago")
  end

  defp ago_words(days) when days > 59 and days <= 364 do
    "#{round(days / 30)}" <> gettext(" months ago")
  end

  defp ago_words(days) when days > 364 do
    year = round(days / 365)

    if year > 1 do
      "#{year}" <> gettext(" years ago")
    else
      "#{year}" <> gettext(" year ago")
    end
  end

  def options(list) do
    Enum.map(list, fn el ->
      content_tag(:option, "", value: el)
    end)
  end

  defp i_peggy_text(form, field, placeholder, opts) do
    content_tag(
      :div,
      [
        text_input(form, field, peggy_field(form, field, placeholder, opts)),
        error_tag(form, field)
      ], class: "control field"
    )
  end

  defp peggy_field(form, field, placeholder, opts) do
    [class, _options] = find_pop_key_value(:class, opts)

    default_options = [
      class: "#{input_error_css_class(form, field)} #{class}",
      autocomplete: :off,
      placeholder: placeholder,
      phx_feedback_for: input_name(form, field),
      phx_debounce: "blur"
    ]

    Keyword.merge(default_options, opts)
  end

  defp find_pop_key_value(key, list) do
    if Enum.any?(list, fn {k, _v} -> k == key end) do
      {key, value} = Enum.find(list, fn {k, _v} -> k == key end)
      list = Enum.reject(list, fn {k, _v} -> k == key end)
      [value, list]
    else
      [nil, list]
    end
  end
end
