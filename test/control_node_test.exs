defmodule ControlNodeTest do
  use ExUnit.Case
  doctest ControlNode

  test "greets the world" do
    assert ControlNode.hello() == :world
  end
end
