defmodule MessageQueue.Adapters.Producer do
  @moduledoc """
    Behaviour for creating MessageQueue producers
  """

  @callback publish(message :: term(), queue :: list() | binary(), options :: map()) ::
              :ok | AMQP.Basic.error() | {:error, :not_published} | {:error, any()}
end
