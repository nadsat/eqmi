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

  def client(dev_ref, type) do
    with {:ok, path} <- GenServer.call(__MODULE__, {:get_path, dev_ref}) do
      Eqmi.Device.client(path, type)
    else
      err -> err
    end
  end

  def release_client(dev_ref, client_ref) do
    with {:ok, path} <- GenServer.call(__MODULE__, {:get_path, dev_ref}) do
      Eqmi.Device.release_client(path, client_ref)
    else
      err -> err
    end
  end

  def send_message(dev_ref, client_ref, msg) do
    with {:ok, path} <- GenServer.call(__MODULE__, {:get_path, dev_ref}) do
      Eqmi.Device.send_message(path, client_ref, msg)
    else
      err -> err
    end
  end

  def send_raw(dev_ref, msg) do
    with {:ok, path} <- GenServer.call(__MODULE__, {:get_path, dev_ref}) do
      Eqmi.Device.send_raw(path, msg)
    else
      err -> err
    end
  end

  def init(_) do
    {:ok, %{devices: %{}, refs: %{}}}
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
        {:reply, {:ok, ref}, new_state}

      dev ->
        {:reply, {:ok, dev}, state}
    end
  end

  def handle_call({:get_path, ref}, _from, state) do
    case Map.get(state.ref, ref) do
      nil ->
        {:reply, {:error, :device_not_found}, state}

      path ->
        {:reply, {:ok, path}, state}
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

  def handle_call({:get_client, ref}, _from, %{control_points: controls} = s) do
    client = Map.get(controls, ref)

    if client != nil do
      {:reply, {:ok, client}, s}
    else
      {:reply, {:error, "control_point not found"}, s}
    end
  end

  def handle_info(msg, s) do
    IO.inspect(msg, label: "info in server")
    {:noreply, s}
  end

  def terminate(reason, _s) do
    IO.inspect(reason, label: "terminate")
  end
end
