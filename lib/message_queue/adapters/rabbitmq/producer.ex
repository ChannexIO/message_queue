defmodule MessageQueue.Adapters.RabbitMQ.Producer do
  @moduledoc false

  use Supervisor

  @behaviour MessageQueue.Adapters.Producer

  alias MessageQueue.Adapters.RabbitMQ.ProcessRegistry
  alias MessageQueue.Adapters.RabbitMQ.ProducerWorker
  alias MessageQueue.Utils

  require Logger

  @module_name inspect(__MODULE__)
  @default_workers_count 2
  @workers_index_counter Module.concat(__MODULE__, WorkersIndexCounter)

  defguardp pos_integer(term) when is_integer(term) and term > 0

  @impl MessageQueue.Adapters.Producer
  def publish(message, queue, options) do
    retry(current_monotonic_time(), options[:message_id], fn ->
      request_worker({:publish, message, queue, options})
    end)
  end

  @impl MessageQueue.Adapters.Producer
  def delete_queue(queue, options) do
    retry(current_monotonic_time(), options[:message_id], fn ->
      request_worker({:delete_queue, queue, options})
    end)
  end

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      type: :supervisor,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc false
  def start_link(init_args) do
    Supervisor.start_link(__MODULE__, init_args, name: __MODULE__)
  end

  @impl Supervisor
  def init(_init_arg) do
    :ets.new(@workers_index_counter, [:public, :named_table])

    children = [
      {Registry, name: ProcessRegistry, keys: :duplicate},
      set_workers_supervisor_specs()
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp set_workers_supervisor_specs do
    workers_supervisor_name = Module.concat(__MODULE__, WorkersSupervisor)
    workers_supervisor_options = [name: workers_supervisor_name, strategy: :one_for_one]

    %{
      id: workers_supervisor_name,
      type: :supervisor,
      start: {Supervisor, :start_link, [set_workers_specs(), workers_supervisor_options]}
    }
  end

  defp set_workers_specs do
    for index <- 1..get_workers_count() do
      Supervisor.child_spec(ProducerWorker, id: {ProducerWorker, index})
    end
  end

  defp get_workers_count do
    :message_queue
    |> Application.get_env(:producer_workers_count)
    |> format_workers_count()
  end

  defp format_workers_count(count) when is_binary(count) do
    case Integer.parse(count) do
      {count, ""} when count > 0 -> count
      _ -> @default_workers_count
    end
  end

  defp format_workers_count(nil), do: @default_workers_count
  defp format_workers_count(count) when pos_integer(count), do: count
  defp format_workers_count(_count), do: @default_workers_count

  defp request_worker(request) do
    case get_worker_channel() do
      {:ok, channel} -> ProducerWorker.request(channel, request)
      {:error, :no_workers} -> {:error, "MessageQueue service unavailable"}
    end
  catch
    :exit, error -> {:error, "MessageQueue service unavailable: #{inspect(error)}"}
  end

  defp get_worker_channel do
    workers = ProcessRegistry.lookup(:producer_workers)

    case Enum.count(workers) do
      0 ->
        {:error, :no_workers}

      workers_count ->
        next_index = get_and_increment_worker_index(workers_count)
        {_pid, channel} = Enum.at(workers, rem(next_index, workers_count))
        {:ok, channel}
    end
  end

  defp get_and_increment_worker_index(workers_count) do
    default = {_value_pos = 2, _default_value = -1}
    update_operation = {_value_pos = 2, _incr = 1, _threshold = workers_count, _set_value = 1}
    :ets.update_counter(@workers_index_counter, :worker_index, update_operation, default)
  end

  defp retry(start_time, message_id, fun, attempt \\ 0) do
    %{}
    |> Map.put(:message_id, message_id)
    |> Map.put(:attempt, attempt)
    |> Map.put(:start_time, start_time)
    |> Map.put(:fun, fun)
    |> retry(fun.())
  end

  defp retry(params, :ok) when params.attempt == 0, do: :ok

  defp retry(params, :ok) do
    log_retry_success(params)
    :ok
  end

  defp retry(params, {:error, error}) when params.attempt == 0 do
    retry_params = Utils.producer_retry_params()

    params
    |> Map.update!(:message_id, &set_message_id/1)
    |> Map.put(:max_total_time, retry_params[:max_total_time])
    |> Map.put(:max_delay, retry_params[:max_delay])
    |> Map.put(:buffer_time, retry_params[:buffer_time])
    |> Map.put(:error, error)
    |> set_retry_delay()
    |> retry()
  end

  defp retry(params, {:error, error}) do
    params
    |> Map.put(:error, error)
    |> set_retry_delay()
    |> retry()
  end

  defp retry(params) when params.retry do
    log_retry_warning(params)
    Process.sleep(params.delay)
    retry(params, params.fun.())
  end

  defp retry(params) do
    log_retry_warning(params)
    {:error, params.error}
  end

  defp set_retry_delay(params) do
    now = current_monotonic_time()
    delay = delay_for_error_request(params)
    elapsed = now - params.start_time
    remain = ms_to_sec(params.max_total_time - elapsed)

    cond do
      elapsed + delay <= params.max_total_time ->
        warning_info = "retry $attempt in $delay ms ($remain s left), error: $error"

        params
        |> Map.update!(:attempt, &(&1 + 1))
        |> Map.put(:retry, true)
        |> Map.put(:warning, warning_info)
        |> Map.put(:delay, delay)
        |> Map.put(:remain, remain)

      params.max_total_time - elapsed > params.buffer_time ->
        warning_info = "final retry $attempt in $delay ms ($remain s left), error: $error"
        adjusted_delay = params.max_total_time - elapsed - jitter(params.buffer_time)

        params
        |> Map.update!(:attempt, &(&1 + 1))
        |> Map.put(:retry, true)
        |> Map.put(:warning, warning_info)
        |> Map.put(:delay, adjusted_delay)
        |> Map.put(:remain, remain)

      true ->
        warning_info = "giving up after $attempt attempts, elapsed $elapsed ms, error: $error"

        params
        |> Map.put(:retry, false)
        |> Map.put(:elapsed, elapsed)
        |> Map.put(:warning, warning_info)
    end
  end

  defp log_retry_warning(params) do
    "#{@module_name} $message_id: #{params.warning}"
    |> Utils.interpolate_template(params)
    |> Logger.warning()
  end

  defp log_retry_success(params) do
    Logger.info("#{@module_name} #{params.message_id}: success on attempt #{params.attempt}")
  end

  defp set_message_id(nil) do
    timestamp = System.os_time()
    suffix = Base.encode32(:crypto.strong_rand_bytes(4), padding: false)
    "msg_#{timestamp}_#{suffix}"
  end

  defp set_message_id(message_id), do: message_id

  defp current_monotonic_time, do: System.monotonic_time(:millisecond)

  defp ms_to_sec(ms), do: Float.round(ms / 1000, 1)

  defp delay_for_error_request(params) do
    2
    |> Integer.pow(params.attempt)
    |> :timer.seconds()
    |> min(params.max_delay)
    |> jitter()
  end

  # Add jitter: 80%–100% of delay to prevent multiple requests from trying
  # to execute at the same time
  defp jitter(delay) do
    min = trunc(delay * 0.8)
    Enum.random(min..delay)
  end
end
