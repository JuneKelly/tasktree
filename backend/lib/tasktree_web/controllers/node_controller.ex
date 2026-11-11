defmodule TasktreeWeb.NodeController do
  use TasktreeWeb, :controller

  alias Tasktree.{Events, Nodes, Queries}
  alias TasktreeWeb.{IfMatch, QueryParams}

  action_fallback TasktreeWeb.FallbackController

  def index(conn, _params) do
    with {:ok, result} <- Queries.list(QueryParams.decode(conn)) do
      render(conn, :index, result: result)
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, detail} <- Queries.get(id), do: render(conn, :show, detail: detail)
  end

  def create(conn, _params) do
    with {:ok, node} <- Nodes.create(actor(conn), conn.body_params),
         {:ok, %{node: node}} <- Queries.get(node.id) do
      conn |> put_status(:created) |> render(:node, node: node)
    end
  end

  def update(conn, %{"id" => id}) do
    with {:ok, version} <- IfMatch.fetch(conn),
         {:ok, node} <- Nodes.update(actor(conn), id, version, conn.body_params),
         do: respond(conn, node)
  end

  def transition(conn, %{"id" => id}) do
    with {:ok, version} <- IfMatch.fetch(conn),
         {:ok, node} <- Nodes.transition(actor(conn), id, version, conn.body_params),
         do: respond(conn, node)
  end

  def move(conn, %{"id" => id}) do
    with {:ok, version} <- IfMatch.fetch(conn),
         {:ok, node} <- Nodes.move(actor(conn), id, version, conn.body_params),
         do: respond(conn, node)
  end

  def claim(conn, %{"id" => id}) do
    with {:ok, node} <- Nodes.claim(actor(conn), id, conn.body_params), do: respond(conn, node)
  end

  def release(conn, %{"id" => id}) do
    with {:ok, node} <- Nodes.release(actor(conn), id, conn.body_params), do: respond(conn, node)
  end

  def events(conn, %{"id" => id}) do
    with {:ok, _node} <- Nodes.get(id),
         do: render(conn, :events, events: Events.list_for_node(id))
  end

  defp actor(conn), do: conn.assigns.actor

  # Re-read so the response carries the SQL-derived blocked/claimable predicates.
  defp respond(conn, node) do
    with {:ok, %{node: node}} <- Queries.get(node.id), do: render(conn, :node, node: node)
  end
end
