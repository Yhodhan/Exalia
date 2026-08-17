defmodule Exalia.RoutingTable do
  import Bitwise

  alias Exalia.KBucket
  alias Exalia.Candidate

  defstruct [
    :id,
    :kbuckets
  ]

  def new(own_id) do
    %__MODULE__{
      kbuckets: %{},
      id: own_id
    }
  end

  def insert(table, %Candidate{} = candidate) do
    {bucket, index} = get_bucket(table, candidate.id)
    new_bucket = KBucket.insert(bucket, candidate)
    put_bucket(table, index, new_bucket)
  end

  def fetch_bucket(table, index) do
    table
    |> Map.get(:kbuckets)
    |> Map.get(index, [])
  end

  def put_bucket(%__MODULE__{} = table, index, bucket) do
    %__MODULE__{table | kbuckets: Map.put(table.kbuckets, index, bucket)}
  end

  def get_candidate(table, id) do
    {bucket, _index} = get_bucket(table, id)

    bucket
    |> Enum.find(fn c -> c.id == id end)
  end

  # ------------------
  # Private functions
  # ------------------

  defp xor_distance(a, b) do
    a = conversion(a)
    b = conversion(b)

    bxor(a, b)
  end

  defp get_bucket(table, id) do
    distance = xor_distance(table.id, id)
    index = bucket_index(distance)

    {fetch_bucket(table, index), index}
  end

  # """
  # Obtains the first not 0 bit of the distance between two nodes
  # """

  defp bucket_index(distance) when distance > 0, do: bucket_index(distance, -1)
  defp bucket_index(0, index), do: index

  defp bucket_index(distance, index),
    do: bucket_index(distance >>> 1, index + 1)

  defp conversion(value) when is_binary(value),
    do: :binary.decode_unsigned(value)

  defp conversion(value), do: value
end
