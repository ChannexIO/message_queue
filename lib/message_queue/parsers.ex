defmodule MessageQueue.Parsers do
  @moduledoc false

  alias __MODULE__.{ExtBinary, Json}

  @doc false
  def encode(message) do
    get_parser(message).encode(message.data, message.parser_opts)
  end

  @doc false
  def decode(message) do
    get_parser(message).decode(message.data, message.parser_opts)
  end

  defp get_parser(%{type: :json}), do: Json
  defp get_parser(%{type: :ext_binary}), do: ExtBinary
  defp get_parser(%{type: _}), do: ExtBinary
end
