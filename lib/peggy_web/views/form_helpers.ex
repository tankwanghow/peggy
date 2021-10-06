defmodule PeggyWeb.FormHelpers do
  @moduledoc """
  Conveniences for translating and building form elements.
  """
  use Phoenix.HTML
  import PeggyWeb.ErrorHelpers

  def peggy_text(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :text] ++ opts)
  end

  def peggy_date(form, field, placeholder, opts \\ []) do
    i_peggy_text(form, field, placeholder, [type: :date] ++ opts)
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
    content_tag(:div, [select(form, field, values, opts), error_tag(form, field)], class: "select field control")
  end

  def datalist(list, id) do
    content_tag(:datalist, options(list), id: id)
  end

  def options(list) do
    Enum.map list, fn el ->
      content_tag(:option, "", value: el)
    end
  end

  defp i_peggy_text(form, field, placeholder, opts) do
    [col_class, opts] = find_pop_key_value(:col_class, opts)
    [class, opts] = find_pop_key_value(:class, opts)

    opt = [class: "#{class} input #{input_error_css_class(form, field)}", autocomplete: :off,
           placeholder: placeholder, phx_feedback_for: input_name(form, field), phx_debounce: "blur"]

    if col_class != "" do
      peggy_column(
        content_tag(:div,
          [text_input(form, field, opt ++ opts),
          error_tag(form, field)],
          class: "field control"),
        col_class)
    else
      content_tag(:div,
        [text_input(form, field, opt ++ opts),
         error_tag(form, field)],
        class: "field control")
    end
  end

  defp find_pop_key_value(key, list) do
    if Enum.any?(list, fn {k, _v} -> k == key end) do
      {key, value} = Enum.find(list, fn {k, _v} -> k == key end)
      list = Enum.reject(list, fn {k, _v} -> k == key end)
      [value, list]
    else
      ["", list]
    end
  end

  defp peggy_column(input_tag, column_class) do
    content_tag(:div, input_tag,
      class: "column #{column_class}"
    )
  end
end
