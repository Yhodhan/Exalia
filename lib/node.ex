defmodule Exalia.KNode do
  alias Exalia.RoutingTable
  alias Exalia.KRPC
  alias Bencoder.Decoder
  alias Exalia.Config
  alias Message.QueryMessage
  alias Message.ResponseMessage

  use GenServer
  require Logger

  @id_size_bytes 20
  @time_out 2_000

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

  def start_link(state \\ %{}),
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
    port = Config.dht_port()

    case :gen_udp.open(port, [:binary, :inet, {:active, true}]) do
      {:ok, socket} ->
        {:ok, %{state | socket: socket, pending: %{}}}

      {:error, :eaddriuse} ->
        Logger.warning("Port #{port} in use, falling back to random port")
        {:ok, socket} = :gen_udp.open(0, [:binary, :inet, {:active, true}])
        {:ok, %{state | socket: socket, pending: %{}}}
    end
  end

  def handle_call(:contacts, _from, state) do
    contacts = RoutingTable.get_contacts(state.routing_table)

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
         {:ok, type, data} <- analyze_response(data) do
      case type do
        :response ->
          process_response(data, state, {ip, port})

        :query ->
          handle_query(state, data["q"], data, {ip, port})

        :error ->
          handle_error(state, data)
      end
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

  def process_response(data, state, {ip, port}) do
    case fetch_tx(data["t"], state) do
      {:ok, {from, type}, pending} ->
        {response, state} = handle_response(state, type, data, {ip, port})
        GenServer.reply(from, response)
        {:noreply, %{state | pending: pending}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_response(state, :ping, response, address),
    do: ResponseMessage.ping(state, response, address)

  def handle_response(state, :find_node, response, _address),
    do: ResponseMessage.find_node(state, response)

  def handle_response(state, :get_peers, response, _address),
    do: ResponseMessage.get_peers(state, response)

  def handle_response(state, :announce_peers, response, _address),
    do: ResponseMessage.announce_peer(state, response)

  def handle_response(state, _type, _response, {ip, port}) do
    Logger.warning(
      "=== Unknown Reponse received from address: #{inspect(ip)} port: #{inspect(port)}"
    )

    {:noreply, state}
  end

  # ----------------------------------------------------
  #               HANDLE NETWORK QUERIES
  # ----------------------------------------------------

  def handle_query(state, "ping", query, address),
    do: {:noreply, QueryMessage.ping(state, query, address)}

  def handle_query(state, "find_node", query, address),
    do: {:noreply, QueryMessage.find_node(state, query, address)}

  def handle_query(state, "get_peers", query, address),
    do: {:noreply, QueryMessage.get_peers(state, query, address)}

  def handle_query(state, type, _, {ip, port}) do
    Logger.warning(
      "=== Unknown Query received : #{inspect(type)} from address: #{inspect(ip)} port: #{inspect(port)}"
    )

    {:noreply, state}
  end

  # ----------------------------------------------------
  #               HANDLE NETWORK QUERIES
  # ----------------------------------------------------

  def handle_error(state, data) do
    # Bencoded error responses contain an "e" key with [error_code, error_message]
    case Map.get(data, "e") do
      [code, message] ->
        Logger.error("DHT Node returned error #{code}: #{message}")

      # NOTE: remove the peer from the routing table and the pending transactions

      _ ->
        Logger.error("DHT Node returned malformed error structure: #{inspect(data)}")
    end

    {:noreply, state}
  end

  # ----------------------------------------------------
  #                   PRIVATE FUNCTIONS
  # ----------------------------------------------------

  defp generate_id() do
    bytes = :crypto.strong_rand_bytes(@id_size_bytes)
    :binary.decode_unsigned(bytes)
  end

  defp transaction_id(),
    do: :crypto.strong_rand_bytes(2)

  defp analyze_response(data) do
    case data do
      %{"y" => "r"} ->
        # {:ok, data["t"], data}
        {:ok, :response, data}

      %{"y" => "q"} ->
        {:ok, :query, data}

      %{"y" => "e"} ->
        {:ok, :error, data}

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
end
