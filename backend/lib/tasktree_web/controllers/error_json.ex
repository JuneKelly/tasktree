defmodule TasktreeWeb.ErrorJSON do
  @moduledoc """
  The error contract (DESIGN.md §5): `{"error": {"code", "message", "details"}}`.
  `render/2` is invoked by the endpoint for framework errors (404, 400, 500, ...).
  """

  @spec body(String.t(), String.t(), map()) :: map()
  def body(code, message, details \\ %{}),
    do: %{error: %{code: code, message: message, details: details}}

  def render(template, _assigns) do
    message = Phoenix.Controller.status_message_from_template(template)
    body(message |> String.downcase() |> String.replace(" ", "_"), message)
  end
end
