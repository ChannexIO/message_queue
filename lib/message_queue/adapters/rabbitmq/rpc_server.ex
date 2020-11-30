defmodule MessageQueue.Adapters.RabbitMQ.RPCServer do
  @moduledoc false

  @reconnect_interval 10_000

  use AMQP
  use GenServer
  alias MessageQueue.RPCClient.Command
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    connection = MessageQueue.connection()
    rpc_queue = MessageQueue.rpc_queue()

    with {:ok, conn} <- Connection.open(connection),
         {:ok, channel} <- Channel.open(conn),
         {:ok, _} <- Queue.declare(channel, rpc_queue),
         :ok <- Basic.qos(channel, prefetch_count: 1),
         {:ok, _} <- Basic.consume(channel, rpc_queue) do
      {:noreply, channel, :hibernate}
    else
      {:error, _} ->
        Logger.error("Failed to connect RabbitMQ. Reconnecting later...")
        Process.sleep(@reconnect_interval)
        {:noreply, state, {:continue, :connect}}
    end
  catch
    :exit, error ->
      Logger.error("RabbitMQ error: #{inspect(error)}. Reconnecting later...")
      Process.sleep(@reconnect_interval)
      {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info({:EXIT, _, :normal}, _channel) do
    {:stop, :normal, nil}
  end

  @impl true
  def handle_info({:basic_consume_ok, %{consumer_tag: _}}, channel) do
    {:noreply, channel, :hibernate}
  end

  @impl true
  def handle_info({:basic_cancel, %{consumer_tag: _}}, channel) do
    {:stop, :normal, channel}
  end

  @impl true
  def handle_info({:basic_cancel_ok, %{consumer_tag: _}}, channel) do
    {:noreply, channel, :hibernate}
  end

  @impl true
  def handle_info({:basic_deliver, payload, meta}, channel) do
    result = Command.run(payload)
    Basic.publish(channel, "", meta.reply_to, result, correlation_id: meta.correlation_id)
    Basic.ack(channel, meta.delivery_tag)
    {:noreply, channel, :hibernate}
  end

  @impl true
  def terminate(_, channel) do
    if is_pid(channel.pid) and Process.alive?(channel.pid) do
      Channel.close(channel)
    end

    :normal
  end
end
