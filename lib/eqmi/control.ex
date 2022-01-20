defmodule Eqmi.Control do
  use GenStateMachine, callback_mode: :state_functions

  @allocation_msg_id 34
  require Logger

  @moduledoc """
  CTL control point implementation.
  """
  defmodule CTLState do
    @moduledoc false
    # current_tx: current transaction id
    # server_pid: pid of  EqmiServer module
    defstruct device_name: nil,
              current_tx: 0,
              client_pid: nil
  end

  defp via_tuple(dev_name) do
    {:via, Registry, {:eqmi_registry, dev_name}}
  end

  defp base_name(device) do
    base_name = device |> String.trim() |> Path.basename()

    Module.concat(__MODULE__, base_name)
  end

  @doc """
  Start up a CallControl GenStateMachine.
  """
  @spec start_link([term]) :: {:ok, pid} | {:error, term}
  def start_link(device_name) do
    name =
      device_name
      |> base_name()
      |> via_tuple()

    GenStateMachine.start_link(__MODULE__, device_name, name: name)
  end

  @doc """
  allocate client id for a service
  """
  @spec allocate_cid(String.t(), term()) :: {:ok, term()} | {:error, term}
  def allocate_cid(device_name, service) do
    device_name
    |> base_name()
    |> via_tuple()
    |> GenStateMachine.call({:allocate, service}, 12_000)
  end

  @spec release_cid(pid(), term(), term()) :: :ok | {:error, term}
  def release_cid(device_name, service, cid) do
    device_name
    |> base_name()
    |> via_tuple()
    |> GenStateMachine.call({:release, service, cid}, 6000)
  end

  # gen_state_machine callbacks
  def init(dev_name) do
    tx_id = 0
    data = %CTLState{device_name: dev_name, current_tx: tx_id + 1}
    event = {:next_event, :cast, :sync}
    {:ok, :init_ctl, data, event}
  end

  def init_ctl(:cast, :sync, data) do
    qmux_msg = ctl_msg_base(:sync, [], data.current_tx)
    Eqmi.Device.send_raw(data.device_name, qmux_msg)
    {:next_state, :wait4_sync, data}
  end

  def wait4_sync(:info, {:qmux, %{message_type: :response}}, data) do
    {:next_state, :idle, data}
  end

  def wait4_sync(:info, {:qmux, msg}, _data) do
    Logger.warn("Waiting 4 sync indication [#{inspect(msg)}]")
    {:keep_state_and_data, 10_000}
  end

  def wait4_sync({:call, _from}, _msg, _data) do
    {:keep_state_and_data, [:postpone, 10_000]}
  end

  def idle({:call, from}, {:allocate, service}, data) do
    service = Eqmi.service_type_id(service)

    tx_id = data.current_tx
    qmux_msg = ctl_msg_base(:allocate_cid, [{:service, service}], tx_id)

    Eqmi.Device.send_raw(data.device_name, qmux_msg)
    new_data = %{data | client_pid: from, current_tx: tx_id + 1}
    {:next_state, :wait4_cid, new_data, 10_000}
  end

  def idle({:call, from}, {:release, service, cid}, data) do
    service = Eqmi.service_type_id(service)

    tx_id = data.current_tx
    qmux_msg = ctl_msg_base(:release_cid, [{:service, service}, {:cid, cid}], tx_id)

    Eqmi.Device.send_raw(data.device_name, qmux_msg)
    new_data = %{data | client_pid: from, current_tx: tx_id + 1}
    {:next_state, :wait4_release, new_data, 10_000}
  end

  def idle(:info, {:qmux, msg}, _data) do
    IO.inspect(msg, label: "info in idle")
    :keep_state_and_data
  end

  def wait4_cid(:info, {:qmux, %{message_type: :response} = msg}, data) do
    [h | _] = msg.messages
    cid = get_cid(h)

    response =
      if cid != nil do
        {:ok, cid}
      else
        {:error, :cid_not_present}
      end

    GenStateMachine.reply(data.client_pid, response)
    new_data = %{data | client_pid: nil}
    {:next_state, :idle, new_data}
  end

  def wait4_cid(:info, {:qmux, msg}, _data) do
    Logger.warn("Waiting 4 cid indication [#{inspect(msg)}]")
    {:keep_state_and_data, 10_000}
  end

  def wait4_cid({:call, _from}, _msg, _data) do
    {:keep_state_and_data, [:postpone, 10_000]}
  end

  def wait4_release(:info, {:qmux, _msg}, data) do
    GenStateMachine.reply(data.client_pid, :ok)
    new_data = %{data | client_pid: nil}
    {:next_state, :idle, new_data}
  end

  def wait4_release({:call, _from}, _msg, _data) do
    {:keep_state_and_data, [:postpone, 10_000]}
  end

  defp get_cid(%{msg_id: @allocation_msg_id, parameters: params}) do
    params
    |> Enum.find_value(fn x ->
      v = Map.get(x, :allocation_info)
      if v != nil, do: v.cid
    end)
  end

  defp get_cid(_msg) do
    {:error, :not_supported}
  end

  defp ctl_msg_base(msg_type, params, tx_id) do
    msg = Eqmi.CTL.request(msg_type, params)
    payload = Eqmi.CTL.qmux_sdu(:request, tx_id, [msg])
    header = Eqmi.QmuxHeader.new(:control_point, 0, :qmi_ctl, byte_size(payload))
    Eqmi.qmux_message(header, payload)
  end
end
