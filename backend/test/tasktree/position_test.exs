defmodule Tasktree.PositionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Tasktree.Position

  defp key_gen do
    gen all(
          body <- list_of(integer(0..61), max_length: 6),
          last <- integer(1..61)
        ) do
      (body ++ [last])
      |> Enum.map(
        &Enum.at(~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", &1)
      )
      |> List.to_string()
    end
  end

  property "between(a, b) is valid and strictly between" do
    check all(a <- key_gen(), b <- key_gen(), a != b) do
      {lo, hi} = if a < b, do: {a, b}, else: {b, a}
      m = Position.between(lo, hi)
      assert Position.valid?(m)
      assert lo < m and m < hi
    end
  end

  property "append and prepend" do
    check all(a <- key_gen()) do
      assert Position.valid?(Position.between(a, nil))
      assert Position.between(a, nil) > a
      assert Position.valid?(Position.between(nil, a))
      assert Position.between(nil, a) < a
    end
  end

  property "repeated insertion at the same spot never fails or collides" do
    check all(dirs <- list_of(member_of([:left, :right, :append, :prepend]), max_length: 60)) do
      keys =
        Enum.reduce(dirs, [Position.between(nil, nil)], fn dir, [h | _] = acc ->
          # keep sorted; insert relative to the whole list
          sorted = Enum.sort(acc)
          first = hd(sorted)
          last = List.last(sorted)

          new =
            case dir do
              :append -> Position.between(last, nil)
              :prepend -> Position.between(nil, first)
              :right -> Position.between(h, Enum.find(sorted, &(&1 > h)))
              :left -> Position.between(Enum.reverse(sorted) |> Enum.find(&(&1 < h)), h)
            end

          [new | acc]
        end)

      assert length(Enum.uniq(keys)) == length(keys)
      assert Enum.all?(keys, &Position.valid?/1)
    end
  end

  test "between(nil, nil) is a valid key" do
    assert Position.valid?(Position.between(nil, nil))
  end

  test "keys with leading zeros" do
    m = Position.between(nil, "01")
    assert Position.valid?(m) and m < "01"
  end

  test "rejects a >= b" do
    assert_raise ArgumentError, fn -> Position.between("b", "a") end
    assert_raise ArgumentError, fn -> Position.between("a", "a") end
  end

  test "rejects invalid keys" do
    for bad <- ["", "a0", "a-b", "é"] do
      assert_raise ArgumentError, fn -> Position.between(bad, nil) end
    end
  end
end
