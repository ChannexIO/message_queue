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
    retry(
      current_monotonic_time(),
      fn ->
        request_worker({:publish, message, queue, options})
      end,
      Keyword.get(options, :message_id, nil)
    )
  end

  @impl MessageQueue.Adapters.Producer
  def delete_queue(queue, options) do
    retry(
      current_monotonic_time(),
      fn ->
        request_worker({:delete_queue, queue, options})
      end,
      Keyword.get(options, :message_id, nil)
    )
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

  defp retry(start_time, fun, message_id, attempt \\ 0) do
    with {:error, error} <- fun.(),
         message_id <- non_empty_message_id(message_id),
         {:ok, delay} <- set_retry_delay(start_time, attempt, error, message_id) do
      Process.sleep(delay)
      retry(start_time, fun, message_id, attempt + 1)
    else
      :ok ->
        log_retry_success(attempt, message_id)
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  defp set_retry_delay(start_time, attempt, error, message_id) do
    params = Utils.producer_retry_params()
    max_total_time = params[:max_total_time]
    max_delay = params[:max_delay]
    buffer_time = params[:buffer_time]
    now = current_monotonic_time()
    elapsed = now - start_time
    eslaped_verbose = "(#{elapsed / 1000}/#{max_total_time / 1000})"
    delay = delay_for_error_request(attempt, max_delay)

    cond do
      elapsed + delay <= max_total_time ->
        log_retry_warning(
          "#{message_id}: retrying in #{delay} ms (attempt #{attempt + 1}) #{eslaped_verbose} ..."
        )

        {:ok, delay}

      max_total_time - elapsed > buffer_time ->
        adjusted_delay = max_total_time - elapsed - jitter(buffer_time)

        log_retry_warning(
          "#{message_id}: final retry in #{adjusted_delay} ms (attempt #{attempt + 1}) #{eslaped_verbose} ..."
        )

        {:ok, adjusted_delay}

      true ->
        log_retry_warning(
          "#{message_id}: giving up after #{attempt} attempts #{eslaped_verbose}: #{error}"
        )

        {:error, error}
    end
  end

  defp log_retry_warning(warning), do: Logger.warning("#{@module_name} #{warning}")

  defp log_retry_success(0, _message_id), do: :ok

  defp log_retry_success(attempt, message_id) do
    Logger.info("#{@module_name} #{message_id}: success on attempt #{attempt + 1}")
  end

  defp current_monotonic_time, do: System.monotonic_time(:millisecond)

  defp delay_for_error_request(attempt, max_delay) do
    2
    |> Integer.pow(attempt)
    |> :timer.seconds()
    |> min(max_delay)
    |> jitter()
  end

  # Add jitter: 80%–100% of delay to prevent multiple requests from trying
  # to execute at the same time
  defp jitter(delay) do
    min = trunc(delay * 0.8)
    Enum.random(min..delay)
  end

  defp non_empty_message_id(nil) do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64()
  end

  defp non_empty_message_id(message_id), do: message_id
end
