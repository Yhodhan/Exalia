defmodule Exalia.KNode do
  alias Exalia.RoutingTable
  alias Exalia.KRPC
  alias Bencoder.Decoder

  use GenServer
  require Logger

  @id_size_bytes 20

  defstruct [
    :routing_table,
    :id,
    :port,
    :socket,
    pending: %{}
  ]

  def new() do
    id = generate_id()
    rtable = RoutingTable.new(id)

    state = %__MODULE__{
      routing_table: rtable,
      id: id
    }

    start_link(state)
  end

  # -------------------
  #   GenServer calls
  # -------------------

  def start_link(state \\ []),
    do: GenServer.start_link(__MODULE__, state)

  def ping(pid, host, port),
    do: GenServer.call(pid, {:ping, host, port}, 5_000)

  def store() do
  end

  def find_node() do
  end

  def find_value() do
  end

  # ----------------------
  #  GenServer functions
  # ----------------------

  def init(state) do
    {:ok, socket} = :gen_udp.open(0, [:binary, :inet, {:active, true}])
    {:ok, %{state | socket: socket, pending: %{}}}
  end

  def handle_call({:ping, host, port}, from, state) do
    tid = transaction_id()

    {:ok, msg} = KRPC.ping(state.id, tid)
    {:ok, ip} = :inet.getaddr(String.to_charlist(host), :inet)

    result = :gen_udp.send(state.socket, ip, port, msg)

    Logger.info("=== Package sent ===")

    pending = Map.put(state.pending, tid, from)
    {:noreply, %{state | pending: pending}}
  end

  def handle_info({:udp, _socket, _ip, _port, data}, state) do
    Logger.info("=== Response received ===")

    with {:ok, data} <- Decoder.decode(data),
         {:ok, tid, response} <- analyze_response(data),
         {:ok, from, pending} <- fetch_tx(tid, state) do
      state = handle_response(state, from, response)
      #        GenServer.reply(from, response)
      #        {:noreply, %{state | pending: pending}}
    else
      _ ->
        {:noreply, state}
    end
  end

  def handle_response(state, from, response) do
    res = response["r"]

    case res do
      %{"id" => id, "token" => token, "nodes" => nodes} ->
        handle_get_peers(state, id, token, nodes)

      %{"id" => id, "nodes" => nodes} ->
        handle_find_node(state, id, nodes)

      %{"id" => id} ->
        handle_ping(state, id)
    end
  end

  def handle_ping(state, id) do
    # store the node in the routing table
    table = RoutingTable.insert(state.routing_table, id)
    %{state | table: table}
  end

  def handle_find_node(state, id, nodes) do
  end

  def handle_get_peers(state, id, token, values) when is_list(values) do
  end

  def handle_get_peers(state, id, token, nodes) do
  end

  def handle_announce_peers() do
  end

  # ------------------
  # Private functions
  # ------------------

  defp generate_id() do
    :crypto.strong_rand_bytes(@id_size_bytes)
    |> :binary.decode_unsigned()
  end

  defp transaction_id(),
    do: :crypto.strong_rand_bytes(2)

  defp analyze_response(data) do
    case data do
      %{"y" => "r"} ->
        {:ok, data["t"], data}

      _ ->
        {:error, data}
    end
  end

  defp fetch_tx(tid, state) do
    case Map.pop(state.pending, tid) do
      {nil, _pending} ->
        {:noreply, state}

      {from, pending} ->
        {:ok, from, pending}
    end
  end
end
