defmodule MessageQueue.Utils do
  @moduledoc false

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
  def update_call_timeout(timeout)
      when (is_integer(timeout) and timeout >= 0) or timeout == :infinity do
    Application.put_env(:message_queue, :gen_server_call_timeout, timeout)
    :persistent_term.put({__MODULE__, :gen_server_call_timeout}, timeout)
  end
end
