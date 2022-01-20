defmodule Eqmi.Device do
  use GenServer
  alias Eqmi.Types

  @ctl_id 0

  defmodule ClientState do
    @moduledoc false
    defstruct type: nil,
              current_tx: 0,
              id: 0,
              pid: nil
  end

  def start_link(args) do
    device = Keyword.fetch!(args, :device)
    name = device |> base_name() |> via_tuple()
    GenServer.start_link(__MODULE__, args, name: name)
  end

  defp via_tuple(dev_name) do
    {:via, Registry, {:eqmi_registry, dev_name}}
  end

  defp base_name(device) do
    base_name = device |> String.trim() |> Path.basename()

    Module.concat(__MODULE__, base_name)
  end

  def stop(dev_name, reason \\ :shutdown, timeout \\ :infinity) do
    dev_name
    |> base_name()
    |> via_tuple()
    |> GenServer.stop(reason, timeout)
  end

  def client(dev_name, type) do
    case Eqmi.Control.allocate_cid(dev_name, type) do
      {:ok, cid} ->
        dev_name
        |> base_name()
        |> via_tuple()
        |> GenServer.call({:new_client, type, cid})

      _ ->
        {:error, "allocating control point"}
    end
  end

  def release_client(dev_name, ref) do
    name =
      dev_name
      |> base_name()
      |> via_tuple()

    with {:ok, client} <- GenServer.call(name, {:get_client, ref}) do
      Eqmi.Control.release_cid(dev_name, client.type, client.id)
      GenServer.call(name, {:release, ref})
    else
      err -> err
    end
  end

  def qmux_message(dev_name, client_ref, ctrl_flag, service, messages) do
    dev_name
    |> base_name()
    |> via_tuple()
    |> GenServer.call({:qmux_message, client_ref, ctrl_flag, service, messages})
  end

  def send_message(dev_name, ref, msg) do
    dev_name
    |> base_name()
    |> via_tuple()
    |> GenServer.call({:send_msg, ref, msg})
  end

  def send_raw(dev_name, msg) do
    dev_name
    |> base_name()
    |> via_tuple()
    |> GenServer.call({:send_raw, msg})
  end

  def init(args) do
    device = Keyword.fetch!(args, :device)
    options = [:write, :raw]

    case File.open(device, options) do
      {:ok, dev} ->
        {:ok, reader} = Eqmi.Reader.start_link(self(), device)

        {:ok, ctl} =
          device
          |> Eqmi.Control.start_link()

        {:ok,
         %{
           reader: reader,
           device: dev,
           control_points: %{},
           clients: %{:qmi_ctl => %{@ctl_id => ctl}},
           ctl: ctl
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp qmux_sdu(msg_type, transaction_id, messages) do
    msg_id = Types.message_id(msg_type)

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

  def handle_call(:get_ctl, _from, s) do
    {:reply, {:ok, s.ctl}, s}
  end

  def handle_call({:new_client, type, cid}, from, %{clients: clients, control_points: ctrls} = s) do
    {pid, _} = from
    client_state = %ClientState{type: type, id: cid, current_tx: 0, pid: pid}
    ref = Process.monitor(pid)

    clients_ids =
      clients
      |> Map.get(type, %{})
      |> Map.put(cid, pid)

    new_clients = Map.put(clients, type, clients_ids)
    new_ctrls = Map.put(ctrls, ref, client_state)
    state = %{s | clients: new_clients, control_points: new_ctrls}
    {:reply, ref, state}
  end

  def handle_call({:release, ref}, _from, s) do
    new_state = release_base(ref, s)
    {:reply, :ok, new_state}
  end

  def handle_call({:get_client, ref}, _from, %{control_points: controls} = s) do
    client = Map.get(controls, ref)

    if client != nil do
      {:reply, {:ok, client}, s}
    else
      {:reply, {:error, "control_point not found"}, s}
    end
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

  def handle_call(
        {:send_msg, ref, msg},
        _from,
        %{device: dev, control_points: controls} = s
      ) do
    client = Map.get(controls, ref)

    if client != nil do
      tx_id = client.current_tx + 1
      payload = qmux_sdu(client.type, :request, tx_id, msg)
      header = Eqmi.QmuxHeader.new(:control_point, client.id, client.type, byte_size(payload))
      qmux_msg = Eqmi.qmux_message(header, payload)
      new_client = %ClientState{client | current_tx: tx_id}
      new_ctrls = Map.put(controls, ref, new_client)
      res = IO.binwrite(dev, qmux_msg)

      {:reply, res, %{s | control_points: new_ctrls}}
    else
      {:reply, {:error, "control_point not found"}, s}
    end
  end

  def handle_call({:send_raw, msg}, _from, %{device: dev} = s) do
    res = IO.binwrite(dev, msg)
    {:reply, res, s}
  end

  def handle_info({:qmux, header, messages}, %{clients: clients} = s) do
    msg = process_service(header, messages)
    client = find_client(clients, header.service_type, header.client_id)

    if client != nil do
      send(client, {:qmux, msg})
    end

    {:noreply, s}
  end

  def handle_info({:DOWN, ref, :process, _object, _reason}, state) do
    new_state = release_base(ref, state)
    {:noreply, new_state}
  end

  def handle_info(msg, s) do
    IO.inspect(msg, label: "info in server")
    {:noreply, s}
  end

  def terminate(_reason, s) do
    File.close(s.device)
  end

  defp release_base(ref, %{clients: clients, control_points: controls} = s) do
    control_point = Map.get(controls, ref)
    client_list = Map.get(clients, control_point.type)
    new_controls = Map.delete(controls, ref)
    new_client_list = Map.delete(client_list, control_point.id)
    new_clients = Map.put(clients, control_point.type, new_client_list)
    %{s | clients: new_clients, control_points: new_controls}
  end

  defp find_client(clients, service_type, client_id) do
    clients
    |> Map.get(service_type, %{})
    |> Map.get(client_id)
  end

  defp process_service(%{service_type: :qmi_ctl} = payload, messages) do
    Eqmi.CTL.process_qmux_sdu(messages, payload)
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

  defp process_service(%{service_type: :qmi_uim} = payload, messages) do
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

  defp qmux_sdu(:qmi_ctl, msg_type, tx_id, messages) do
    Eqmi.CTL.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_wds, msg_type, tx_id, messages) do
    Eqmi.WDS.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_dms, msg_type, tx_id, messages) do
    Eqmi.DMS.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_nas, msg_type, tx_id, messages) do
    Eqmi.NAS.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_qos, msg_type, tx_id, messages) do
    Eqmi.QOS.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_wms, msg_type, tx_id, messages) do
    Eqmi.WMS.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_pds, msg_type, tx_id, messages) do
    Eqmi.PDS.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_voice, msg_type, tx_id, messages) do
    Eqmi.VOICE.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_pbm, msg_type, tx_id, messages) do
    Eqmi.PBM.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_uim, msg_type, tx_id, messages) do
    Eqmi.UIM.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_loc, msg_type, tx_id, messages) do
    Eqmi.LOC.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_sar, msg_type, tx_id, messages) do
    Eqmi.SAR.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_wda, msg_type, tx_id, messages) do
    Eqmi.WDA.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_oma, msg_type, tx_id, messages) do
    Eqmi.OMA.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_gms, msg_type, tx_id, messages) do
    Eqmi.GMS.qmux_sdu(msg_type, tx_id, messages)
  end

  defp qmux_sdu(:qmi_gas, msg_type, tx_id, messages) do
    Eqmi.GAS.qmux_sdu(msg_type, tx_id, messages)
  end
end
