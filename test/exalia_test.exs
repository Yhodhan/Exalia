defmodule ExaliaTest do
  use ExUnit.Case
  doctest Exalia

  test "greets the world" do
    assert Exalia.hello() == :world
  end
end
