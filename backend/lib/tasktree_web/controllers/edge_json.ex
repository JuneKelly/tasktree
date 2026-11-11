defmodule TasktreeWeb.EdgeJSON do
  def show(%{edge: edge}), do: TasktreeWeb.NodeJSON.edge(edge)
end
