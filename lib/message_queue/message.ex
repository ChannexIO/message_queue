defmodule MessageQueue.Message do
  @moduledoc """
  This struct holds all information about a message.
  """

  alias MessageQueue.Parsers

  defstruct data: nil,
            parser_opts: [],
            type: :json

  @type t() :: %__MODULE__{}

  @type data() :: term()
  @type opts() :: Access.t()
  @type encoded_message() :: binary() | String.t()
  @type decoded_message() :: binary() | String.t()
  @type parsing_error() :: String.t()

  @doc """
  Encodes the data according to its type using a parser.
  """
  @spec encode(data(), opts()) :: {:ok, encoded_message()} | {:error, parsing_error()}
  def encode(data, opts) do
    opts |> put_in([:data], data) |> new() |> encode()
  end

  @doc """
  Decodes the data according to its type using a parser.
  """
  @spec decode(data(), opts()) :: {:ok, decoded_message()} | {:error, parsing_error()}
  def decode(data, opts) do
    opts |> put_in([:data], data) |> new() |> decode()
  end

  defp new(opts) do
    struct(__MODULE__, opts)
  end

  defp encode(%__MODULE__{} = message) do
    Parsers.encode(message)
  end

  defp decode(%__MODULE__{} = message) do
    Parsers.decode(message)
  end
end
