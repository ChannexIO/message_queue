defmodule MessageQueue.Consumer do
  @moduledoc """
    Module which consumes messages from message queue
  """

  defmacro __using__(_opts) do
    quote do
      use unquote(MessageQueue.consumer())
    end
  end
end
