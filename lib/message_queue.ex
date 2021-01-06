defmodule MessageQueue do
  @moduledoc false

  @spec producer() :: module()
  def producer, do: adapter(Producer)

  @spec consumer() :: module()
  def consumer, do: adapter(Consumer)

  @spec rpc_server() :: module()
  def rpc_server, do: adapter(RPCServer)

  @spec rpc_client() :: module()
  def rpc_client, do: adapter(RPCClient)

  @spec rpc_queue() :: binary()
  def rpc_queue do
    app_name = Application.get_env(:message_queue, :app_name)
    "rpc_#{app_name}"
  end

  @spec rpc_modules() :: list()
  def rpc_modules do
    Application.get_env(:message_queue, :rpc_modules, [])
  end

  @spec connection() :: keyword()
  def connection do
    Application.get_env(:message_queue, :connection)
  end

  @spec publish(term(), String.t() | list(String.t()), keyword()) :: :ok | term()
  def publish(message, queue, options) do
    producer().publish(message, queue, options)
  end

  defp adapter(module) do
    case Application.get_env(:message_queue, :adapter) do
      :rabbitmq -> MessageQueue.Adapters.RabbitMQ
      _ -> MessageQueue.Adapters.Sandbox
    end
    |> Module.concat(module)
  end
end
