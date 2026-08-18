defmodule Exalia.KNode do
  alias Exalia.RoutingTable
  alias Exalia.KRPC
  alias Bencoder.Decoder
  alias Exalia.Candidate

  use GenServer
  require Logger

  @id_size_bytes 20
  @time_out 5_000

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

    {:ok, pid} = start_link(state)
    {:ok, pid, id}
  end

  # -------------------
  #   GenServer calls
  # -------------------

  def start_link(state \\ []),
    do: GenServer.start_link(__MODULE__, state)

  def ping(pid, host, port) do
    try do
      GenServer.call(pid, {:ping, host, port}, @time_out)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  def contacs(pid),
    do: GenServer.call(pid, :contacts)

  def find_node(pid, contact, target) do
    try do
      GenServer.call(pid, {:find_node, contact, target}, @time_out)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  def get_peers(pid),
    do: GenServer.call(pid, :get_peers)

  def get_node_id(pid),
    do: GenServer.call(pid, :node_id)

  def get_routing_table(pid),
    do: GenServer.call(pid, :routing_table)

  # ----------------------
  #  GenServer functions
  # ----------------------

  def init(state) do
    {:ok, socket} = :gen_udp.open(0, [:binary, :inet, {:active, true}])
    {:ok, %{state | socket: socket, pending: %{}}}
  end

  def handle_call(:contacts, _from, state) do
    contacts =
      Map.values(state.routing_table.kbuckets)
      |> List.flatten()

    {:reply, contacts, state}
  end

  # -----------------
  #      PING 
  # ----------------- 
  def handle_call({:ping, host, port}, from, state) do
    tid = transaction_id()

    {:ok, msg} = KRPC.ping(tid, state.id)
    {:ok, ip} = :inet.getaddr(String.to_charlist(host), :inet)

    :gen_udp.send(state.socket, ip, port, msg)

    Process.send_after(self(), {:request_timeout, tid}, @time_out)

    Logger.info("=== Ping sent ===")

    pending = Map.put(state.pending, tid, from)
    {:noreply, %{state | pending: pending}}
  end

  # -----------------
  #     FIND NODE 
  # ----------------- 
  def handle_call({:find_node, contact, target}, from, state) do
    tid = transaction_id()

    {:ok, msg} = KRPC.find_node(tid, state.id, target)

    :gen_udp.send(state.socket, contact.ip, contact.port, msg)

    Logger.info("=== Find Node Request ===")

    pending = Map.put(state.pending, tid, from)
    {:noreply, %{state | pending: pending}}
  end

  def handle_call(:get_peers, _from, _state) do
    nil
  end

  # ---------------------------
  #        Getter Functions
  # ---------------------------
  def handle_call(:routing_table, _from, state),
    do: {:reply, state.routing_table, state}

  def handle_call(:node_id, _from, state),
    do: {:reply, state.id, state}

  # ---------------------------
  #    Handle Port connection 
  # ---------------------------

  def handle_info({:udp, _socket, ip, port, data}, state) do
    Logger.info("=== Response received ===")

    with {:ok, data} <- Decoder.decode(data),
         {:ok, tid, response} <- analyze_response(data),
         {:ok, from, pending} <- fetch_tx(tid, state) do
      {response, state} = handle_response(state, response, {ip, port})
      GenServer.reply(from, response)
      {:noreply, %{state | pending: pending}}
    else
      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:request_timeout, tid}, state) do
    case Map.pop(state.pending, tid) do
      {nil, _pending} ->
        {:noreply, state}

      {from, pending} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending: pending}}
    end
  end

  # ---------------------------
  #   Handle network responses
  # ---------------------------

  def handle_response(state, response, address) do
    case response["r"] do
      %{"id" => id, "token" => token, "nodes" => nodes} ->
        handle_get_peers(state, id, token, nodes)

      %{"id" => _id, "nodes" => nodes} ->
        handle_find_node(state, nodes)

      %{"id" => id} ->
        handle_ping(state, id, address)

      _ ->
        {:unknown_command, state}
    end
  end

  def handle_ping(state, raw_id, {ip, port}) do
    Logger.info("=== Ping received ===")
    # store the node in the routing table
    id = :binary.decode_unsigned(raw_id)
    candidate = Candidate.new(id, ip, port)
    table = RoutingTable.insert(state.routing_table, candidate)

    {:pong, %{state | routing_table: table}}
  end

  def handle_find_node(state, nodes) do
    Logger.info("=== Find Nodes received ===")

    decoded_nodes =
      parse_nodes(nodes)
      |> Enum.uniq_by(& &1.id)

    table =
      decoded_nodes
      |> Enum.reduce(state.routing_table, fn n, table ->
        RoutingTable.insert(table, n)
      end)

    {decoded_nodes, %{state | routing_table: table}}
  end

  def handle_get_peers(_state, _id, _token, values) when is_list(values) do
  end

  def handle_get_peers(_state, _id, _token, _nodes) do
  end

  def handle_announce_peers() do
  end

  # ------------------
  # Private functions
  # ------------------

  defp parse_nodes(<<>>), do: []

  defp parse_nodes(<<id::binary-size(20), a, b, c, d, port::binary-size(2), rest::binary>>) do
    id = :binary.decode_unsigned(id)
    ip = {a, b, c, d}
    port = :binary.decode_unsigned(port)
    candidate = Candidate.new(id, ip, port)

    [candidate] ++ parse_nodes(rest)
  end

  defp generate_id() do
    bytes = :crypto.strong_rand_bytes(@id_size_bytes)
    :binary.decode_unsigned(bytes)
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
      {nil, _pending} -> :error
      {from, pending} -> {:ok, from, pending}
    end
  end
end
