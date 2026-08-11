defmodule KBucket do
  @buckets_num 20

  defstruct [
    :candidates
  ]

  def new() do
    %__MODULE__{
      candidates: []
    }
  end

  def insert(bucket, contact) do
  end
end
