defmodule Exalia.KBucket do
  alias Exalia.Candidate
  @k 8

  @spec insert(any(), any()) :: none()
  def insert(bucket, %Candidate{} = contact) do
    case Enum.find_index(bucket, &(&1.id == contact.id)) do
      nil ->
        insert_new(bucket, contact)

      index ->
        bucket
        |> List.delete_at(index)
        |> Kernel.++([contact])
    end
  end

  def insert_new(bucket, contact) when length(bucket) < @k do
    bucket ++ [contact]
  end

  def insert_new(bucket, contact) do
    {:full, bucket, contact}
  end
end
