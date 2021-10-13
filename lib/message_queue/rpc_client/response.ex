defmodule MessageQueue.RPCClient.Response do
  @moduledoc """
  Module for prepare response form remote client
  """

  alias MessageQueue.Message

  @spec prepare!(payload :: binary) :: term()
  def prepare!(payload) do
    case Message.decode(payload, type: :ext_binary) do
      {:ok, payload} -> payload
      {:error, error} -> raise error
    end
  end
end
