defmodule Tasktree.Workflow do
  @moduledoc """
  Loads, validates, and queries the workflow config (DESIGN.md §3.4).

  The validated config is stored in `:persistent_term` by `load!/0`, which runs at
  application start, so a missing or malformed config prevents boot.
  """

  @key {__MODULE__, :config}
  @top_keys [:initial, :states, :actionable, :fields]
  @field_types ["string", "date", "int", "enum"]

  @type t :: %{
          initial: String.t(),
          states: %{String.t() => map()},
          actionable: [String.t()],
          fields: %{String.t() => map()}
        }

  @doc "Loads the file at `:workflow_path`, validates it, and stores it. Raises on any problem."
  @spec load!() :: t()
  def load!, do: load!(Application.fetch_env!(:tasktree, :workflow_path))

  @spec load!(Path.t()) :: t()
  def load!(path) do
    config =
      try do
        {value, _binding} = Code.eval_file(path)
        value
      rescue
        e -> raise ArgumentError, "cannot load workflow config #{path}: #{Exception.message(e)}"
      end

    case validate(config) do
      {:ok, wf} ->
        :persistent_term.put(@key, wf)
        wf

      {:error, reason} ->
        raise ArgumentError, "invalid workflow config #{path}: #{reason}"
    end
  end

  @doc "The loaded workflow. Raises if `load!/0` has not run."
  @spec current() :: t()
  def current, do: :persistent_term.get(@key)

  @doc "Single lookup point so per-subtree workflows can be added later."
  @spec for_node(term()) :: t()
  def for_node(_node), do: current()

  @spec validate(term()) :: {:ok, t()} | {:error, String.t()}
  def validate(%{} = c) do
    with :ok <- check_keys(c, @top_keys, "top level"),
         {:ok, fields} <- validate_field_defs(c.fields),
         {:ok, states} <- validate_states(c.states, fields),
         :ok <- check_initial(c.initial, states),
         :ok <- check_actionable(c.actionable, states) do
      {:ok, %{initial: c.initial, states: states, actionable: c.actionable, fields: fields}}
    end
  end

  def validate(_), do: {:error, "config must be a map"}

  defp check_keys(map, allowed, where) do
    missing = allowed -- Map.keys(map)
    unknown = Map.keys(map) -- allowed

    cond do
      missing != [] -> {:error, "#{where}: missing keys #{inspect(missing)}"}
      unknown != [] -> {:error, "#{where}: unknown keys #{inspect(unknown)}"}
      true -> :ok
    end
  end

  defp validate_field_defs(%{} = defs) when map_size(defs) > 0 do
    Enum.reduce_while(defs, {:ok, defs}, fn {name, def}, acc ->
      case validate_field_def(name, def) do
        :ok -> {:cont, acc}
        {:error, _} = e -> {:halt, e}
      end
    end)
  end

  defp validate_field_defs(_), do: {:error, "fields must be a non-empty map"}

  defp validate_field_def(name, _) when not is_binary(name),
    do: {:error, "field name #{inspect(name)} must be a string"}

  defp validate_field_def(name, %{type: "enum"} = d) do
    with :ok <- check_keys(d, [:type, :values], "field #{name}") do
      if is_list(d.values) and d.values != [] and Enum.all?(d.values, &is_binary/1) and
           Enum.uniq(d.values) == d.values,
         do: :ok,
         else: {:error, "field #{name}: enum values must be a non-empty list of unique strings"}
    end
  end

  defp validate_field_def(name, %{type: t} = d) when t in @field_types,
    do: check_keys(d, [:type], "field #{name}")

  defp validate_field_def(name, _),
    do: {:error, "field #{name}: type must be one of #{inspect(@field_types)}"}

  defp validate_states(%{} = states, fields) when map_size(states) > 0 do
    Enum.reduce_while(states, {:ok, states}, fn {name, s}, acc ->
      case validate_state(name, s, states, fields) do
        :ok -> {:cont, acc}
        {:error, _} = e -> {:halt, e}
      end
    end)
  end

  defp validate_states(_, _), do: {:error, "states must be a non-empty map"}

  defp validate_state(name, _, _, _) when not is_binary(name),
    do: {:error, "state name #{inspect(name)} must be a string"}

  defp validate_state(name, %{terminal: term, next: next} = s, states, fields)
       when is_boolean(term) and is_list(next) do
    required = Map.get(s, :require_fields, [])

    cond do
      Map.keys(s) -- [:terminal, :next, :require_fields] != [] ->
        {:error, "state #{name}: unknown keys"}

      Enum.any?(next, &(not Map.has_key?(states, &1))) ->
        {:error, "state #{name}: next references unknown state"}

      not is_list(required) or Enum.any?(required, &(not Map.has_key?(fields, &1))) ->
        {:error, "state #{name}: require_fields references unknown field"}

      true ->
        :ok
    end
  end

  defp validate_state(name, _, _, _),
    do: {:error, "state #{name}: needs boolean :terminal and list :next"}

  defp check_initial(initial, states) do
    if is_binary(initial) and Map.has_key?(states, initial),
      do: :ok,
      else: {:error, "initial #{inspect(initial)} is not a known state"}
  end

  defp check_actionable(list, states) do
    if is_list(list) and Enum.all?(list, &Map.has_key?(states, &1)),
      do: :ok,
      else: {:error, "actionable must be a list of known states"}
  end

  @doc "Whether `state` exists and is terminal."
  @spec terminal?(t(), String.t()) :: boolean()
  def terminal?(wf, state), do: Map.fetch!(wf.states, state).terminal

  @doc """
  Checks a transition. `fields` is the node's fields merged with any supplied in the request.
  """
  @spec check_transition(t(), String.t(), String.t(), map()) ::
          :ok
          | {:error, {:unknown_state, String.t()}}
          | {:error, {:illegal_transition, String.t(), String.t()}}
          | {:error, {:missing_fields, [String.t()]}}
  def check_transition(wf, from, to, fields) do
    with {:ok, f} <- fetch_state(wf, from),
         {:ok, t} <- fetch_state(wf, to),
         :ok <- if(to in f.next, do: :ok, else: {:error, {:illegal_transition, from, to}}) do
      case Enum.reject(Map.get(t, :require_fields, []), &Map.has_key?(fields, &1)) do
        [] -> :ok
        missing -> {:error, {:missing_fields, missing}}
      end
    end
  end

  defp fetch_state(wf, name) do
    case wf.states do
      %{^name => s} -> {:ok, s}
      _ -> {:error, {:unknown_state, name}}
    end
  end

  @doc "Validates a node `fields` map (string keys, non-nil values) against the field schema."
  @spec validate_fields(t(), map()) ::
          :ok | {:error, {:unknown_field, String.t()} | {:invalid_field, String.t()}}
  def validate_fields(wf, fields) do
    Enum.find_value(fields, :ok, fn {name, value} ->
      case wf.fields do
        %{^name => def} ->
          if valid_value?(def, value), do: nil, else: {:error, {:invalid_field, name}}

        _ ->
          {:error, {:unknown_field, name}}
      end
    end)
  end

  defp valid_value?(%{type: "string"}, v), do: is_binary(v)
  defp valid_value?(%{type: "int"}, v), do: is_integer(v)
  defp valid_value?(%{type: "enum", values: vs}, v), do: v in vs

  defp valid_value?(%{type: "date"}, v),
    do: is_binary(v) and match?({:ok, _}, Date.from_iso8601(v))
end
