defmodule Exalia.RoutingTable do
  import Bitwise

  alias Exalia.KBucket
  alias Exalia.Candidate
  alias Exalia.Utils

  @alpha 8

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

    case KBucket.insert(bucket, candidate) do
      {:full, _bucket, _candidate} ->
        table

      new_bucket ->
        put_bucket(table, index, new_bucket)
    end
  end

  def fetch_bucket(table, index) do
    table
    |> Map.get(:kbuckets)
    |> Map.get(index, [])
  end

  def put_bucket(%__MODULE__{} = table, index, bucket) do
    %__MODULE__{table | kbuckets: Map.put(table.kbuckets, index, bucket)}
  end

  def fetch_candidate(table, id) do
    distance = Utils.xor_distance(table.id, id)
    index = bucket_index(distance)
    bucket = fetch_bucket(table, index)

    Enum.find(bucket, fn c -> c.id == id end)
  end

  def has_candidate?(table, id),
    do: not is_nil(fetch_candidate(table, id))

  def get_closest_candidates(table, id) do
    table.kbuckets
    |> Map.values()
    |> List.flatten()
    |> Enum.sort_by(fn c -> Utils.xor_distance(c.id, id) end)
    |> Enum.take(@alpha)
  end

  def get_contacts(table) do
    table.kbuckets
    |> Map.values()
    |> List.flatten()
  end

  # ------------------
  # Private functions
  # ------------------
  defp get_bucket(table, id) do
    distance = Utils.xor_distance(table.id, id)
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
end
