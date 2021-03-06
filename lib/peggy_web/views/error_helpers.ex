defmodule PeggyWeb.ErrorHelpers do
  @moduledoc """
  Conveniences for translating and building error messages.
  """

  use Phoenix.HTML

  @doc """
  Generates tag for inlined form input errors.
  """
  def error_tag(form, field) do
    Enum.map(Keyword.get_values(form.errors, field), fn error ->
      content_tag(:span, translate_error(error),
        id: Atom.to_string(field) <> "-invalid-feedback",
        class: "is-danger help invalid-feedback",
        phx_feedback_for: input_name(form, field)
      )
    end)
  end

  def input_error_css_class(form, field) do
    if Enum.count(Keyword.get_values(form.errors, field)) > 0 do
      "is-danger"
    else
      ""
    end
  end

  def message_tag(form, field) do
    Enum.map(Keyword.get_values(form.source.messages, field), fn msg ->
      {text, style} = msg

      content_tag(:span, translate_message(text),
        id: Atom.to_string(field) <> "-message-feedback",
        class: "#{style} help message-feedback",
        phx_feedback_for: input_name(form, field)
      )
    end)
  end

  def input_message_css_class(form, field) do
    Enum.map(Keyword.get_values(form.source.messages, field), fn msg ->
      {_text, style} = msg
      style
    end)
    |> List.flatten()
    |> Enum.join(" ")
  end

  def translate_message(text) do
    Gettext.dgettext(PeggyWeb.Gettext, "errors", text)
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate "is invalid" in the "errors" domain
    #     dgettext("errors", "is invalid")
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # Because the error messages we show in our forms and APIs
    # are defined inside Ecto, we need to translate them dynamically.
    # This requires us to call the Gettext module passing our gettext
    # backend as first argument.
    #
    # Note we use the "errors" domain, which means translations
    # should be written to the errors.po file. The :count option is
    # set by Ecto and indicates we should also apply plural rules.
    if count = opts[:count] do
      Gettext.dngettext(PeggyWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(PeggyWeb.Gettext, "errors", msg, opts)
    end
  end
end
