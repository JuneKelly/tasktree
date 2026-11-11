defmodule TasktreeWeb.AuthPlug do
  @moduledoc "Resolves `Authorization: Bearer <token>` to `conn.assigns.actor`, or halts with 401."

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, actor} <- Tasktree.Auth.actor_for(token) do
      assign(conn, :actor, actor)
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", "Bearer")
        |> put_resp_content_type("application/json")
        |> send_resp(
          401,
          Jason.encode!(
            TasktreeWeb.ErrorJSON.body("unauthorized", "missing or invalid bearer token")
          )
        )
        |> halt()
    end
  end
end
