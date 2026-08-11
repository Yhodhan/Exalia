defmodule Node do
  use GenServer

  # -------------------
  #   GenServer calls
  # -------------------

  def start_link(state \\ []),
    do: GenServer.start_link(__MODULE__, state)

  def ping() do
  end

  def store() do
  end

  def find_node() do
  end

  def find_value() do
  end

  # ----------------------
  #   GenServer functions
  # ----------------------

  def init(state),
    do: {:ok, state}

  # ------------------
  # Private functions
  # ------------------
end
