defmodule Exalia.KBucket do
  alias Exalia.Candidate
  @k 8

  defstruct [
    :nodes,
    :last_update
  ]

  def new() do
    %__MODULE__{
      nodes: [],
      last_update: System.monotonic_time(:millisecond)
    }
  end

  @spec insert(any(), any()) :: none()
  def insert(bucket, %Candidate{} = contact) do
    case Enum.find_index(bucket.nodes, &(&1.id == contact.id)) do
      nil ->
        insert_new(bucket, contact)

      index ->
        %__MODULE__{
          nodes:
            bucket.nodes
            |> List.delete_at(index)
            |> Kernel.++([contact]),
          last_update: System.monotonic_time(:millisecond)
        }
    end
  end

  def insert_new(bucket, contact) when length(bucket.nodes) < @k do
    %__MODULE__{
      nodes: bucket.nodes ++ [contact],
      last_update: System.monotonic_time(:millisecond)
    }
  end

  def insert_new(bucket, contact) do
    {:full, bucket, contact}
  end
end
