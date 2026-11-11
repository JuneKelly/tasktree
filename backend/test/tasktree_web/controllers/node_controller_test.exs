defmodule TasktreeWeb.NodeControllerTest do
  use TasktreeWeb.ConnCase, async: false

  import TasktreeWeb.ApiHelpers

  defp np(n, suffix \\ ""), do: "/api/nodes/#{n["id"]}#{suffix}"

  describe "create" do
    test "201 with node, allowed_transitions and predicates; actor from the token" do
      n = create_node(%{"title" => "x", "tags" => ["a"]}, token: agent())

      assert %{
               "state" => "TODO",
               "version" => 1,
               "tags" => ["a"],
               "allowed_transitions" => ["NEXT", "DOING", "CANCELLED"],
               "blocked" => false,
               "claimable" => true
             } = n

      assert %{"data" => [%{"actor" => "agent:test", "op" => "create"}]} =
               json!(api(:get, np(n, "/events")), 200)
    end

    test "body cannot supply an actor" do
      error!(
        api(:post, "/api/nodes", %{"title" => "x", "actor" => "human:evil"}),
        422,
        "validation_failed"
      )
    end

    test "422 validation_failed with details" do
      assert %{"details" => %{"title" => _}} =
               error!(api(:post, "/api/nodes", %{}), 422, "validation_failed")

      error!(
        api(:post, "/api/nodes", %{"title" => "x", "fields" => %{"nope" => 1}}),
        422,
        "validation_failed"
      )
    end
  end

  describe "show / index" do
    test "show returns children, edges, predicates" do
      p = create_node()
      c = create_node(%{"parent_id" => p["id"]})

      assert %{"children" => [cid], "edges" => %{"out" => [], "in" => []}, "claimable" => true} =
               json!(api(:get, np(p)), 200)

      assert cid == c["id"]
    end

    test "404 not_found" do
      error!(api(:get, "/api/nodes/nope"), 404, "not_found")
      error!(api(:get, "/api/nodes/nope/events"), 404, "not_found")
    end

    test "index with repeatable filters, pagination and validation" do
      a = create_node(%{"tags" => ["x"]})
      b = create_node()
      {:ok, _} = Tasktree.Nodes.transition("human:t", b["id"], 1, %{"to" => "NEXT"})

      assert %{"data" => [%{"id" => id}]} = json!(api(:get, "/api/nodes?state=NEXT"), 200)
      assert id == b["id"]
      assert %{"data" => two} = json!(api(:get, "/api/nodes?state=NEXT&state=TODO"), 200)
      assert length(two) == 2
      assert %{"data" => [%{"id" => a_id}]} = json!(api(:get, "/api/nodes?tag=x"), 200)
      assert a_id == a["id"]

      assert %{"data" => [_], "next_cursor" => cursor} =
               json!(api(:get, "/api/nodes?limit=1"), 200)

      assert is_binary(cursor)
      error!(api(:get, "/api/nodes?limit=0"), 422, "validation_failed")
      error!(api(:get, "/api/nodes?bogus=1"), 422, "validation_failed")
    end
  end

  describe "If-Match mutations" do
    test "missing If-Match -> 428 on every mutation that needs it" do
      n = create_node()

      for {m, s, b} <- [
            {:patch, "", %{"title" => "x"}},
            {:post, "/transition", %{"to" => "NEXT"}},
            {:post, "/move", %{"parent_id" => nil}}
          ] do
        error!(api(m, np(n, s), b), 428, "precondition_required")
      end
    end

    test "non-integer If-Match -> 422" do
      n = create_node()

      error!(
        api(:patch, np(n), %{"title" => "x"}, headers: [{"if-match", "abc"}]),
        422,
        "validation_failed"
      )
    end

    test "stale version -> 409 version_conflict with the current node" do
      n = create_node()
      json!(api(:patch, np(n), %{"title" => "new"}, version: 1), 200)

      err =
        error!(api(:patch, np(n), %{"title" => "newer"}, version: 1), 409, "version_conflict")

      assert %{"current" => %{"title" => "new", "version" => 2}} = err["details"]
    end
  end

  describe "update" do
    test "200 and version bump" do
      n = create_node()

      assert %{"title" => "new", "version" => 2} =
               json!(api(:patch, np(n), %{"title" => "new"}, version: 1), 200)
    end

    test "404 and 422" do
      n = create_node()
      error!(api(:patch, "/api/nodes/nope", %{"title" => "x"}, version: 1), 404, "not_found")
      error!(api(:patch, np(n), %{"bogus" => 1}, version: 1), 422, "validation_failed")
    end
  end

  describe "transition" do
    test "200; DONE requires outcome (422); illegal -> invalid_transition" do
      n = create_node()

      error!(
        api(:post, np(n, "/transition"), %{"to" => "DONE"}, version: 1),
        422,
        "invalid_transition"
      )

      doing = json!(api(:post, np(n, "/transition"), %{"to" => "DOING"}, version: 1), 200)
      assert doing["state"] == "DOING"

      assert %{"details" => %{"fields" => _}} =
               error!(
                 api(:post, np(n, "/transition"), %{"to" => "DONE"}, version: 2),
                 422,
                 "validation_failed"
               )

      done =
        json!(
          api(:post, np(n, "/transition"), %{"to" => "DONE", "fields" => %{"outcome" => "ok"}},
            version: 2
          ),
          200
        )

      assert %{
               "state" => "DONE",
               "fields" => %{"outcome" => "ok"},
               "allowed_transitions" => ["TODO"]
             } = done
    end
  end

  describe "move" do
    test "200, and 422 cycle" do
      a = create_node()
      b = create_node(%{"parent_id" => a["id"]})

      assert %{"parent_id" => nil} =
               json!(api(:post, np(b, "/move"), %{"parent_id" => nil}, version: 1), 200)

      c = create_node(%{"parent_id" => a["id"]})
      error!(api(:post, np(a, "/move"), %{"parent_id" => c["id"]}, version: 1), 422, "cycle")
    end
  end

  describe "claim / release" do
    test "claim, 409 claimed with holder, mutation gated, release, force" do
      n = create_node()
      claimed = json!(api(:post, np(n, "/claim"), %{"ttl_seconds" => 60}, token: agent()), 200)
      assert %{"claimed_by" => "agent:test", "claimable" => false} = claimed

      err = error!(api(:post, np(n, "/claim"), nil, token: human()), 409, "claimed")
      assert %{"claimed_by" => "agent:test", "claim_expires_at" => _} = err["details"]
      error!(api(:patch, np(n), %{"title" => "x"}, version: 2), 409, "claimed")
      error!(api(:post, np(n, "/release"), nil, token: human()), 409, "claimed")

      assert %{"claimed_by" => nil} =
               json!(api(:post, np(n, "/release"), %{"force" => true}, token: human()), 200)
    end

    test "agents cannot force-release; releasing an unclaimed node is 422; claim 404" do
      n = create_node()
      error!(api(:post, np(n, "/release"), nil), 422, "validation_failed")
      error!(api(:post, "/api/nodes/nope/claim"), 404, "not_found")
      error!(api(:post, np(n, "/claim"), %{"ttl_seconds" => 0}), 422, "validation_failed")
    end
  end

  test "events endpoints: history with actors, and the global feed" do
    n = create_node(%{}, token: agent())
    json!(api(:post, np(n, "/claim"), nil, token: agent()), 200)
    assert %{"data" => evs} = json!(api(:get, np(n, "/events")), 200)
    assert Enum.map(evs, & &1["op"]) == ["create", "claim"]
    assert Enum.all?(evs, &(&1["actor"] == "agent:test"))

    assert %{"data" => feed, "last_seq" => last} =
             json!(api(:get, "/api/events?since=0&limit=1000"), 200)

    assert last == List.last(feed)["seq"]

    assert %{"data" => [], "last_seq" => ^last} =
             json!(api(:get, "/api/events?since=#{last}"), 200)

    error!(api(:get, "/api/events?limit=0"), 422, "validation_failed")
    error!(api(:get, "/api/events?since=x"), 422, "validation_failed")
    error!(api(:get, "/api/events?bogus=1"), 422, "validation_failed")
  end

  test "acceptance flow: list claimable, claim, DONE with outcome, history" do
    n = create_node(%{"title" => "job"}, token: human())

    assert %{"data" => data} =
             json!(api(:get, "/api/nodes?claimable=true", nil, token: agent()), 200)

    assert n["id"] in Enum.map(data, & &1["id"])

    claimed = json!(api(:post, np(n, "/claim"), nil, token: agent()), 200)

    s1 =
      json!(
        api(:post, np(n, "/transition"), %{"to" => "DOING"},
          token: agent(),
          version: claimed["version"]
        ),
        200
      )

    json!(
      api(:post, np(n, "/transition"), %{"to" => "DONE", "fields" => %{"outcome" => "shipped"}},
        token: agent(),
        version: s1["version"]
      ),
      200
    )

    assert %{"data" => evs} = json!(api(:get, np(n, "/events"), nil, token: agent()), 200)
    assert Enum.map(evs, & &1["op"]) == ["create", "claim", "transition", "transition"]

    assert Enum.map(evs, & &1["actor"]) == [
             "human:test",
             "agent:test",
             "agent:test",
             "agent:test"
           ]
  end
end
