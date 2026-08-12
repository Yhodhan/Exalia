defmodule Exalia.Node do
  alias Exalia.RoutingTable

  use GenServer

  @id_size_bytes 20

  defstruct [
    :routing_table,
    :id
  ]

  def new() do
    id = generate_id()
    rtable = RoutingTable.new(id)

    %__MODULE__{
      routing_table: rtable,
      id: id
    }
  end

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

  defp generate_id() do
    :crypto.strong_rand_bytes(@id_size_bytes)
    |> :binary.decode_unsigned()
  end
end
