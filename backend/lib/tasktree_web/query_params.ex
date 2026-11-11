defmodule TasktreeWeb.QueryParams do
  @moduledoc """
  Decodes the raw query string keeping repeated keys (`state=A&state=B` -> `["A", "B"]`),
  which Plug's own parser collapses to the last value.
  """

  @spec decode(Plug.Conn.t()) :: %{String.t() => String.t() | [String.t()]}
  def decode(conn) do
    conn.query_string
    |> URI.query_decoder()
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      Map.update(acc, k, v, fn
        existing when is_list(existing) -> existing ++ [v]
        existing -> [existing, v]
      end)
    end)
  end
end
