defmodule ServiceAppTest do
  use ExUnit.Case
  doctest ServiceApp

  test "greets the world" do
    assert ServiceApp.hello() == :world
  end
end
