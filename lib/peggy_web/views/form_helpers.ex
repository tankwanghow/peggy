defmodule PeggyWeb.FormHelpers do
  @moduledoc """
  Conveniences for translating and building form elements.
  """
  use Phoenix.HTML
  import PeggyWeb.ErrorHelpers
  import PeggyWeb.Gettext

  def peggy_text(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :text] ++ opts)
  end

  def peggy_date(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [onfocus: "(this.type='date')", onblur: "(this.type='text')"] ++ opts)
  end

  def peggy_number(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :number] ++ opts)
  end

  def peggy_email(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :email] ++ opts)
  end

  def peggy_password(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :password] ++ opts)
  end

  def peggy_select(form, field, values, opts \\ []) do
    {got_msg, _options} = Keyword.pop(opts, :got_msg, false)
    content_tag(
      :div,
      [
        select(form, field, values, peggy_field(form, field, "", opts)),
        error_tag(form, field),
        if(got_msg, do: message_tag(form, field), else: [])
      ], class: "control field select"
    )
  end

  def datalist(list, id) do
    content_tag(:datalist, options(list), id: id)
  end

  def datalist_with_ids(list, id, value_key, id_key) do
    content_tag(:datalist, option_with_ids(list, value_key, id_key), id: id)
  end

  def options(list) do
    Enum.map(list, fn el ->
      content_tag(:option, "", value: el)
    end)
  end

  def option_with_ids(list, value_key, id_key) do
    Enum.map(list, fn el ->
      content_tag(:option, "", value: Map.get(el, value_key), data_id: Map.get(el, id_key))
    end)
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

  defp i_peggy_text(form, field, placeholder, opts) do
    {class, options} = Keyword.pop(opts, :class, "")
    {got_msg, _options} = Keyword.pop(options, :got_msg, false)
    content_tag(
      :div,
      [
        text_input(form, field, peggy_field(form, field, placeholder, Keyword.merge(opts, class: "#{class} input"))),
        error_tag(form, field),
        if(got_msg, do: message_tag(form, field), else: [])
      ], class: "control field"
    )
  end

  defp peggy_field(form, field, placeholder, opts) do
    {class, options} = Keyword.pop(opts, :class, "")
    {got_msg, options} = Keyword.pop(options, :got_msg, false)

    default_options = [
      class: "#{input_error_css_class(form, field)} #{class} " <> if(got_msg, do: input_message_css_class(form, field), else: ""),
      autocomplete: :off,
      placeholder: placeholder,
      phx_feedback_for: input_name(form, field),
      phx_debounce: "blur"
    ]

    Keyword.merge(default_options, options)
  end
end
