defmodule Tasktree.EdgesTest do
  use Tasktree.DataCase, async: false

  alias Tasktree.{Edges, Events, Nodes}
  alias Tasktree.Edges.Edge

  @human "human:t"
  @agent "agent:a"

  defp mk(attrs \\ %{}) do
    {:ok, n} = Nodes.create(@human, Map.merge(%{"title" => "t"}, attrs))
    n
  end

  defp edge(from, to, kind \\ "blocks"),
    do: %{"from_id" => from.id, "to_id" => to.id, "kind" => kind}

  defp ops(id), do: Enum.map(Events.list_for_node(id), & &1.op)

  describe "add" do
    test "happy path: edge row, one event per endpoint with the actor" do
      a = mk()
      b = mk()
      {:ok, e} = Edges.add(@agent, edge(a, b))
      assert %Edge{kind: :blocks} = Repo.get!(Edge, e.id)

      for n <- [a, b] do
        assert [:create, :edge_add] = ops(n.id)
        ev = n.id |> Events.list_for_node() |> List.last()
        assert %{actor: @agent, payload: %{"edge" => %{"id" => id, "kind" => "blocks"}}} = ev
        assert id == e.id
      end
    end

    test "relates edges may form cycles; both kinds may coexist for a pair" do
      a = mk()
      b = mk()
      assert {:ok, _} = Edges.add(@human, edge(a, b, "relates"))
      assert {:ok, _} = Edges.add(@human, edge(b, a, "relates"))
      assert {:ok, _} = Edges.add(@human, edge(a, b, "blocks"))
    end

    test "blocks cycles are rejected: direct, and transitive" do
      [a, b, c, d] = for _ <- 1..4, do: mk()
      {:ok, _} = Edges.add(@human, edge(a, b))
      {:ok, _} = Edges.add(@human, edge(b, c))
      assert {:error, :cycle} = Edges.add(@human, edge(b, a))
      assert {:error, :cycle} = Edges.add(@human, edge(c, a))
      assert {:ok, _} = Edges.add(@human, edge(a, c))
      assert {:ok, _} = Edges.add(@human, edge(c, d))
      assert {:error, :cycle} = Edges.add(@human, edge(d, a))
      assert Repo.aggregate(Edge, :count) == 4
    end

    test "a rejected cycle writes no event" do
      a = mk()
      b = mk()
      {:ok, _} = Edges.add(@human, edge(a, b))
      {:error, :cycle} = Edges.add(@human, edge(b, a))
      assert ops(a.id) == [:create, :edge_add]
    end

    test "validation errors" do
      a = mk()
      b = mk()
      ok = edge(a, b)
      assert {:error, {:validation_failed, %{"x" => _}}} = Edges.add(@human, Map.put(ok, "x", 1))

      assert {:error, {:validation_failed, %{"kind" => _}}} =
               Edges.add(@human, Map.put(ok, "kind", "bogus"))

      assert {:error, {:validation_failed, %{"kind" => _}}} =
               Edges.add(@human, Map.delete(ok, "kind"))

      assert {:error, {:validation_failed, %{"from_id" => _}}} =
               Edges.add(@human, Map.delete(ok, "from_id"))

      assert {:error, {:validation_failed, %{"to_id" => _}}} =
               Edges.add(@human, Map.put(ok, "to_id", "nope"))

      assert {:error, {:validation_failed, %{"from_id" => _}}} =
               Edges.add(@human, Map.put(ok, "from_id", "nope"))

      assert {:error, {:validation_failed, %{"to_id" => _}}} = Edges.add(@human, edge(a, a))
    end

    test "duplicate edge is a validation error" do
      a = mk()
      b = mk()
      {:ok, _} = Edges.add(@human, edge(a, b))

      assert {:error, {:validation_failed, %{"kind" => "edge already exists"}}} =
               Edges.add(@human, edge(a, b))

      assert ops(a.id) == [:create, :edge_add]
    end
  end

  describe "remove" do
    test "happy path: row gone, events recorded, cycle-closing edge now allowed" do
      a = mk()
      b = mk()
      {:ok, e} = Edges.add(@human, edge(a, b))
      assert {:ok, %Edge{id: id}} = Edges.remove(@agent, e.id)
      assert id == e.id
      refute Repo.get(Edge, e.id)

      for n <- [a, b] do
        assert [:create, :edge_add, :edge_remove] = ops(n.id)
        assert %{actor: @agent} = n.id |> Events.list_for_node() |> List.last()
      end

      assert {:ok, _} = Edges.add(@human, edge(b, a))
    end

    test "not_found" do
      assert {:error, :not_found} = Edges.remove(@human, "nope")
    end
  end

  test "move-under-descendant is rejected even with edges present" do
    a = mk()
    b = mk(%{"parent_id" => a.id})
    {:ok, _} = Edges.add(@human, edge(a, b))
    assert {:error, :cycle} = Nodes.move(@human, a.id, 1, %{"parent_id" => b.id})
  end
end
