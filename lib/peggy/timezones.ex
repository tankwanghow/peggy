defmodule Peggy.Timezones do
  @moduledoc """
  Curated list of IANA timezone identifiers offered in farm forms.

  We don't ship `tzdata` as a dependency (the app doesn't need
  arbitrary historical zone conversions), so this is a hand-picked
  set covering common regions with extra coverage for South-East Asia
  where the target users are.

  Add zones here as needed — keep the list ordered by UTC offset so
  the dropdown is easy to scan.
  """

  @zones [
    # ── UTC anchor ─────────────────────────────────────────────
    "UTC",

    # ── Americas ───────────────────────────────────────────────
    "America/Los_Angeles",
    "America/Denver",
    "America/Chicago",
    "America/New_York",
    "America/Sao_Paulo",
    "America/Argentina/Buenos_Aires",

    # ── Europe / Africa ────────────────────────────────────────
    "Europe/London",
    "Europe/Lisbon",
    "Africa/Lagos",
    "Europe/Paris",
    "Europe/Berlin",
    "Europe/Madrid",
    "Europe/Rome",
    "Europe/Amsterdam",
    "Africa/Johannesburg",
    "Europe/Istanbul",
    "Europe/Moscow",

    # ── Middle East / South Asia ───────────────────────────────
    "Asia/Dubai",
    "Asia/Karachi",
    "Asia/Kolkata",
    "Asia/Colombo",
    "Asia/Dhaka",
    "Asia/Yangon",

    # ── South-East Asia (primary user base) ────────────────────
    "Asia/Bangkok",
    "Asia/Jakarta",
    "Asia/Ho_Chi_Minh",
    "Asia/Kuala_Lumpur",
    "Asia/Singapore",
    "Asia/Manila",
    "Asia/Makassar",
    "Asia/Jayapura",

    # ── East Asia ──────────────────────────────────────────────
    "Asia/Shanghai",
    "Asia/Hong_Kong",
    "Asia/Taipei",
    "Asia/Tokyo",
    "Asia/Seoul",

    # ── Oceania ────────────────────────────────────────────────
    "Australia/Perth",
    "Australia/Adelaide",
    "Australia/Sydney",
    "Pacific/Auckland"
  ]

  @doc "All offered timezones."
  def list, do: @zones

  @doc """
  Options shape for `<.input type=\"select\">`. Each option is
  `{label, value}` where label is the same as the IANA id (no
  pretty-printing — admins recognise these).
  """
  def options, do: Enum.map(@zones, &{&1, &1})

  @doc "True if the given string is one of the offered zones."
  def known?(tz) when is_binary(tz), do: tz in @zones
  def known?(_), do: false
end
