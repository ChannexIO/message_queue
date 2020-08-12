defmodule MessageQueue.Adapters.RabbitMQ.RPCClient do
  @moduledoc false

  @reconnect_interval 10_000
  @call_timeout 30_000

  use AMQP
  use GenServer
  alias MessageQueue.RPCClient.{Request, Response}
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def call(module, function, args) do
    GenServer.call(__MODULE__, {:exec, {module, function, args}}, @call_timeout)
  end

  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    connection = MessageQueue.connection()

    with {:ok, conn} <- Connection.open(connection),
         {:ok, channel} <- Channel.open(conn),
         {:ok, %{queue: queue}} <- Queue.declare(channel, "", exclusive: true),
         {:ok, _} <- Basic.consume(channel, queue, nil, no_ack: true) do
      {:noreply, %{channel: channel, queue: queue, calls: %{}}, :hibernate}
    else
      {:error, _} ->
        Logger.error("Failed to connect RabbitMQ. Reconnecting later...")
        Process.sleep(@reconnect_interval)
        {:noreply, state, {:continue, :connect}}
    end
  end

  @impl true
  def handle_info({:EXIT, _, :normal}, _state) do
    {:stop, :normal, nil}
  end

  @impl true
  def handle_info({:basic_consume_ok, %{consumer_tag: _}}, state) do
    {:noreply, state, :hibernate}
  end

  @impl true
  def handle_info({:basic_cancel, %{consumer_tag: _}}, state) do
    {:stop, :normal, state, :hibernate}
  end

  @impl true
  def handle_info({:basic_cancel_ok, %{consumer_tag: _}}, state) do
    {:noreply, state, :hibernate}
  end

  @impl true
  def handle_info({:basic_deliver, payload, meta}, state) do
    payload
    |> Response.prepare()
    |> rpc_reply(meta.correlation_id, state)
  end

  @impl true
  def handle_info({:timeout, correlation_id}, state) do
    rpc_reply({:error, :timeout}, correlation_id, state)
  end

  @impl true
  def handle_call({:exec, command}, from, %{channel: channel, queue: queue, calls: calls} = state) do
    with {:ok, %{payload: payload, correlation_id: correlation_id}} <- Request.prepare(command),
         :ok <-
           Basic.publish(channel, "", MessageQueue.rpc_queue(), payload,
             reply_to: queue,
             correlation_id: correlation_id
           ) do
      Process.send_after(RPCClient, {:timeout, correlation_id}, @call_timeout)

      {:noreply, %{state | calls: Map.put(calls, correlation_id, from)}}
    else
      error -> {:reply, error, state}
    end
  end

  @impl true
  def terminate(_, %{channel: channel} = _state) do
    if is_pid(channel[:pid]) and Process.alive?(channel[:pid]) do
      Channel.close(channel)
    end

    :normal
  end

  @impl true
  def terminate(_, _), do: :normal

  defp rpc_reply(reply, correlation_id, %{calls: calls} = state) do
    case Map.pop(calls, correlation_id) do
      {nil, _} ->
        {:noreply, state, :hibernate}

      {from, calls} ->
        GenServer.reply(from, reply)
        {:noreply, %{state | calls: calls}, :hibernate}
    end
  end
end
