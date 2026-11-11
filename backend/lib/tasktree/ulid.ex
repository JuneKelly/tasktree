defmodule Tasktree.ULID do
  @moduledoc """
  Minimal ULID generator: 48-bit ms timestamp + 80 random bits, Crockford base32,
  26 chars. Lexicographic order follows creation time (ms granularity).
  """

  @alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  @spec generate() :: String.t()
  def generate do
    <<n::128>> = <<System.system_time(:millisecond)::48, :crypto.strong_rand_bytes(10)::binary>>
    encode(n, 26, [])
  end

  defp encode(_n, 0, acc), do: List.to_string(acc)

  defp encode(n, count, acc) do
    encode(Bitwise.bsr(n, 5), count - 1, [Enum.at(@alphabet, Bitwise.band(n, 31)) | acc])
  end
end
