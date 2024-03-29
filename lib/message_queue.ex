defmodule MessageQueue do
  @moduledoc false

  defdelegate publish(message, queue, options \\ []), to: MessageQueue.Producer
  defdelegate delete_queue(queue, options \\ []), to: MessageQueue.Producer
  defdelegate rpc_call(module, function, args, opts \\ []), to: MessageQueue.RPCClient, as: :call
  defdelegate rpc_cast(module, function, args), to: MessageQueue.RPCClient, as: :cast
  defdelegate get_connection(), to: MessageQueue.Connection, as: :get
  defdelegate encode_data(data, opts \\ []), to: MessageQueue.Message, as: :encode
  defdelegate decode_data(data, opts \\ []), to: MessageQueue.Message, as: :decode

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

  @spec prefix_queue_or_empty(binary()) :: binary()
  def prefix_queue_or_empty(queue) do
    case Application.get_env(:message_queue, :app_name, "") do
      "" -> ""
      app_name -> "#{app_name}.#{queue}"
    end
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
