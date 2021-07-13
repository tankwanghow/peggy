defmodule PeggyWeb.FormHelpers do
  @moduledoc """
  Conveniences for translating and building form elements.
  """

  use Phoenix.HTML

  import PeggyWeb.ErrorHelpers

  def peggy_text(form, field, placeholder, opts \\ []) do
    opt = [class: "input #{input_error_css_class(form, field)}",
           placeholder: placeholder, phx_feedback_for: input_name(form, field)]
    content_tag(:p,
      [text_input(form, field, opt ++ opts),
      error_tag(form, field)],
      class: "field control")
  end

  def peggy_text_column(form, field, placeholder, column_class, opts \\[]) do
    content_tag(:div, peggy_text(form, field, placeholder, opts),
      class: "column #{column_class}"
    )
  end

  def peggy_email(form, field, placeholder, opts \\ []) do
    opt = [class: "input #{input_error_css_class(form, field)}",
           placeholder: placeholder, phx_feedback_for: input_name(form, field)]
    content_tag(:p,
      [email_input(form, field, opt ++ opts),
      error_tag(form, field)],
      class: "field control")
  end

  def peggy_password(form, field, placeholder, opts \\ []) do
    opt = [class: "input #{input_error_css_class(form, field)}",
           placeholder: placeholder, phx_feedback_for: input_name(form, field)]
    content_tag(:p,
      [password_input(form, field, opt ++ opts),
      error_tag(form, field)],
      class: "field control")
  end
end
