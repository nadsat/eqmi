defmodule Eqmi.Reader do
  use Task

  def start_link(pid, dev) do
    Task.start_link(__MODULE__, :run, [pid, dev])
  end

  def run(pid, dev) do
    options = [:read, :raw]

    {:ok, fd} = File.open(dev, options)
    run_priv(pid, fd)
  end

  defp run_priv(pid, dev) do
    msg = IO.binread(dev, 3)
    process_message(msg, pid, dev)
  end

  defp process_message({:error, reason}, pid, _) do
    send(pid, {:error, reason})
  end

  defp process_message(:eof, pid, _) do
    send(pid, {:error, :eof})
  end

  defp process_message(qmux, pid, dev) do
    <<_version, l::binary>> = qmux
    len = :binary.decode_unsigned(l, :little)
    msg = IO.binread(dev, len - 2)
    <<h::binary-size(3), rest::binary>> = msg
    header = Eqmi.QmuxHeader.parse(h)
    send(pid, {:qmux, header, rest})
    run_priv(dev, pid)
  end
end
