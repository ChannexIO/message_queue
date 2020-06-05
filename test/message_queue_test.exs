defmodule MessageQueueTest do
  use ExUnit.Case
  doctest MessageQueue

  test "greets the world" do
    assert MessageQueue.hello() == :world
  end
end
