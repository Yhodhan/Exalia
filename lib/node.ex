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

    :gen_udp.send(state.socket, ip, port, msg)

    Logger.info("=== Ping sent ===")

    pending = Map.put(state.pending, tid, from)
    {:noreply, %{state | pending: pending}}
  end

  def handle_info({:udp, _socket, _ip, _port, data}, state) do
    Logger.info("=== Ping received ===")
    case Decoder.decode(data) do
      {:ok, %{"t" => tid} = response} ->
        case(Map.pop(state.pending, tid)) do
          {nil, _pending} ->
            # unwanted package
            {:noreply, state}

          {from, pending} ->
            GenServer.reply(from, response)
            {:noreply, %{state | pending: pending}}
        end

      _ ->
        {:noreply, state}
    end
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
end
