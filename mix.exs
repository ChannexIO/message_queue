defmodule MessageQueue.MixProject do
  use Mix.Project

  @name "MessageQueue"
  @version "0.6.2"
  @repo_url "https://github.com/ChannexIO/message_queue"

  def project do
    [
      app: :message_queue,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      name: @name,
      source_url: @repo_url,
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MessageQueue.Application, []}
    ]
  end

  defp deps do
    [
      {:amqp, "~> 3.1"},
      {:jason, "~> 1.3"}
    ]
  end

  def docs do
    [
      source_ref: "v#{@version}",
      source_url: @repo_url,
      main: @name
    ]
  end
end
