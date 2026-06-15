defmodule Peggy.Farms.InvitationTest do
  use ExUnit.Case, async: true

  alias Peggy.Farms.Invitation

  describe "encode_token/1 and decode_token/1" do
    test "round-trip a raw token through a URL-safe string" do
      raw = :crypto.strong_rand_bytes(32)

      encoded = Invitation.encode_token(raw)

      assert is_binary(encoded)
      assert encoded == URI.encode(encoded), "encoded token must be URL-safe"
      assert {:ok, ^raw} = Invitation.decode_token(encoded)
    end

    test "decode_token/1 returns :error on garbage" do
      assert :error = Invitation.decode_token("not a real token!!!")
    end
  end
end
