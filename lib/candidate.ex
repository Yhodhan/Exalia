defmodule Exalia.Candidate do
  defstruct [
    :id,
    :ip,
    :port
  ]

  def new(id, ip, port),
    do: %__MODULE__{id: id, ip: ip, port: port}
end
