defmodule MessageQueue.Adapters.RabbitMQ.RPCClient do
  @moduledoc false

  @behaviour MessageQueue.Adapters.RPCClient

  @reconnect_interval :timer.seconds(10)
  @call_timeout :timer.seconds(35)

  use AMQP
  use GenServer
  alias MessageQueue.RPCClient.{Request, Response}
  require Logger

  @doc false
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__, hibernate_after: 15_000)
  end

  @impl true
  def call(service_name, function, args, opts \\ []) do
    GenServer.call(__MODULE__, {:exec, {service_name, function, args}, opts}, set_timeout(opts))
  end

  @impl true
  def cast(service_name, function, args) do
    GenServer.cast(__MODULE__, {:exec, {service_name, function, args}})
  end

  @impl true
  def init(state) do
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    with {:ok, conn} <- MessageQueue.get_connection(),
         {:ok, channel} <- Channel.open(conn),
         {:ok, %{queue: queue}} <- Queue.declare(channel, "", auto_delete: true),
         {:ok, _} <- Basic.consume(channel, queue, nil, no_ack: true) do
      Process.monitor(channel.pid)
      {:noreply, %{channel: channel, queue: queue, calls: %{}}}
    else
      _error ->
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
  def handle_info({:DOWN, _, :process, _pid, reason}, _) do
    {:stop, {:connection_lost, reason}, nil}
  end

  def handle_info({_ref, {:ok, _connection}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_consume_ok, %{consumer_tag: _}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_cancel, %{consumer_tag: _}}, state) do
    {:stop, :normal, state}
  end

  def handle_info({:basic_cancel_ok, %{consumer_tag: _}}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, meta}, state) do
    payload
    |> Response.prepare!()
    |> rpc_reply(meta.correlation_id, state)
  end

  def handle_info({:timeout, correlation_id}, state) do
    rpc_reply({:error, :timeout}, correlation_id, state)
  end

  @impl true
  def handle_call({:exec, command, opts}, from, state) do
    with {:ok, %{payload: payload, correlation_id: correlation_id}} <-
           Request.prepare_call(command),
         timeout_ref <- schedule_timeout_error(opts, correlation_id),
         :ok <- publish(command, payload, state, correlation_id) do
      {:noreply, %{state | calls: Map.put(state.calls, correlation_id, {from, timeout_ref})}}
    else
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_cast({:exec, command}, state) do
    with {:ok, %{payload: payload}} <- Request.prepare_cast(command),
         :ok <- publish(command, payload, state) do
      {:noreply, state}
    else
      _ -> {:noreply, state}
    end
  end

  @impl true
  def terminate(_, %{channel: channel} = _state) do
    if is_pid(channel.pid) and Process.alive?(channel.pid) do
      Channel.close(channel)
    end

    :normal
  end

  def terminate(_, _), do: :normal

  defp set_timeout(opts) do
    timeout = opts[:timeout] || @call_timeout
    if is_integer(timeout) and timeout > 0, do: timeout, else: @call_timeout
  end

  defp publish({service_name, _function, _args}, payload, state) do
    Basic.publish(state.channel, "rpc", "", payload, headers: [{service_name, true}])
  end

  defp publish({service_name, _function, _args}, payload, state, correlation_id) do
    Basic.publish(state.channel, "rpc", "", payload,
      headers: [{service_name, true}],
      reply_to: state.queue,
      correlation_id: correlation_id
    )
  end

  defp rpc_reply(reply, correlation_id, %{calls: calls} = state) do
    case Map.pop(calls, correlation_id) do
      {nil, _} ->
        {:noreply, state}

      {{from, timeout_ref}, calls} ->
        Process.cancel_timer(timeout_ref, async: true, info: false)
        GenServer.reply(from, reply)
        {:noreply, %{state | calls: calls}}
    end
  end

  # since on timeout we will get exception and couldn't send timeout error
  # response to the calling process, we schedule timeout error reply that will
  # be sended before the actual timeout
  defp schedule_timeout_error(opts, correlation_id) do
    timeout = set_timeout(opts) - :timer.seconds(5)
    timeout = if timeout >= 0, do: timeout, else: 0
    Process.send_after(__MODULE__, {:timeout, correlation_id}, timeout)
  end
end
