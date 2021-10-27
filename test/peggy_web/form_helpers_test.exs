defmodule PeggyWeb.FormHelpersTest do
  alias PeggyWeb.FormHelpers
  use ExUnit.Case

  @day 24 * 60 * 60

  describe "Form Helpers ago/1" do
    test "never", do: assert "never" == FormHelpers.ago(nil)
    test "today", do: assert "today" == FormHelpers.ago(NaiveDateTime.utc_now)
    test "yesterday", do: assert "yesterday" == FormHelpers.ago(NaiveDateTime.add(NaiveDateTime.utc_now, -1 * @day))
    test "14 days ago", do: assert "14 days ago" == FormHelpers.ago(NaiveDateTime.add(NaiveDateTime.utc_now, -14 * @day))
    test "2 weeks ago", do: assert "2 weeks ago" == FormHelpers.ago(NaiveDateTime.add(NaiveDateTime.utc_now, -15 * @day))
    test "8 weeks ago", do: assert "8 weeks ago" == FormHelpers.ago(NaiveDateTime.add(NaiveDateTime.utc_now, -59 * @day))
    test "2 months ago", do: assert "2 months ago" == FormHelpers.ago(NaiveDateTime.add(NaiveDateTime.utc_now, -60 * @day))
    test "12 months ago", do: assert "12 months ago" == FormHelpers.ago(NaiveDateTime.add(NaiveDateTime.utc_now, -364 * @day))
    test "1 year ago", do: assert "1 year ago" == FormHelpers.ago(NaiveDateTime.add(NaiveDateTime.utc_now, -365 * @day))
    test "5 years ago", do: assert "5 years ago" == FormHelpers.ago(NaiveDateTime.add(NaiveDateTime.utc_now, -365 * 5 * @day))
  end

end
