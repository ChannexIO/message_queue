defmodule MessageQueue.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    :logger.add_primary_filter(
      :ignore_rabbitmq_progress_reports,
      {&:logger_filters.domain/2, {:stop, :equal, [:progress]}}
    )

    children = [
      MessageQueue.Connection,
      MessageQueue.Producer,
      MessageQueue.RPCClient,
      MessageQueue.RPCServer
    ]

    opts = [strategy: :one_for_one, name: __MODULE__, max_restarts: 100]
    Supervisor.start_link(children, opts)
  end
end
