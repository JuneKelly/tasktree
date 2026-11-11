defmodule Tasktree.NodesTest do
  use Tasktree.DataCase, async: false

  alias Tasktree.{Events, Nodes}
  alias Tasktree.Nodes.Node

  @human "human:t"
  @agent "agent:a"
  @agent2 "agent:b"

  defp mk(attrs \\ %{}, actor \\ @human) do
    {:ok, n} = Nodes.create(actor, Map.merge(%{"title" => "t"}, attrs))
    n
  end

  defp ops(id), do: Enum.map(Events.list_for_node(id), & &1.op)
  defp last_event(id), do: id |> Events.list_for_node() |> List.last()

  defp children(parent_id) do
    q =
      if parent_id,
        do: from(n in Node, where: n.parent_id == ^parent_id),
        else: from(n in Node, where: is_nil(n.parent_id))

    Repo.all(from n in q, order_by: [n.position, n.id], select: n.id)
  end

  defp expire_claim(id, holder) do
    past = DateTime.add(DateTime.utc_now(), -60, :second)

    Repo.update_all(from(n in Node, where: n.id == ^id),
      set: [claimed_by: holder, claim_expires_at: past]
    )
  end

  defp doing(n) do
    {:ok, n} = Nodes.transition(@human, n.id, n.version, %{"to" => "DOING"})
    n
  end

  describe "create" do
    test "happy path: initial state, defaults, create event" do
      {:ok, n} =
        Nodes.create(@agent, %{
          "title" => "x",
          "tags" => ["a", "a", "b"],
          "fields" => %{"effort" => 5}
        })

      assert %{state: "TODO", body: "", version: 1, tags: ["a", "b"], fields: %{"effort" => 5}} =
               n

      assert [%{op: :create, actor: @agent, payload: %{"before" => %{}, "after" => after_}}] =
               Events.list_for_node(n.id)

      assert after_["title"] == "x" and after_["state"] == "TODO"
    end

    test "appends, and after_id inserts between siblings" do
      a = mk()
      c = mk()
      b = mk(%{"after_id" => a.id})
      assert children(nil) == [a.id, b.id, c.id]
    end

    test "children under a parent" do
      p = mk()
      c = mk(%{"parent_id" => p.id})
      assert c.parent_id == p.id
      assert children(p.id) == [c.id]
    end

    test "validation errors" do
      assert {:error, {:validation_failed, %{"title" => _}}} = Nodes.create(@human, %{})

      assert {:error, {:validation_failed, %{"title" => _}}} =
               Nodes.create(@human, %{"title" => ""})

      assert {:error, {:validation_failed, %{"bogus" => _}}} =
               Nodes.create(@human, %{"title" => "x", "bogus" => 1})

      assert {:error, {:validation_failed, %{"fields.nope" => _}}} =
               Nodes.create(@human, %{"title" => "x", "fields" => %{"nope" => 1}})

      assert {:error, {:validation_failed, %{"fields.effort" => _}}} =
               Nodes.create(@human, %{"title" => "x", "fields" => %{"effort" => "x"}})

      assert {:error, {:validation_failed, %{"tags" => _}}} =
               Nodes.create(@human, %{"title" => "x", "tags" => [1]})

      assert {:error, {:validation_failed, %{"parent_id" => _}}} =
               Nodes.create(@human, %{"title" => "x", "parent_id" => "nope"})

      other_parent = mk()
      child = mk(%{"parent_id" => other_parent.id})

      assert {:error, {:validation_failed, %{"after_id/before_id" => _}}} =
               Nodes.create(@human, %{"title" => "x", "after_id" => child.id})
    end

    test "failed create writes nothing" do
      before_count = Repo.aggregate(Node, :count)
      assert {:error, _} = Nodes.create(@human, %{})
      assert Repo.aggregate(Node, :count) == before_count
    end
  end

  describe "update" do
    test "happy path bumps version and records a diff event" do
      n = mk()

      {:ok, u} =
        Nodes.update(@agent, n.id, 1, %{
          "title" => "new",
          "tags" => ["x"],
          "fields" => %{"effort" => 3}
        })

      assert %{title: "new", version: 2, tags: ["x"], fields: %{"effort" => 3}} = u
      e = last_event(n.id)

      assert %{
               op: :update,
               actor: @agent,
               payload: %{"before" => %{"title" => "t"}, "after" => %{"title" => "new"}}
             } = e
    end

    test "null removes a field" do
      n = mk(%{"fields" => %{"effort" => 3, "assignee" => "me"}})
      {:ok, u} = Nodes.update(@human, n.id, 1, %{"fields" => %{"effort" => nil}})
      assert u.fields == %{"assignee" => "me"}
    end

    test "removing a field required by the current state is rejected" do
      n = doing(mk())

      {:ok, d} =
        Nodes.transition(@human, n.id, n.version, %{
          "to" => "DONE",
          "fields" => %{"outcome" => "ok"}
        })

      assert {:error, {:validation_failed, %{"fields" => _}}} =
               Nodes.update(@human, d.id, d.version, %{"fields" => %{"outcome" => nil}})
    end

    test "no-op changes nothing: no event, no version bump" do
      n = mk()
      assert {:ok, %{version: 1}} = Nodes.update(@human, n.id, 1, %{"title" => "t"})
      assert ops(n.id) == [:create]
    end

    test "errors" do
      n = mk()
      assert {:error, :not_found} = Nodes.update(@human, "nope", 1, %{"title" => "x"})

      assert {:error, {:validation_failed, %{"bogus" => _}}} =
               Nodes.update(@human, n.id, 1, %{"bogus" => 1})

      assert {:error, {:validation_failed, %{"attrs" => _}}} = Nodes.update(@human, n.id, 1, %{})

      assert {:error, {:validation_failed, %{"title" => _}}} =
               Nodes.update(@human, n.id, 1, %{"title" => ""})

      assert {:error, {:validation_failed, %{"fields" => _}}} =
               Nodes.update(@human, n.id, 1, %{"fields" => []})

      assert {:error, {:validation_failed, %{"fields.nope" => _}}} =
               Nodes.update(@human, n.id, 1, %{"fields" => %{"nope" => 1}})

      assert {:error, {:version_conflict, %Node{version: 1}}} =
               Nodes.update(@human, n.id, 7, %{"title" => "x"})

      assert ops(n.id) == [:create]
    end

    test "claimed by another live actor" do
      n = mk()
      {:ok, _} = Nodes.claim(@agent, n.id, %{})

      assert {:error, {:claimed, %{"claimed_by" => @agent}}} =
               Nodes.update(@human, n.id, 2, %{"title" => "x"})

      assert {:ok, _} = Nodes.update(@agent, n.id, 2, %{"title" => "x"})
    end

    test "expired claim is cleared lazily with a claim_expired event" do
      n = mk()
      expire_claim(n.id, @agent)
      {:ok, u} = Nodes.update(@human, n.id, 1, %{"title" => "x"})
      assert u.claimed_by == nil and u.claim_expires_at == nil
      assert ops(n.id) == [:create, :claim_expired, :update]

      assert %{payload: %{"before" => %{"claimed_by" => @agent}}} =
               Enum.at(Events.list_for_node(n.id), 1)
    end
  end

  describe "transition" do
    test "happy path" do
      n = mk()
      {:ok, t} = Nodes.transition(@agent, n.id, 1, %{"to" => "DOING"})
      assert %{state: "DOING", version: 2} = t

      assert %{
               op: :transition,
               payload: %{"before" => %{"state" => "TODO"}, "after" => %{"state" => "DOING"}}
             } = last_event(n.id)
    end

    test "DONE needs outcome, from the node or the request" do
      n = doing(mk())

      assert {:error, {:validation_failed, %{"fields" => _}}} =
               Nodes.transition(@human, n.id, n.version, %{"to" => "DONE"})

      assert {:ok, %{state: "DONE", fields: %{"outcome" => "ok"}}} =
               Nodes.transition(@human, n.id, n.version, %{
                 "to" => "DONE",
                 "fields" => %{"outcome" => "ok"}
               })

      m = mk(%{"fields" => %{"outcome" => "pre"}}) |> doing()

      assert {:ok, %{state: "DONE"}} =
               Nodes.transition(@human, m.id, m.version, %{"to" => "DONE"})
    end

    test "errors" do
      n = mk()

      assert {:error, {:invalid_transition, %{"from" => "TODO", "to" => "DONE"}}} =
               Nodes.transition(@human, n.id, 1, %{
                 "to" => "DONE",
                 "fields" => %{"outcome" => "x"}
               })

      assert {:error, {:validation_failed, %{"to" => _}}} =
               Nodes.transition(@human, n.id, 1, %{"to" => "BOGUS"})

      assert {:error, {:validation_failed, %{"to" => _}}} = Nodes.transition(@human, n.id, 1, %{})

      assert {:error, {:validation_failed, %{"x" => _}}} =
               Nodes.transition(@human, n.id, 1, %{"to" => "NEXT", "x" => 1})

      assert {:error, {:validation_failed, %{"fields.nope" => _}}} =
               Nodes.transition(@human, n.id, 1, %{"to" => "NEXT", "fields" => %{"nope" => 1}})

      assert {:error, {:version_conflict, _}} =
               Nodes.transition(@human, n.id, 9, %{"to" => "NEXT"})

      assert {:error, :not_found} = Nodes.transition(@human, "nope", 1, %{"to" => "NEXT"})
      {:ok, _} = Nodes.claim(@agent, n.id, %{})
      assert {:error, {:claimed, _}} = Nodes.transition(@human, n.id, 2, %{"to" => "NEXT"})
    end
  end

  describe "move" do
    test "reparent and reorder, with a move event" do
      a = mk()
      b = mk()
      c = mk()
      {:ok, m} = Nodes.move(@agent, c.id, 1, %{"parent_id" => nil, "before_id" => a.id})
      assert m.version == 2
      assert children(nil) == [c.id, a.id, b.id]
      {:ok, _} = Nodes.move(@agent, c.id, 2, %{"parent_id" => nil, "after_id" => a.id})
      assert children(nil) == [a.id, c.id, b.id]

      assert %{op: :move, actor: @agent, payload: %{"after" => %{"position" => _}}} =
               last_event(c.id)

      {:ok, moved} = Nodes.move(@human, b.id, 1, %{"parent_id" => a.id})
      assert moved.parent_id == a.id and children(a.id) == [b.id]
      {:ok, back} = Nodes.move(@human, b.id, 2, %{"parent_id" => nil})
      assert back.parent_id == nil
    end

    test "cycles are rejected" do
      a = mk()
      b = mk(%{"parent_id" => a.id})
      c = mk(%{"parent_id" => b.id})
      assert {:error, :cycle} = Nodes.move(@human, a.id, 1, %{"parent_id" => a.id})
      assert {:error, :cycle} = Nodes.move(@human, a.id, 1, %{"parent_id" => c.id})
      assert ops(a.id) == [:create]
    end

    test "errors" do
      a = mk()
      b = mk()
      assert {:error, :not_found} = Nodes.move(@human, "nope", 1, %{"parent_id" => nil})

      assert {:error, {:validation_failed, %{"parent_id" => _}}} =
               Nodes.move(@human, a.id, 1, %{})

      assert {:error, {:validation_failed, %{"parent_id" => _}}} =
               Nodes.move(@human, a.id, 1, %{"parent_id" => "nope"})

      assert {:error, {:validation_failed, %{"after_id" => _}}} =
               Nodes.move(@human, a.id, 1, %{
                 "parent_id" => nil,
                 "after_id" => b.id,
                 "before_id" => b.id
               })

      assert {:error, {:validation_failed, %{"after_id/before_id" => _}}} =
               Nodes.move(@human, a.id, 1, %{"parent_id" => nil, "after_id" => a.id})

      assert {:error, {:validation_failed, %{"after_id/before_id" => _}}} =
               Nodes.move(@human, a.id, 1, %{"parent_id" => b.id, "after_id" => b.id})

      assert {:error, {:version_conflict, _}} = Nodes.move(@human, a.id, 5, %{"parent_id" => nil})
      {:ok, _} = Nodes.claim(@agent, a.id, %{})
      assert {:error, {:claimed, _}} = Nodes.move(@human, a.id, 2, %{"parent_id" => b.id})
    end
  end

  describe "claim" do
    test "happy path, renewal, and claim event" do
      n = mk()
      {:ok, c} = Nodes.claim(@agent, n.id, %{"ttl_seconds" => 60})
      assert c.claimed_by == @agent and c.version == 2
      assert DateTime.diff(c.claim_expires_at, DateTime.utc_now()) in 58..60
      {:ok, r} = Nodes.claim(@agent, n.id, %{"ttl_seconds" => 600})
      assert DateTime.compare(r.claim_expires_at, c.claim_expires_at) == :gt
      assert ops(n.id) == [:create, :claim, :claim]
    end

    test "default ttl is 900s" do
      n = mk()
      {:ok, c} = Nodes.claim(@agent, n.id, %{})
      assert DateTime.diff(c.claim_expires_at, DateTime.utc_now()) in 898..900
    end

    test "another live holder -> claimed with holder in details" do
      n = mk()
      {:ok, c} = Nodes.claim(@agent, n.id, %{})

      assert {:error, {:claimed, %{"claimed_by" => @agent, "claim_expires_at" => exp}}} =
               Nodes.claim(@agent2, n.id, %{})

      assert exp == c.claim_expires_at
    end

    test "expired claim can be taken over, recording claim_expired" do
      n = mk()
      expire_claim(n.id, @agent)
      {:ok, c} = Nodes.claim(@agent2, n.id, %{})
      assert c.claimed_by == @agent2
      assert ops(n.id) == [:create, :claim_expired, :claim]
    end

    test "errors" do
      n = mk()
      assert {:error, :not_found} = Nodes.claim(@agent, "nope", %{})

      for bad <- [0, -1, 86_401, "5", 1.5] do
        assert {:error, {:validation_failed, %{"ttl_seconds" => _}}} =
                 Nodes.claim(@agent, n.id, %{"ttl_seconds" => bad})
      end

      assert {:error, {:validation_failed, %{"x" => _}}} = Nodes.claim(@agent, n.id, %{"x" => 1})
      assert {:ok, _} = Nodes.claim(@agent, n.id, %{"ttl_seconds" => 86_400})
    end
  end

  describe "release" do
    test "holder releases" do
      n = mk()
      {:ok, _} = Nodes.claim(@agent, n.id, %{})
      {:ok, r} = Nodes.release(@agent, n.id, %{})
      assert r.claimed_by == nil and r.claim_expires_at == nil and r.version == 3
      assert %{op: :release, actor: @agent} = last_event(n.id)
    end

    test "other live holder -> claimed; human can force; agent cannot" do
      n = mk()
      {:ok, _} = Nodes.claim(@agent, n.id, %{})
      assert {:error, {:claimed, %{"claimed_by" => @agent}}} = Nodes.release(@agent2, n.id, %{})

      assert {:error, {:validation_failed, %{"force" => _}}} =
               Nodes.release(@agent2, n.id, %{"force" => true})

      assert {:ok, %{claimed_by: nil}} = Nodes.release(@human, n.id, %{"force" => true})
    end

    test "errors" do
      n = mk()
      assert {:error, :not_found} = Nodes.release(@agent, "nope", %{})
      assert {:error, {:validation_failed, %{"claim" => _}}} = Nodes.release(@agent, n.id, %{})
      expire_claim(n.id, @agent2)
      assert {:error, {:validation_failed, %{"claim" => _}}} = Nodes.release(@agent, n.id, %{})

      assert {:error, {:validation_failed, %{"force" => _}}} =
               Nodes.release(@agent, n.id, %{"force" => "yes"})

      assert {:error, {:validation_failed, %{"x" => _}}} =
               Nodes.release(@agent, n.id, %{"x" => 1})
    end
  end

  describe "concurrency (shared sandbox; callers serialize on the one connection)" do
    test "claim race: exactly one winner" do
      n = mk()

      results =
        race([
          fn -> Nodes.claim(@agent, n.id, %{}) end,
          fn -> Nodes.claim(@agent2, n.id, %{}) end
        ])

      assert [{:ok, _}] = Enum.filter(results, &match?({:ok, _}, &1))
      assert [{:error, {:claimed, _}}] = Enum.filter(results, &match?({:error, _}, &1))
    end

    test "optimistic version: one of two same-version updates wins" do
      n = mk()

      results =
        race(for t <- ["a", "b"], do: fn -> Nodes.update(@human, n.id, 1, %{"title" => t}) end)

      assert [{:ok, _}] = Enum.filter(results, &match?({:ok, _}, &1))

      assert [{:error, {:version_conflict, %Node{version: 2}}}] =
               Enum.filter(results, &match?({:error, _}, &1))
    end
  end

  defp race(funs) do
    owner = self()

    funs
    |> Enum.map(fn f ->
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.allow(Repo, owner, self())
        f.()
      end)
    end)
    |> Task.await_many()
  end
end
