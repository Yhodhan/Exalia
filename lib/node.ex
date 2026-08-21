defmodule Exalia.KNode do
  alias Exalia.RoutingTable
  alias Exalia.KRPC
  alias Bencoder.Decoder
  alias Exalia.Candidate

  use GenServer
  require Logger

  @id_size_bytes 20
  @time_out 1_000

  defstruct [
    :routing_table,
    :id,
    :port,
    :socket,
    tokens: %{},
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

  # -----------------
  #   Main API calls
  # -----------------

  def ping(pid, host, port) do
    try do
      GenServer.call(pid, {:ping, host, port}, @time_out)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  def find_node(pid, contact, target) do
    try do
      GenServer.call(pid, {:find_node, contact, target}, @time_out)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  def get_peers(pid, contact, infohash) do
    try do
      GenServer.call(pid, {:get_peers, contact, infohash}, @time_out)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  def announce_peer(pid, contact, infohash, port, token) do
    try do
      GenServer.call(pid, {:announce_peer, contact, infohash, port, token}, @time_out)
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  # ------------------
  #  Helper functions
  # ------------------

  def contacs(pid),
    do: GenServer.call(pid, :contacts)

  def get_node_id(pid),
    do: GenServer.call(pid, :node_id)

  def get_routing_table(pid),
    do: GenServer.call(pid, :routing_table)

  def get_tokens(pid),
    do: GenServer.call(pid, :tokens)

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

    Logger.info("=== Ping Request sent ===")

    pending = Map.put(state.pending, tid, {from, :ping})
    {:noreply, %{state | pending: pending}}
  end

  # -----------------
  #     FIND NODE 
  # ----------------- 
  def handle_call({:find_node, contact, target}, from, state) do
    tid = transaction_id()

    {:ok, msg} = KRPC.find_node(tid, state.id, target)

    :gen_udp.send(state.socket, contact.ip, contact.port, msg)

    Logger.info("=== Find Node Request Sent ===")

    pending = Map.put(state.pending, tid, {from, :find_node})
    {:noreply, %{state | pending: pending}}
  end

  def handle_call({:get_peers, contact, infohash}, from, state) do
    tid = transaction_id()

    {:ok, msg} = KRPC.get_peers(tid, state.id, infohash)

    :gen_udp.send(state.socket, contact.ip, contact.port, msg)

    Logger.info("=== Get Peers Request Sent ===")

    pending = Map.put(state.pending, tid, {from, :get_peers})
    {:noreply, %{state | pending: pending}}
  end

  def handle_call({:announce_peer, contact, infohash, port, token}, from, state) do
    tid = transaction_id()

    {:ok, msg} = KRPC.announce_peer(tid, state.id, infohash, port, token)

    :gen_udp.send(state.socket, contact.ip, contact.port, msg)

    Logger.info("=== Announce Peer Sent ===")

    pending = Map.put(state.pending, tid, {from, :announce_peer})
    {:noreply, %{state | pending: pending}}
  end

  # ---------------------------
  #        Getter Functions
  # ---------------------------
  def handle_call(:routing_table, _from, state),
    do: {:reply, state.routing_table, state}

  def handle_call(:node_id, _from, state),
    do: {:reply, state.id, state}

  def handle_call(:tokens, _from, state),
    do: {:reply, state.tokens, state}

  # ---------------------------
  #    Handle Port connection 
  # ---------------------------

  def handle_info({:udp, _socket, ip, port, data}, state) do
    Logger.info("=== Response received ===")

    result =
      try do
        Decoder.decode(data)
      rescue
        _ -> :error
      end

    with {:ok, data} <- result,
         {:ok, tid, response} <- analyze_response(data),
         {:ok, {from, type}, pending} <- fetch_tx(tid, state) do
      {response, state} = handle_response(state, type, response, {ip, port})
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

  # ----------------------------------------------------
  #               HANDLE NETWORK RESPONSES
  # ----------------------------------------------------

  def handle_response(state, :ping, response, address),
    do: handle_ping(state, response, address)

  def handle_response(state, :find_node, response, _address),
    do: handle_find_node(state, response)

  def handle_response(state, :get_peers, response, _address),
    do: handle_get_peers(state, response)

  def handle_response(state, :announce_peers, response, _address),
    do: handle_announce_peer(state, response)

  def handle_response(state, _type, _response, _address),
    do: {:unknown_command, state}

  # ----------------------------------------------------
  #                       PING 
  # ----------------------------------------------------

  def handle_ping(state, response, {ip, port}) do
    Logger.info("=== Ping received ===")
    %{"id" => id} = response["r"]
    # store the node in the routing table
    id = :binary.decode_unsigned(id)
    candidate = Candidate.new(id, ip, port)
    table = RoutingTable.insert(state.routing_table, candidate)

    {:pong, %{state | routing_table: table}}
  end

  # ----------------------------------------------------
  #                     FIND NODE
  # ----------------------------------------------------

  def handle_find_node(state, response) do
    Logger.info("=== Find Nodes received ===")
    %{"id" => _id, "nodes" => nodes} = response["r"]

    {decoded_nodes, table} = fill_routing_table(state, nodes)

    {decoded_nodes, %{state | routing_table: table}}
  end

  # ----------------------------------------------------
  #                     GET PEERS 
  # ----------------------------------------------------

  def handle_get_peers(state, response) do
    case response["r"] do
      %{"id" => id, "token" => token, "nodes" => nodes} ->
        Logger.info("=== Get Peers Received: Nodes ===")
        id = :binary.decode_unsigned(id)
        tokens = Map.put(state.tokens, id, token)

        {decoded_nodes, table} = fill_routing_table(state, nodes)

        {{:nodes, decoded_nodes}, %{state | routing_table: table, tokens: tokens}}

      %{"id" => id, "token" => token, "values" => values} ->
        Logger.info("=== Get Peers Received: Peers ===")
        id = :binary.decode_unsigned(id)
        tokens = Map.put(state.tokens, id, token)

        peers = Enum.map(values, fn v -> decode_peer(v) end)

        {{:peers, peers}, %{state | tokens: tokens}}

      _ ->
        Logger.warning("Unexpected get_peers response shape: #{inspect(response)}")
        {{:error, :unexpected_response}, state}
    end
  end

  # ----------------------------------------------------
  #                    ANNOUNCE PEERS 
  # ----------------------------------------------------

  def handle_announce_peer(state, _response) do
    # nothing to store — just acknowledge success to the caller
    {:announced, state}
  end

  # ----------------------------------------------------
  #                   PRIVATE FUNCTIONS
  # ----------------------------------------------------

  defp parse_nodes(bytes) do
    case bytes do
      <<>> ->
        []

      <<id::binary-size(20), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, a, b, c, d,
        port::binary-size(2), rest::binary>> ->
        build_candidate(id, {a, b, c, d}, port) ++ parse_nodes(rest)

      <<id::binary-size(20), a, b, c, d, port::binary-size(2), rest::binary>> ->
        build_candidate(id, {a, b, c, d}, port) ++ parse_nodes(rest)

      leftover ->
        Logger.warning(
          "=== Unparseable trailing node bytes (#{byte_size(leftover)} bytes), dropping ==="
        )

        []
    end
  end

  defp build_candidate(id, ip, port) do
    id = :binary.decode_unsigned(id)
    port = :binary.decode_unsigned(port)
    candidate = Candidate.new(id, ip, port)
    [candidate]
  end

  defp decode_peer(<<a, b, c, d, port::16>>),
    do: {{a, b, c, d}, port}

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
      {from_and_type, pending} -> {:ok, from_and_type, pending}
    end
  end

  def fill_routing_table(state, nodes) do
    decoded_nodes =
      parse_nodes(nodes)
      |> Enum.uniq_by(& &1.id)

    {decoded_nodes,
     decoded_nodes
     |> Enum.reject(&(&1.id == state.id))
     |> Enum.reduce(state.routing_table, fn n, table ->
       RoutingTable.insert(table, n)
     end)}
  end
end
