defmodule Tasktree.Auth do
  @moduledoc """
  Static bearer tokens mapped to actors (DESIGN.md §4). Configured as
  `TASKTREE_TOKENS="tok1=human:june,tok2=agent:planner"` and parsed at boot by
  `load!/0`; a missing or malformed value prevents boot.
  """

  @key {__MODULE__, :tokens}

  @doc "Parses and stores the tokens from the `:auth_tokens` app config. Raises on any problem."
  @spec load!() :: %{String.t() => String.t()}
  def load! do
    tokens = parse_tokens!(Application.fetch_env!(:tasktree, :auth_tokens))
    :persistent_term.put(@key, tokens)
    tokens
  end

  @spec parse_tokens!(String.t()) :: %{String.t() => String.t()}
  def parse_tokens!(raw) when is_binary(raw) do
    pairs =
      raw
      |> String.split(",", trim: true)
      |> Enum.map(fn entry ->
        case String.split(String.trim(entry), "=", parts: 2) do
          [token, actor] when token != "" ->
            if Regex.match?(~r/\A(human|agent):[^\s:]+\z/, actor),
              do: {token, actor},
              else:
                raise(
                  ArgumentError,
                  "invalid actor #{inspect(actor)} in TASKTREE_TOKENS (want human:<name> or agent:<name>)"
                )

          _ ->
            raise ArgumentError,
                  "malformed TASKTREE_TOKENS entry #{inspect(entry)} (want token=actor)"
        end
      end)

    if pairs == [], do: raise(ArgumentError, "TASKTREE_TOKENS defines no tokens")

    tokens = Map.new(pairs)

    if map_size(tokens) != length(pairs),
      do: raise(ArgumentError, "duplicate token in TASKTREE_TOKENS")

    tokens
  end

  @doc "The actor for a bearer token, or `:error`. Compares every token in constant time per entry."
  @spec actor_for(String.t()) :: {:ok, String.t()} | :error
  def actor_for(token) when is_binary(token) do
    :persistent_term.get(@key)
    |> Enum.reduce(:error, fn {t, actor}, acc ->
      if Plug.Crypto.secure_compare(t, token), do: {:ok, actor}, else: acc
    end)
  end
end
