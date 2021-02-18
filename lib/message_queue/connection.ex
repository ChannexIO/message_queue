defmodule MessageQueue.Connection do
  @moduledoc """
  Module for keeping connection to message broker
  """

  @behaviour MessageQueue.Adapters.Connection

  def child_spec(opts) do
    %{
      id: MessageQueue.connection(),
      start: {MessageQueue.connection(), :start_link, [opts]}
    }
  end

  def get do
    case MessageQueue.connection().get() do
      {:ok, connection} when not is_nil(connection) -> {:ok, connection}
      _ -> {:error, :not_connected}
    end
  catch
    :exit, _ -> {:error, :not_connected}
  end
end
