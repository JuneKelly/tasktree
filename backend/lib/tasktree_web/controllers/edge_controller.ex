defmodule TasktreeWeb.EdgeController do
  use TasktreeWeb, :controller

  alias Tasktree.Edges

  action_fallback TasktreeWeb.FallbackController

  def create(conn, _params) do
    with {:ok, edge} <- Edges.add(conn.assigns.actor, conn.body_params) do
      conn |> put_status(:created) |> render(:show, edge: edge)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _edge} <- Edges.remove(conn.assigns.actor, id) do
      send_resp(conn, 204, "")
    end
  end
end
