defmodule Tasktree.QueriesTest do
  use Tasktree.DataCase, async: false

  alias Tasktree.{Edges, Nodes, Queries}
  alias Tasktree.Nodes.Node

  @h "human:t"
  @a "agent:a"

  defp mk(attrs \\ %{}) do
    {:ok, n} = Nodes.create(@h, Map.merge(%{"title" => "t"}, attrs))
    n
  end

  defp ids(params) do
    {:ok, %{data: data}} = Queries.list(params)
    Enum.map(data, & &1.id)
  end

  defp sorted(ids), do: Enum.sort(ids)

  defp block(from, to),
    do: {:ok, _} = Edges.add(@h, %{"from_id" => from.id, "to_id" => to.id, "kind" => "blocks"})

  defp move_to(n, state) do
    {:ok, n} =
      Nodes.transition(@h, n.id, n.version, %{"to" => state, "fields" => %{"outcome" => "x"}})

    n
  end

  defp expire_claim(id) do
    past = DateTime.add(DateTime.utc_now(), -60, :second)

    Repo.update_all(from(n in Node, where: n.id == ^id),
      set: [claimed_by: "agent:old", claim_expires_at: past]
    )
  end

  describe "list filters" do
    test "no filters returns everything ordered by id" do
      a = mk()
      b = mk()
      assert ids(%{}) == sorted([a.id, b.id])
    end

    test "state (repeatable = OR)" do
      a = mk()
      b = mk() |> move_to("CANCELLED")

      c =
        mk()
        |> then(fn n ->
          {:ok, n} = Nodes.transition(@h, n.id, n.version, %{"to" => "NEXT"})
          n
        end)

      assert ids(%{"state" => "CANCELLED"}) == [b.id]
      assert ids(%{"state" => ["TODO", "NEXT"]}) == sorted([a.id, c.id])
    end

    test "tag (repeatable = AND)" do
      a = mk(%{"tags" => ["x", "y"]})
      b = mk(%{"tags" => ["x"]})
      _c = mk()
      assert ids(%{"tag" => "x"}) == sorted([a.id, b.id])
      assert ids(%{"tag" => ["x", "y"]}) == [a.id]
      assert ids(%{"tag" => "nope"}) == []
    end

    test "field.<name>, typed by the schema" do
      a = mk(%{"fields" => %{"effort" => 30, "priority" => "A"}})
      _b = mk(%{"fields" => %{"effort" => 5, "priority" => "B"}})
      assert ids(%{"field.effort" => "30"}) == [a.id]
      assert ids(%{"field.priority" => "A", "field.effort" => "30"}) == [a.id]
      assert ids(%{"field.priority" => "A", "field.effort" => "5"}) == []
    end

    test "claimed_by only matches live claims" do
      a = mk()
      b = mk()
      {:ok, _} = Nodes.claim(@a, a.id, %{})
      expire_claim(b.id)
      assert ids(%{"claimed_by" => @a}) == [a.id]
      assert ids(%{"claimed_by" => "agent:old"}) == []
    end

    test "under = descendants, recursively, excluding the root itself" do
      r = mk()
      c1 = mk(%{"parent_id" => r.id})
      g = mk(%{"parent_id" => c1.id})
      _other = mk()
      assert ids(%{"under" => r.id}) == sorted([c1.id, g.id])
      assert ids(%{"under" => g.id}) == []
      assert ids(%{"under" => r.id, "state" => "DONE"}) == []
    end
  end

  describe "derived predicates" do
    test "blocked: non-terminal blocker blocks; terminal blocker does not" do
      blocker = mk()
      target = mk()
      free = mk()
      block(blocker, target)
      assert ids(%{"blocked" => "true"}) == [target.id]
      assert ids(%{"blocked" => "false"}) == sorted([blocker.id, free.id])

      move_to(blocker, "CANCELLED")
      assert ids(%{"blocked" => true}) == []
    end

    test "relates edges do not block" do
      a = mk()
      b = mk()
      {:ok, _} = Edges.add(@h, %{"from_id" => a.id, "to_id" => b.id, "kind" => "relates"})
      assert ids(%{"blocked" => "true"}) == []
    end

    test "claimable: actionable, unblocked, no live claim" do
      ok = mk()
      blocker = mk()
      blocked = mk()
      block(blocker, blocked)
      claimed = mk()
      {:ok, _} = Nodes.claim(@a, claimed.id, %{})
      expired = mk()
      expire_claim(expired.id)
      doing = mk()
      {:ok, _} = Nodes.transition(@h, doing.id, 1, %{"to" => "DOING"})
      done = mk() |> move_to("CANCELLED")
      _ = done

      assert ids(%{"claimable" => "true"}) == sorted([ok.id, blocker.id, expired.id])
      assert ids(%{"claimable" => "false"}) == sorted([blocked.id, claimed.id, doing.id, done.id])
    end

    test "predicates are returned on every row, from the same query" do
      blocker = mk()
      target = mk()
      block(blocker, target)
      {:ok, %{data: data}} = Queries.list(%{})
      by_id = Map.new(data, &{&1.id, &1})
      assert %{blocked: false, claimable: true} = by_id[blocker.id]
      assert %{blocked: true, claimable: false} = by_id[target.id]
    end
  end

  describe "pagination" do
    test "limit and cursor walk all rows exactly once" do
      all = for _ <- 1..5, do: mk().id
      {:ok, %{data: p1, next_cursor: c1}} = Queries.list(%{"limit" => "2"})
      {:ok, %{data: p2, next_cursor: c2}} = Queries.list(%{"limit" => 2, "cursor" => c1})
      {:ok, %{data: p3, next_cursor: c3}} = Queries.list(%{"limit" => 2, "cursor" => c2})
      assert Enum.map(p1 ++ p2 ++ p3, & &1.id) == sorted(all)
      assert [2, 2, 1] == Enum.map([p1, p2, p3], &length/1)
      assert c1 && c2 && c3 == nil
    end

    test "exact fit has no next cursor" do
      mk()
      assert {:ok, %{next_cursor: nil}} = Queries.list(%{"limit" => 1})
    end
  end

  describe "list validation" do
    test "errors" do
      mk()

      for {params, key} <- [
            {%{"bogus" => "1"}, "bogus"},
            {%{"limit" => "0"}, "limit"},
            {%{"limit" => "201"}, "limit"},
            {%{"limit" => "x"}, "limit"},
            {%{"limit" => 1.5}, "limit"},
            {%{"cursor" => ""}, "cursor"},
            {%{"claimable" => "yes"}, "claimable"},
            {%{"blocked" => 1}, "blocked"},
            {%{"state" => 1}, "state"},
            {%{"tag" => []}, "tag"},
            {%{"claimed_by" => ""}, "claimed_by"},
            {%{"under" => "nope"}, "under"},
            {%{"under" => 5}, "under"},
            {%{"field.nope" => "1"}, "field.nope"},
            {%{"field.effort" => "abc"}, "field.effort"},
            {%{"field.deadline" => "tomorrow"}, "field.deadline"},
            {%{"field.priority" => "Z"}, "field.priority"},
            {%{"field.effort" => ["1"]}, "field.effort"}
          ] do
        assert {:error, {:validation_failed, %{^key => _}}} = Queries.list(params),
               inspect(params)
      end
    end
  end

  describe "get" do
    test "node with children (ordered), edges and predicates" do
      p = mk()
      c1 = mk(%{"parent_id" => p.id})
      c2 = mk(%{"parent_id" => p.id})
      other = mk()
      block(other, p)
      {:ok, e2} = Edges.add(@h, %{"from_id" => p.id, "to_id" => c2.id, "kind" => "relates"})

      {:ok, %{node: node, children: kids, edges: %{out: out, in: inn}}} = Queries.get(p.id)
      assert kids == [c1.id, c2.id]
      assert [%{id: id}] = out
      assert id == e2.id
      assert [%{from_id: from}] = inn
      assert from == other.id
      assert %{blocked: true, claimable: false} = node
    end

    test "not_found" do
      assert {:error, :not_found} = Queries.get("nope")
    end
  end

  describe "tree" do
    setup do
      r1 = mk(%{"title" => "r1"})
      r2 = mk(%{"title" => "r2"})
      c1 = mk(%{"parent_id" => r1.id})
      c2 = mk(%{"parent_id" => r1.id})
      g = mk(%{"parent_id" => c1.id})
      gg = mk(%{"parent_id" => g.id})
      %{r1: r1, r2: r2, c1: c1, c2: c2, g: g, gg: gg}
    end

    defp shape(nodes), do: Enum.map(nodes, fn %{node: n, children: c} -> {n.id, shape(c)} end)

    test "default depth 3 returns all roots with two more levels", t do
      {:ok, tree} = Queries.tree(%{})

      # siblings are ordered by position (creation order here), not by id
      assert shape(tree) == [
               {t.r1.id, [{t.c1.id, [{t.g.id, []}]}, {t.c2.id, []}]},
               {t.r2.id, []}
             ]
    end

    test "depth counts levels including the top", t do
      assert {:ok, tree} = Queries.tree(%{"depth" => "1"})
      assert shape(tree) |> Enum.all?(fn {_, kids} -> kids == [] end)
      assert {:ok, [%{children: [_, _]}, _]} = Queries.tree(%{"depth" => 2})
      assert {:ok, tree4} = Queries.tree(%{"depth" => 4})
      assert t.gg.id in (tree4 |> List.flatten() |> flat_ids())
    end

    test "root restricts to one subtree", t do
      assert {:ok, [%{node: %{id: id}} = top]} = Queries.tree(%{"root" => t.c1.id})
      assert id == t.c1.id
      assert shape([top]) == [{t.c1.id, [{t.g.id, [{t.gg.id, []}]}]}]
    end

    test "siblings are ordered by position" do
      p = mk()
      a = mk(%{"parent_id" => p.id})
      b = mk(%{"parent_id" => p.id})
      {:ok, _} = Nodes.move(@h, b.id, 1, %{"parent_id" => p.id, "before_id" => a.id})
      assert {:ok, [%{children: kids}]} = Queries.tree(%{"root" => p.id})
      assert Enum.map(kids, & &1.node.id) == [b.id, a.id]
    end

    test "nodes carry predicates", t do
      {:ok, _} = Edges.add(@h, %{"from_id" => t.r2.id, "to_id" => t.c2.id, "kind" => "blocks"})
      {:ok, tree} = Queries.tree(%{"root" => t.c2.id})
      assert [%{node: %{blocked: true}}] = tree
    end

    test "errors" do
      assert {:error, :not_found} = Queries.tree(%{"root" => "nope"})
      assert {:error, {:validation_failed, %{"depth" => _}}} = Queries.tree(%{"depth" => "0"})
      assert {:error, {:validation_failed, %{"depth" => _}}} = Queries.tree(%{"depth" => "x"})
      assert {:error, {:validation_failed, %{"root" => _}}} = Queries.tree(%{"root" => 5})
      assert {:error, {:validation_failed, %{"bogus" => _}}} = Queries.tree(%{"bogus" => 1})
    end

    defp flat_ids(list),
      do: Enum.flat_map(list, fn %{node: n, children: c} -> [n.id | flat_ids(c)] end)
  end
end
