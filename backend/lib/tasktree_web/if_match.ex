defmodule TasktreeWeb.IfMatch do
  @moduledoc "Reads the integer node version from the `If-Match` header."

  @spec fetch(Plug.Conn.t()) ::
          {:ok, integer()} | {:error, :precondition_required | {:validation_failed, map()}}
  def fetch(conn) do
    case Plug.Conn.get_req_header(conn, "if-match") do
      [] ->
        {:error, :precondition_required}

      [value] ->
        case Integer.parse(value) do
          {n, ""} -> {:ok, n}
          _ -> {:error, {:validation_failed, %{"if-match" => "must be an integer version"}}}
        end

      _ ->
        {:error, {:validation_failed, %{"if-match" => "must be given once"}}}
    end
  end
end
