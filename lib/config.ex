defmodule Exalia.Config do
  def bootstrap_nodes(),
    do: Application.get_env(:exalia, :bootstrap_nodes)
end
