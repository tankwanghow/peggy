defmodule Peggy.Breeding.LitterCapsTest do
  @moduledoc """
  Upper-bound guards on litter-size fields. Caps were raised to admit
  real hyperprolific litters that legacy imports surfaced (born_alive up
  to 25, weaned_count up to 20) while still rejecting gross data errors.
  """
  use ExUnit.Case, async: true

  alias Peggy.Breeding.{Farrowing, Weaning}

  defp born_alive_error?(count) do
    %Farrowing{}
    |> Farrowing.changeset(%{"born_alive" => count})
    |> Map.fetch!(:errors)
    |> Keyword.has_key?(:born_alive)
  end

  defp weaned_count_error?(count) do
    %Weaning{}
    |> Weaning.changeset(%{"weaned_count" => count})
    |> Map.fetch!(:errors)
    |> Keyword.has_key?(:weaned_count)
  end

  describe "Farrowing.changeset born_alive cap" do
    test "accepts a 25-piglet litter" do
      refute born_alive_error?(25)
    end

    test "rejects 26 and above" do
      assert born_alive_error?(26)
    end

    test "still rejects negatives" do
      assert born_alive_error?(-1)
    end
  end

  describe "Weaning.changeset weaned_count cap" do
    test "accepts 20 weaned" do
      refute weaned_count_error?(20)
    end

    test "rejects 21 and above" do
      assert weaned_count_error?(21)
    end
  end
end
