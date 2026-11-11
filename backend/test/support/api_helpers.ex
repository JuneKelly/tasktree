defmodule TasktreeWeb.ApiHelpers do
  @moduledoc "Request helpers for controller tests."

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint TasktreeWeb.Endpoint

  @human "test-human"
  @agent "test-agent"

  def human, do: @human
  def agent, do: @agent

  @doc "Sends a JSON request. Options: `:token` (default human), `:version` (If-Match), `:headers`."
  def api(method, path, body \\ nil, opts \\ []) do
    conn = Phoenix.ConnTest.build_conn()

    conn =
      case Keyword.get(opts, :token, @human) do
        nil -> conn
        token -> put_req_header(conn, "authorization", "Bearer " <> token)
      end

    conn =
      case Keyword.get(opts, :version) do
        nil -> conn
        v -> put_req_header(conn, "if-match", to_string(v))
      end

    conn =
      Enum.reduce(Keyword.get(opts, :headers, []), conn, fn {k, v}, c ->
        put_req_header(c, k, v)
      end)

    body = if body == nil, do: nil, else: Jason.encode!(body)
    conn = if body, do: put_req_header(conn, "content-type", "application/json"), else: conn
    dispatch(conn, @endpoint, method, path, body)
  end

  def json!(conn, status), do: json_response(conn, status)

  def error!(conn, status, code) do
    assert_error = json_response(conn, status)
    %{"error" => %{"code" => ^code, "message" => msg, "details" => details}} = assert_error
    true = is_binary(msg) and is_map(details)
    assert_error["error"]
  end

  def create_node(attrs \\ %{}, opts \\ []) do
    json!(api(:post, "/api/nodes", Map.merge(%{"title" => "t"}, attrs), opts), 201)
  end
end
