defmodule TasktreeWeb.FallbackController do
  @moduledoc "Maps `{:error, reason}` from the contexts to the error contract. Unknown reasons crash (500) rather than being papered over."

  use TasktreeWeb, :controller

  alias TasktreeWeb.{ErrorJSON, NodeJSON}

  def call(conn, {:error, reason}), do: render_error(conn, reason)

  defp render_error(conn, :not_found),
    do: send_error(conn, 404, "not_found", "resource not found")

  defp render_error(conn, :cycle),
    do: send_error(conn, 422, "cycle", "operation would create a cycle")

  defp render_error(conn, :precondition_required),
    do:
      send_error(
        conn,
        428,
        "precondition_required",
        "If-Match header with the node version is required"
      )

  defp render_error(conn, {:validation_failed, details}),
    do: send_error(conn, 422, "validation_failed", "validation failed", details)

  defp render_error(conn, {:invalid_transition, details}),
    do: send_error(conn, 422, "invalid_transition", "transition not allowed", details)

  defp render_error(conn, {:version_conflict, node}),
    do:
      send_error(conn, 409, "version_conflict", "node was modified; refetch and retry", %{
        "current" => NodeJSON.data(node)
      })

  defp render_error(conn, {:claimed, holder}),
    do: send_error(conn, 409, "claimed", "node is claimed by another actor", holder)

  defp send_error(conn, status, code, message, details \\ %{}) do
    conn |> put_status(status) |> json(ErrorJSON.body(code, message, details))
  end
end
