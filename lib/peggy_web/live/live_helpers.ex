defmodule PeggyWeb.LiveHelpers do
  def set_locale(%{"locale" => locale}) do
    Gettext.put_locale(PeggyWeb.Gettext, if(locale, do: locale, else: "en"))
  end
end
