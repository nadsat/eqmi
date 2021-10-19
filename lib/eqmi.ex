defmodule Eqmi do
  use GenServer

  @moduledoc """
  Documentation for `Eqmi`.
  """
  @service_types %{
    0 => :qmi_ctl,
    1 => :qmi_wds,
    2 => :qmi_dms,
    3 => :qmi_nas,
    4 => :qmi_qos,
    5 => :qmi_wms,
    6 => :qmi_pds,
    9 => :qmi_voice,
    10 => :qmi_cat,
    11 => :qmi_uim,
    12 => :qmi_pbm,
    14 => :qmi_cat,
    16 => :qmi_loc,
    17 => :qmi_sar,
    20 => :qmi_wda,
    226 => :qmi_oma,
    231 => :qmi_gms,
    232 => :qmi_gas
  }
  @message_types %{0 => :request, 2 => :response, 4 => :indication}

  def message_type_id(msg_name) do
    @message_types
    |> get_id(msg_name)
  end

  def service_type_id(msg_name) do
    @service_types
    |> get_id(msg_name)
  end

  defp get_id(types, name) do
    types
    |> Enum.find(fn {_key, val} -> val == name end)
    |> elem(0)
  end

  # to be deleted
  def qmux_message(header, payload) do
    if_type = <<1::little-unsigned-integer-size(8)>>

    [if_type, header, payload]
    |> :erlang.list_to_binary()
  end

  defmodule ClientState do
    @moduledoc false
    defstruct type: nil,
              current_tx: 0,
              id: 0,
              pid: nil
  end

  @spec device(String.t()) :: {:ok, reference()} | {:error, term()}
  def device(path) do
    GenServer.call(__MODULE__, {:get_device, path})
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def stop(pid, reason \\ :shutdown, timeout \\ :infinity) do
    GenServer.stop(pid, reason, timeout)
  end

  def client(pid, type) do
    {:ok, ctl} = GenServer.call(pid, :get_ctl)

    case Eqmi.Control.allocate_cid(ctl, type) do
      {:ok, cid} ->
        GenServer.call(pid, {:new_client, type, cid})

      _ ->
        {:error, "allocating control point"}
    end
  end

  def release_client(pid, ref) do
    with {:ok, ctl} <- GenServer.call(pid, :get_ctl),
         {:ok, client} <- GenServer.call(pid, {:get_client, ref}) do
      Eqmi.Control.release_cid(ctl, client.type, client.id)
      GenServer.call(pid, {:release, ref})
    else
      err -> err
    end
  end

  def qmux_message(pid, client_ref, ctrl_flag, service, messages) do
    GenServer.call(pid, {:qmux_message, client_ref, ctrl_flag, service, messages})
  end

  def send_message(pid, ref, msg) do
    GenServer.call(pid, {:send_msg, ref, msg})
  end

  def send_raw(pid, msg) do
    GenServer.call(pid, {:send_raw, msg})
  end

  def init(_) do
    {:ok, %{devices: %{}, refs: %{}}}
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

  def handle_call(:get_ctl, _from, s) do
    {:reply, {:ok, s.ctl}, s}
  end

  def handle_call({:get_device, device_path}, _from, state) do
    path = device_path |> String.trim()

    case Map.get(state.devices, path) do
      nil ->
        spec = {Eqmi.Device, device: path}
        DynamicSupervisor.start_child(Eqmi.DynamicSupervisor, spec)
        ref = make_ref()
        r = Map.put(state.refs, ref, path)
        d = Map.put(state.devices, path, ref)
        new_state = %{devices: d, refs: r}
        {:reply, {:ok, nil}, new_state}

      dev ->
        {:reply, {:ok, dev}, state}
    end
  end

  def handle_call({:new_client, type, cid}, from, %{clients: clients, control_points: ctrls} = s) do
    {pid, _} = from
    client_state = %ClientState{type: type, id: cid, current_tx: 0, pid: pid}
    ref = :erlang.make_ref()

    clients_ids =
      clients
      |> Map.get(type, %{})
      |> Map.put(cid, pid)

    new_clients = Map.put(clients, type, clients_ids)
    new_ctrls = Map.put(ctrls, ref, client_state)
    state = %{s | clients: new_clients, control_points: new_ctrls}
    {:reply, ref, state}
  end

  def handle_call({:release, ref}, _from, %{clients: clients, control_points: controls} = s) do
    control_point = Map.get(controls, ref)
    client_list = Map.get(clients, control_point.type)
    new_controls = Map.delete(controls, ref)
    new_client_list = Map.delete(client_list, control_point.id)
    new_clients = Map.put(clients, control_point.type, new_client_list)
    new_state = %{s | clients: new_clients, control_points: new_controls}
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

  def handle_info(msg, s) do
    IO.inspect(msg, label: "info in server")
    {:noreply, s}
  end

  def terminate(_reason, s) do
    File.close(s.device)
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
