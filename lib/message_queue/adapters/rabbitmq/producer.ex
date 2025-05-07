defmodule MessageQueue.Adapters.RabbitMQ.Producer do
  @moduledoc false

  use Supervisor

  @behaviour MessageQueue.Adapters.Producer

  alias MessageQueue.Adapters.RabbitMQ.{ProcessRegistry, ProducerWorker}

  require Logger

  @default_workers_count 2
  @workers_index_counter Module.concat(__MODULE__, WorkersIndexCounter)
  @max_attempts 5

  defguardp pos_integer(term) when is_integer(term) and term > 0

  @impl MessageQueue.Adapters.Producer
  def publish(message, queue, options) do
    request_worker({:publish, message, queue, options})
  end

  @impl MessageQueue.Adapters.Producer
  def delete_queue(queue, options) do
    request_worker({:delete_queue, queue, options})
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

  defp request_worker(request, attempt \\ 0)
  defp request_worker(request, attempt) when attempt < @max_attempts do
    case get_worker_channel() do
      {:ok, channel} -> ProducerWorker.request(channel, request)
      {:error, :no_workers} ->
        Process.sleep(delay_for_error_request(attempt))
        request_worker(request, attempt + 1)
    end
  end

  defp request_worker(_request, _attempt) do
    {:error, "MessageQueue service unavailable"}
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

  defp delay_for_error_request(attempt) do
    2
    |> Integer.pow(attempt)
    |> :timer.seconds()
  end
end
