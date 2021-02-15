defmodule Eqmi.Server do
  use GenServer

  defmodule ClientState do
    @moduledoc false
    defstruct type: :control_point,
              current_tx: 0,
              id: 0
  end

  def start_link(dev) do
    GenServer.start_link(__MODULE__, dev, __MODULE__)
  end

  def client(pid, type) do
    GenServer.call(pid, {:new_client, type})
  end

  def qmux_message(pid, client_ref, ctrl_flag, service, messages) do
    GenServer.call(pid, {:qmux_message, client_ref, ctrl_flag, service, messages})
  end

  def send_message(pid, msg) do
    GenServer.call(pid, {:send, msg})
  end

  def init(dev) do
    options = [:read, :write, :raw]

    case File.open(dev, options) do
      {:ok, dev} ->
        Eqmi.Reader.start_link(self(), dev)
        {:ok, %{device: dev, clients: %{}}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp new_id(clients) do
    clients
    |> Enum.map(fn {_, v} -> v.id end)
    |> Enum.sort()
    |> Enum.reduce_while(0, fn x, acc -> if acc == x, do: {:cont, acc + 1}, else: {:halt, acc} end)
  end

  defp new_client(type, clients) do
    id = new_id(clients)
    %ClientState{type: type, id: id, current_tx: 0}
  end

  defp qmux_sdu(msg_type, transaction_id, messages) do
    msg_id = Eqmi.message_type_id(msg_type)

    ctrl_flag = <<msg_id::unsigned-integer-size(8)>>
    tx_id = <<transaction_id::unsigned-integer-size(8)>>

    [ctrl_flag, tx_id, messages]
    |> :erlang.list_to_binary()
  end

  defp gen_tx_id(:request, id) do
    id + 1
  end

  defp gen_tx_id(_, id) do
    id
  end

  def handle_call({:new_client, type}, _from, %{clients: clients} = s) do
    client = new_client(type, clients)
    id = :erlang.make_ref()
    new_clients = Map.put(clients, id, client)
    state = %{s | clients: new_clients}
    {:reply, id, state}
  end

  def handle_call(
        {:qmux_message, client_ref, ctrl_flag, service, messages},
        _from,
        %{clients: clients} = s
      ) do
    result = Map.get(clients, client_ref)

    case result do
      {:ok, client} ->
        tx_id = gen_tx_id(ctrl_flag, client.current_tx)
        payload = qmux_sdu(ctrl_flag, tx_id, messages)
        header = Eqmi.QmuxHeader.new(client.type, client.id, service, byte_size(payload))
        if_type = <<1::little-unsigned-integer-size(8)>>

        msg =
          [if_type, header, payload]
          |> :erlang.list_to_binary()

        updated_client = %{client | current_tx: tx_id}
        new_clients = Map.put(clients, client_ref, updated_client)
        state = %{s | clients: new_clients}
        {:reply, msg, state}

      _ ->
        {:reply, :error, s}
    end
  end

  def handle_call({:sned, msg}, _from, %{dev: dev} = s) do
    res = IO.binwrite(dev, msg)
    {:reply, res, s}
  end

  def handle_info({:qmux, header, messages}, state) do
    process_service(header, messages)
    {:noreply, state}
  end

  defp process_service(%{service_type: :qmi_wds} = payload, messages) do
    Eqmi.WDS.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_dms} = payload, messages) do
    Eqmi.DMS.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_nas} = payload, messages) do
    Eqmi.NAS.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_qos} = payload, messages) do
    Eqmi.QOS.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_wms} = payload, messages) do
    Eqmi.WMS.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_pds} = payload, messages) do
    Eqmi.PDS.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_voice} = payload, messages) do
    Eqmi.VOICE.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_pbm} = payload, messages) do
    Eqmi.PBM.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_UIM} = payload, messages) do
    Eqmi.UIM.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_loc} = payload, messages) do
    Eqmi.LOC.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_sar} = payload, messages) do
    Eqmi.SAR.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_wda} = payload, messages) do
    Eqmi.WDA.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_oma} = payload, messages) do
    Eqmi.OMA.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_gms} = payload, messages) do
    Eqmi.GMS.process_qmux_sdu(messages, payload)
  end

  defp process_service(%{service_type: :qmi_gas} = payload, messages) do
    Eqmi.GAS.process_qmux_sdu(messages, payload)
  end
end
