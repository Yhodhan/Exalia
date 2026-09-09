defmodule Exalia.Storage do
  use GenServer

  # -------------------
  #   GenServer calls
  # -------------------

  def start_link(state \\ %{}),
    do: GenServer.start_link(__MODULE__, state, name: __MODULE__)

  # -----------------
  #   Main API calls
  # -----------------

  def store_node(infohash, peer),
    do: GenServer.cast(__MODULE__, {:store_node, infohash, peer})

  def get_nodes(infohash),
    do: GenServer.call(__MODULE__, {:get_nodes, infohash})

  def has_infohash?(infohash),
    do: GenServer.call(__MODULE__, {:hash_infohash, infohash})

  # ----------------------
  #  GenServer functions
  # ----------------------

  @doc """
    Keeps a dictionary with infohash as key and the peers downloading it
  """
  def init(state),
    do: {:ok, state}

  def handle_cast({:store_node, infohash, peer}, state) do
    state =
      if Map.has_key?(state, infohash) do
        nodes = Map.get(state, infohash)
        nodes = nodes ++ [peer]
        Map.put(state, infohash, nodes)
      else
        Map.put(state, infohash, [peer])
      end

    {:noreply, state}
  end

  def handle_call({:get_nodes, infohash}, _from, state) do
    {:reply, Map.get(state, infohash), state}
  end

  def handle_call({:hash_infohash, infohash}, _from, state) do
    {:reply, Map.has_key?(state, infohash), state}
  end
end
