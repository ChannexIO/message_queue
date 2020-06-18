defmodule MessageQueue.Producer do
  @moduledoc """
  Module for publishing message to queue and keeping of connection
  """

  def child_spec(opts) do
    %{
      id: MessageQueue.producer(),
      start: {MessageQueue.producer(), :start_link, [opts]}
    }
  end

  @spec publish(message :: term(), queue :: list() | binary(), options :: map()) ::
          :ok | Basic.error() | {:error, :not_published} | {:error, any()}
  def publish(message, queue, options \\ []) do
    MessageQueue.producer().publish(message, queue, options)
  end
end
