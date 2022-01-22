defmodule Eqmi.Application do
  @moduledoc false
  use Application

  def start(_type, _arg) do
    children = [
      {Registry, keys: :unique, name: :eqmi_registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Eqmi.DynamicSupervisor},
      {Eqmi, []}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
