defmodule Tasktree.Position do
  @moduledoc """
  Base-62 fractional index keys (DESIGN.md §3.5).

  Digits are `0-9A-Za-z` (byte order == digit order, so plain string comparison
  orders keys). A valid key is non-empty and does not end in `"0"`; that
  invariant guarantees a key can always be generated between any two keys.
  """

  @digits ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @base 62

  @doc """
  Returns a key strictly between `a` and `b`. `nil` means unbounded on that side.
  Raises `ArgumentError` for invalid keys or when `a >= b`.
  """
  @spec between(String.t() | nil, String.t() | nil) :: String.t()
  def between(a, b) do
    validate!(a)
    validate!(b)

    if a != nil and b != nil and a >= b do
      raise ArgumentError, "expected a < b, got #{inspect(a)} and #{inspect(b)}"
    end

    mid(a || "", b)
  end

  @spec valid?(term()) :: boolean()
  def valid?(key) when is_binary(key) and key != "" do
    String.ends_with?(key, "0") == false and
      key |> :binary.bin_to_list() |> Enum.all?(&(&1 in @digits))
  end

  def valid?(_), do: false

  defp validate!(nil), do: :ok

  defp validate!(key) do
    valid?(key) || raise ArgumentError, "invalid position key: #{inspect(key)}"
    :ok
  end

  # a: "" or a key tail; b: nil (unbounded) or a key tail; a < b.
  defp mid(a, b) when is_binary(b) do
    n = common_prefix_len(a, b)

    if n > 0 do
      binary_part(b, 0, n) <> mid(drop(a, n), drop(b, n))
    else
      mid_first_digit(a, b)
    end
  end

  defp mid(a, nil), do: mid_first_digit(a, nil)

  defp mid_first_digit(a, b) do
    da = digit(a)
    db = if b == nil, do: @base, else: digit(b)

    cond do
      db - da > 1 ->
        <<Enum.at(@digits, div(da + db, 2))>>

      db == da ->
        # Only reachable with a == "" and b starting with "0".
        "0" <> mid("", drop(b, 1))

      b != nil and byte_size(b) > 1 ->
        binary_part(b, 0, 1)

      true ->
        # An empty `a` is implicitly zero-padded, so its tail stays empty.
        a_tail = if a == "", do: "", else: drop(a, 1)
        <<Enum.at(@digits, da)>> <> mid(a_tail, nil)
    end
  end

  defp digit(""), do: 0
  defp digit(<<c, _::binary>>), do: Enum.find_index(@digits, &(&1 == c))

  defp drop(s, n), do: binary_part(s, n, byte_size(s) - n)

  defp common_prefix_len(a, b), do: common_prefix_len(a, b, 0)

  defp common_prefix_len(<<c, ra::binary>>, <<c, rb::binary>>, n),
    do: common_prefix_len(ra, rb, n + 1)

  defp common_prefix_len(_, _, n), do: n
end
