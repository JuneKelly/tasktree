defmodule TasktreeWeb.AuthTest do
  use TasktreeWeb.ConnCase, async: true

  import TasktreeWeb.ApiHelpers

  alias Tasktree.Auth

  describe "AuthPlug" do
    test "missing, malformed, and unknown tokens -> 401 unauthorized" do
      error!(api(:get, "/api/nodes", nil, token: nil), 401, "unauthorized")
      error!(api(:get, "/api/nodes", nil, token: "nope"), 401, "unauthorized")

      error!(
        api(:get, "/api/nodes", nil, token: nil, headers: [{"authorization", "Basic abc"}]),
        401,
        "unauthorized"
      )

      error!(
        api(:get, "/api/nodes", nil, token: nil, headers: [{"authorization", "Bearer"}]),
        401,
        "unauthorized"
      )
    end

    test "every endpoint requires auth" do
      for {m, p} <- [
            get: "/api/schema",
            get: "/api/tree",
            get: "/api/events",
            get: "/api/nodes",
            post: "/api/nodes",
            get: "/api/nodes/x",
            patch: "/api/nodes/x",
            post: "/api/nodes/x/transition",
            post: "/api/nodes/x/move",
            post: "/api/nodes/x/claim",
            post: "/api/nodes/x/release",
            get: "/api/nodes/x/events",
            post: "/api/edges",
            delete: "/api/edges/x"
          ] do
        error!(api(m, p, nil, token: nil), 401, "unauthorized")
      end
    end

    test "valid token resolves the actor" do
      assert %{"data" => _} = json!(api(:get, "/api/nodes"), 200)
      assert %{"actor" => "human:test"} = json!(api(:get, "/api/me"), 200)
      assert %{"actor" => "agent:test"} = json!(api(:get, "/api/me", nil, token: agent()), 200)
    end
  end

  describe "Auth.parse_tokens!/1" do
    test "parses pairs" do
      assert %{"a" => "human:june", "b" => "agent:planner"} =
               Auth.parse_tokens!("a=human:june,b=agent:planner")
    end

    test "raises on malformed config" do
      for bad <- [
            "",
            "a",
            "=human:x",
            "a=robot:x",
            "a=human:",
            "a=human:x,a=agent:y",
            "a=human:x y"
          ] do
        assert_raise ArgumentError, fn -> Auth.parse_tokens!(bad) end
      end
    end
  end

  test "unknown routes use the error contract" do
    error!(api(:get, "/api/nope"), 404, "not_found")
  end

  test "malformed JSON body -> 400 in the error contract" do
    {400, _headers, body} =
      assert_error_sent(400, fn ->
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("authorization", "Bearer " <> human())
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Phoenix.ConnTest.dispatch(TasktreeWeb.Endpoint, :post, "/api/nodes", "{bad")
      end)

    assert %{"error" => %{"code" => "bad_request", "details" => %{}}} = Jason.decode!(body)
  end
end
