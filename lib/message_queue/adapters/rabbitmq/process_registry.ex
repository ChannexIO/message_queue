defmodule MessageQueue.Adapters.RabbitMQ.ProcessRegistry do
  @moduledoc """
  Helper for process registry managing.
  """

  @spec register(term(), term()) :: {:ok, pid()} | {:error, {:already_registered, pid()}}
  def register(key, value) do
    Registry.register(__MODULE__, key, value)
  end

  @spec lookup(term()) :: [{pid(), term()}]
  def lookup(key) do
    Registry.lookup(__MODULE__, key)
  end
end
