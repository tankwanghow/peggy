defmodule Util do
  def attempt(method, field) do
    if method do
      Map.get(method, field)
    else
      nil
    end
  end
end
