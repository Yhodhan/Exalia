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
    do: GenServer.call(__MODULE__, {:has_infohash, infohash})

  # ----------------------
  #  GenServer functions
  # ----------------------

  @doc """
    Keeps a dictionary with infohash as key and the peers downloading it
  """
  def init(state),
    do: {:ok, state}

  def handle_cast({:store_node, infohash, peer}, state) do
    nodes = Map.get(state, infohash, [])

    update_nodes =
      if Enum.any?(state, &(&1.id == peer.id)),
        do: Enum.map(nodes, fn n -> if n.id == peer.id, do: peer, else: n end),
        else: [peer | nodes]

    {:noreply, Map.put(state, infohash, update_nodes)}
  end

  def handle_call({:get_nodes, infohash}, _from, state) do
    {:reply, Map.get(state, infohash, []), state}
  end

  def handle_call({:has_infohash, infohash}, _from, state) do
    {:reply, Map.has_key?(state, infohash), state}
  end
end
