defmodule MessageQueue.Parsers.CompressedJson do
  @moduledoc false

  alias Jason.DecodeError

  @doc false
  def encode(data, opts) do
    case data |> Jason.encode(opts) |> :zlib.compress() do
      {:ok, encoded_data} -> {:ok, encoded_data}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  @doc false
  def decode(data, opts) do
    case data |> :zlib.uncompress() |> Jason.decode(opts) do
      {:ok, decoded_data} -> {:ok, decoded_data}
      {:error, error} -> {:error, DecodeError.message(error)}
    end
  end
end
