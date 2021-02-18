defmodule MessageQueue.Adapters.Connection do
  @moduledoc """
    Behaviour for creating MessageQueue connections
  """

  @callback get() :: {:ok | AMQP.Connection.t() | term()} | {:error, :not_connected}
end
