defmodule Microsoft.Azure.ActiveDirectory.DeviceAuthenticatorSupervisor do
  alias Microsoft.Azure.AzureEnvironment
  alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticator, as: Worker
  alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.State

  use Supervisor

  def start_azure_management(tenant_id \\ "common", azure_environment \\ :azure_global) do
    %State{
      tenant_id: tenant_id,
      azure_environment: azure_environment,
      resource:
        "https://#{AzureEnvironment.get_val(azure_environment, :resource_manager_endpoint)}/"
    }
    |> start_link()
  end

  def start_link(%State{} = state) do
    Supervisor.start_link(__MODULE__, state)
  end

  @impl true
  def init(%State{} = initial_state) do
    supervisor_pid = self()

    agent_state =
      initial_state
      |> Map.put(:supervisor_pid, supervisor_pid)

    # Give full config into agent ...
    # ... and only the supervisor's PID into the worker
    children = [
      worker(Agent, [fn -> agent_state end]),
      worker(Worker, [%State{supervisor_pid: supervisor_pid}])
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp find_child(supervisor_pid, child_type)
       when is_pid(supervisor_pid) and child_type in [Agent, Worker],
       do:
         supervisor_pid
         |> Supervisor.which_children()
         |> Enum.find(fn {type, _, :worker, _} -> type == child_type end)

  def get_child_pid(supervisor_pid, child_type)
      when is_pid(supervisor_pid) and child_type in [Agent, Worker] do
    with {^child_type, child_pid, :worker, _} <- find_child(supervisor_pid, child_type) do
      case child_pid |> Process.alive?() do
        true -> child_pid
        false -> get_child_pid(supervisor_pid, child_type)
      end
    end
  end
end
