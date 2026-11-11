defmodule Tasktree.NodesConcurrencyTest do
  @moduledoc """
  Real concurrency: each task uses its own DB connection (sandbox in :auto mode, so
  data is committed). Nodes are deleted afterwards; events cannot be deleted (append-only
  trigger) so a few rows per run remain in the test DB, keyed by unique node ids.
  """
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Tasktree.{Nodes, Repo}
  alias Tasktree.Nodes.Node

  setup do
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Sandbox.mode(Repo, :auto)
      Repo.delete_all(Tasktree.Edges.Edge)
      Repo.delete_all(Node)
      Sandbox.mode(Repo, :manual)
    end)

    {:ok, n} = Nodes.create("human:t", %{"title" => "race"})
    %{node: n}
  end

  defp race(funs, n \\ 1) do
    barrier = :atomics.new(1, [])

    for f <- List.duplicate(funs, n) |> List.flatten() do
      Task.async(fn ->
        :atomics.add(barrier, 1, 1)
        f.()
      end)
    end
    |> Task.await_many(10_000)
  end

  test "claim race with many contenders: exactly one wins", %{node: n} do
    funs = for i <- 1..8, do: fn -> Nodes.claim("agent:#{i}", n.id, %{}) end
    results = race(funs)
    assert length(Enum.filter(results, &match?({:ok, _}, &1))) == 1
    assert length(Enum.filter(results, &match?({:error, {:claimed, _}}, &1))) == 7
  end

  test "same-version updates: exactly one wins, version ends at 2", %{node: n} do
    funs = for i <- 1..8, do: fn -> Nodes.update("human:t", n.id, 1, %{"title" => "t#{i}"}) end
    results = race(funs)
    assert length(Enum.filter(results, &match?({:ok, _}, &1))) == 1
    assert length(Enum.filter(results, &match?({:error, {:version_conflict, _}}, &1))) == 7
    assert {:ok, %{version: 2}} = Nodes.get(n.id)
  end

  test "concurrent moves into each other never create a cycle" do
    {:ok, a} = Nodes.create("human:t", %{"title" => "a"})
    {:ok, b} = Nodes.create("human:t", %{"title" => "b"})

    results =
      race([
        fn -> Nodes.move("human:t", a.id, 1, %{"parent_id" => b.id}) end,
        fn -> Nodes.move("human:t", b.id, 1, %{"parent_id" => a.id}) end
      ])

    assert [{:ok, _}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert [{:error, :cycle}] = Enum.filter(results, &match?({:error, _}, &1))
  end

  test "concurrent opposing blocks edges never create a cycle" do
    {:ok, a} = Nodes.create("human:t", %{"title" => "a"})
    {:ok, b} = Nodes.create("human:t", %{"title" => "b"})

    results =
      race([
        fn ->
          Tasktree.Edges.add("human:t", %{"from_id" => a.id, "to_id" => b.id, "kind" => "blocks"})
        end,
        fn ->
          Tasktree.Edges.add("human:t", %{"from_id" => b.id, "to_id" => a.id, "kind" => "blocks"})
        end
      ])

    assert [{:ok, _}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert [{:error, :cycle}] = Enum.filter(results, &match?({:error, _}, &1))
  end
end
