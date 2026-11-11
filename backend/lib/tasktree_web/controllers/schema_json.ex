defmodule TasktreeWeb.SchemaJSON do
  @moduledoc "Workflow as the UI needs it: `{initial, states, transitions, fields, actionable}`."

  def show(%{workflow: wf}) do
    %{
      initial: wf.initial,
      states:
        for {name, s} <- Enum.sort(wf.states) do
          %{name: name, terminal: s.terminal, require_fields: Map.get(s, :require_fields, [])}
        end,
      transitions: Map.new(wf.states, fn {name, s} -> {name, s.next} end),
      fields: wf.fields,
      actionable: wf.actionable
    }
  end
end
