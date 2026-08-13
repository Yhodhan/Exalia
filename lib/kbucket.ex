defmodule Exalia.KBucket do
  @k 8 

  def insert(bucket, contact) do
    case Enum.find_index(bucket, contact) do
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
