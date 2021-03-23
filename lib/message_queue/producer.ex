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

  def publish(message, queue, options) do
    MessageQueue.producer().publish(message, queue, options)
  end

  def delete_queue(queue, options) do
    MessageQueue.producer().delete_queue(queue, options)
  end
end
