defmodule Eqmi.Server do
  def start_link(dev) do
    GenServer.start_link(__MODULE__, dev, __MODULE__)
  end

  def init(dev) do
    options = [:read, :write, :raw]

    case File.open(dev, options) do
      {:ok, dev} ->
        Eqmi.Reader.start_link(self(), dev)
        {:ok, %{device: dev}}

      {:error, reason} ->
        {:stop, reason}
    end
  end
end
