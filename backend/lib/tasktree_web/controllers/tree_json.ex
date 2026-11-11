defmodule TasktreeWeb.TreeJSON do
  def show(%{tree: tree}), do: %{data: Enum.map(tree, &entry/1)}

  defp entry(%{node: node, children: children}),
    do: node |> TasktreeWeb.NodeJSON.data() |> Map.put(:children, Enum.map(children, &entry/1))
end
