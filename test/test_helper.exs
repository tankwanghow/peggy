ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Peggy.Repo, :manual)

defmodule TestHelper do
  import Phoenix.LiveViewTest
  use PeggyWeb.ConnCase
  
  def assert_live_search(view, list, field, terms, sel_func, chunk) do
    list
    |> Enum.filter(fn l -> Map.get(l, field) =~ "#{terms}" end)
    |> Enum.chunk_every(chunk)
    |> Enum.each(fn cks ->
      Enum.each(cks, fn ck ->
        assert has_element?(view, sel_func.(ck.code))
      end)

      render_hook(view, "load-more")
    end)
  end
end
