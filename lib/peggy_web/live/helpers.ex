defmodule PeggyWeb.Helpers do
  use Phoenix.Component

  def work_week(stamp) do
    {y, w} = stamp |> Timex.iso_week()
    y = "#{y}"
    w = String.reverse("0#{w}") |> String.slice(0..1) |> String.reverse()
    "#{y}/#{w}"
  end

  def insert_new_html_newline(str) do
    Phoenix.HTML.html_escape(str || "")
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("\n", "<br/>")
    |> Phoenix.HTML.raw()
  end

  def make_log_delta_to_html(delta) do
    delta
    |> String.replace("&^", "<span>")
    |> String.replace("^&", "</span>")
    |> String.replace("[", "<div class='pl-4'>")
    |> String.replace("]", "</div>")
    |> String.replace("<!", "<span class='text-red-500 line-through'>")
    |> String.replace("!>", "</span>")
    |> String.replace("<$", "<span class='text-green-600'>")
    |> String.replace("$>", "</span>")
  end

  def put_marker_in_diff_log_delta(a1, a2) do
    String.myers_difference(a1, a2)
    |> Enum.map_join(fn {k, v} ->
      case k do
        :del -> "<!#{v}!>"
        :ins -> "<$#{v}$>"
        _ -> v
      end
    end)
  end

  def format_date(date) do
    if is_nil(date) do
      nil
    else
      Timex.format!(Timex.to_date(date), "%d-%m-%Y", :strftime)
    end
  end

  def format_datetime(datetime, com) do
    if is_nil(datetime) do
      nil
    else
      Timex.format!(Timex.to_datetime(datetime, com.timezone), "%d-%m-%Y %H:%M:%S", :strftime)
    end
  end

  def int_or_float_format(n) do
    if(Decimal.eq?(n, Decimal.new("0")),
      do: "",
      else:
        if(Decimal.integer?(n),
          do: Decimal.to_integer(n) |> Number.Delimit.number_to_delimited(precision: 0),
          else: Number.Delimit.number_to_delimited(precision: 4)
        )
    )
  end
end
