defmodule MessageQueue.Utils do
  @moduledoc false

  defguardp non_neg_integer(term) when is_integer(term) and term >= 0

  @doc false
  def call_timeout do
    case :persistent_term.get({__MODULE__, :gen_server_call_timeout}, :undefined) do
      :undefined ->
        timeout = Application.get_env(:message_queue, :gen_server_call_timeout, 15_000)
        :persistent_term.put({__MODULE__, :gen_server_call_timeout}, timeout)
        timeout

      timeout ->
        timeout
    end
  end

  @doc false
  def update_call_timeout(timeout) when non_neg_integer(timeout) or timeout == :infinity do
    Application.put_env(:message_queue, :gen_server_call_timeout, timeout)
    :persistent_term.put({__MODULE__, :gen_server_call_timeout}, timeout)
  end

  @producer_retry_opts_schema [
    max_total_time: [
      doc: "Max total retry time in milliseconds",
      type: :non_neg_integer,
      default: :timer.seconds(60)
    ],
    buffer_time: [
      doc: "Final retry must leave this many milliseconds before timeout",
      type: :non_neg_integer,
      default: :timer.seconds(4)
    ],
    max_delay: [
      doc: "Maximum delay per retry in milliseconds",
      type: :non_neg_integer,
      default: :timer.seconds(8)
    ]
  ]

  @doc false
  def producer_retry_params do
    case :persistent_term.get({__MODULE__, :producer_retry_params}, :undefined) do
      :undefined ->
        params = Application.get_env(:message_queue, :producer_retry_params, [])
        validated = validate_producer_retry_params(params)
        :persistent_term.put({__MODULE__, :producer_retry_params}, validated)
        validated

      params ->
        params
    end
  end

  @doc false
  def update_producer_retry_params(params) when is_map(params) do
    params
    |> Map.to_list()
    |> update_producer_retry_params()
  end

  def update_producer_retry_params(params) when is_list(params) do
    with {:ok, validated} <- NimbleOptions.validate(params, @producer_retry_opts_schema) do
      :persistent_term.put({__MODULE__, :producer_retry_params}, validated)
      Application.put_env(:message_queue, :producer_retry_params, validated)
      {:ok, validated}
    end
  end

  defp validate_producer_retry_params(params) do
    case NimbleOptions.validate(params, @producer_retry_opts_schema) do
      {:ok, validated} -> validated
      {:error, _error} -> NimbleOptions.validate!([], @producer_retry_opts_schema)
    end
  end
end
