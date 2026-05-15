defmodule MessageQueue.Parsers.Raw do
  @moduledoc false

  @error "Raw parser requires a binary payload"

  @doc false
  def encode(data, _opts) when is_binary(data), do: {:ok, data}
  def encode(_data, _opts), do: {:error, @error}

  @doc false
  def decode(data, _opts) when is_binary(data), do: {:ok, data}
  def decode(_data, _opts), do: {:error, @error}
end
