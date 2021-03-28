defmodule Eqmi.Control do
  use GenStateMachine, callback_mode: :state_functions

  @allocation_msg_id 34

  @moduledoc """
  CTL control point implementation.
  """
  defmodule CTLState do
    @moduledoc false
    # current_tx: current transaction id
    # server_pid: pid of  EqmiServer module
    defstruct server_ref: nil,
              current_tx: 0,
              client_pid: nil
  end

  @doc """
  Start up a CallControl GenStateMachine.
  """
  @spec start_link([term]) :: {:ok, pid} | {:error, term}
  def start_link(server_ref, opts \\ []) do
    GenStateMachine.start_link(__MODULE__, server_ref, opts)
  end

  @doc """
  allocate client id for a service
  """
  @spec allocate_cid(pid(), term()) :: :ok | {:error, term}
  def allocate_cid(pid, service) do
    GenStateMachine.call(pid, {:allocate, service}, 6000)
  end

  # gen_state_machine callbacks
  def init(ref) do
    data = %CTLState{server_ref: ref, current_tx: 1}
    {:ok, :idle, data}
  end

  def idle({:call, from}, {:allocate, service}, data) do
    service = Eqmi.service_type_id(service)
    msg = Eqmi.CTL.request(:allocate_cid, [{:service, service}])
    tx_id = data.current_tx
    payload = Eqmi.CTL.qmux_sdu(:request, tx_id, [msg])
    header = Eqmi.QmuxHeader.new(:control_point, 0, :qmi_ctl, byte_size(payload))
    qmux_msg = Eqmi.qmux_message(header, payload)

    Eqmi.Server.send_raw(data.server_ref, qmux_msg)
    new_data = %{data | client_pid: from, current_tx: tx_id + 1}
    {:next_state, :wait4_response, new_data, 10_000}
  end

  def wait4_response(:info, {:qmux, msg}, data) do
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

  def wait4_response({:call, _from}, {:allocate, _service}, _data) do
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
end
