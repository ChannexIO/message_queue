defmodule MessageQueue.Parsers.Json do
  @moduledoc false

  alias Jason.DecodeError

  @doc false
  def encode(data, opts) do
    case Jason.encode(data, opts) do
      {:ok, encoded_data} -> {:ok, encoded_data}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  @doc false
  def decode(data, opts) do
    case Jason.decode(data, opts) do
      {:ok, decoded_data} -> {:ok, decoded_data}
      {:error, error} -> {:error, DecodeError.message(error)}
    end
  end
end
