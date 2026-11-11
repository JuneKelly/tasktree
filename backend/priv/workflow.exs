%{
  initial: "TODO",
  states: %{
    "TODO" => %{terminal: false, next: ["NEXT", "DOING", "CANCELLED"]},
    "NEXT" => %{terminal: false, next: ["TODO", "DOING", "CANCELLED"]},
    "DOING" => %{terminal: false, next: ["TODO", "NEXT", "DONE", "CANCELLED"]},
    "DONE" => %{terminal: true, next: ["TODO"], require_fields: ["outcome"]},
    "CANCELLED" => %{terminal: true, next: ["TODO"]}
  },
  actionable: ["NEXT", "TODO"],
  fields: %{
    "outcome" => %{type: "string"},
    "scheduled" => %{type: "date"},
    "deadline" => %{type: "date"},
    "effort" => %{type: "int"},
    "priority" => %{type: "enum", values: ["A", "B", "C"]},
    "assignee" => %{type: "string"}
  }
}
