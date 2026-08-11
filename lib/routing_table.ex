defmodule RoutingTable do
  defstruct [
    :kbuckets
  ]

  def new() do
    %__MODULE__{
      kbuckets: %{}
    }
  end

  def fetch_bucket(table, index) do
    table
    |> Map.get(:kbuckets)
    |> Map.get(index)
  end
end
