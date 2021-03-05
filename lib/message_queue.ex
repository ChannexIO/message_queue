defmodule MessageQueue do
  @moduledoc false

  defdelegate publish(message, queue, options \\ []), to: MessageQueue.Producer
  defdelegate delete_queue(queue, options \\ []), to: MessageQueue.Producer
  defdelegate rpc_call(module, function, args), to: MessageQueue.RPCClient, as: :call
  defdelegate get_connection, to: MessageQueue.Connection, as: :get

  @spec producer() :: module()
  def producer, do: adapter(Producer)

  @spec consumer() :: module()
  def consumer, do: adapter(Consumer)

  @spec rpc_server() :: module()
  def rpc_server, do: adapter(RPCServer)

  @spec rpc_client() :: module()
  def rpc_client, do: adapter(RPCClient)

  @spec connection() :: module()
  def connection, do: adapter(Connection)

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
  def connection_details do
    Application.get_env(:message_queue, :connection)
  end

  defp adapter(module) do
    case Application.get_env(:message_queue, :adapter) do
      :rabbitmq -> MessageQueue.Adapters.RabbitMQ
      :sandbox -> MessageQueue.Adapters.Sandbox
      adapter -> adapter
    end
    |> Module.concat(module)
  end
end
