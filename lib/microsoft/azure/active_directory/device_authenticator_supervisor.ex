defmodule Microsoft.Azure.ActiveDirectory.DeviceAuthenticatorSupervisor do
  alias Microsoft.Azure.AzureEnvironment
  alias Microsoft.Azure.ActiveDirectory.DeviceAuthenticator
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

  def start_link(state) do
    Supervisor.start_link(__MODULE__, state)
  end

  @impl true
  def init(initial_state = %State{}) do
    pid = self()

    agent_state =
      initial_state
      |> Map.put(:supervisor_pid, pid)

    children = [
      # Give full config into agent ...
      worker(Agent, [fn -> agent_state end]),
      # ... and only the supervisor's PID into the worker
      worker(DeviceAuthenticator, [%State{supervisor_pid: pid}])
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp find_child(pid, child_type)
       when is_pid(pid) and child_type in [Agent, DeviceAuthenticator],
       do:
         pid
         |> Supervisor.which_children()
         |> Enum.find(fn {type, _, :worker, _} -> type == child_type end)

  defp get_child_pid(pid, child_type)
       when is_pid(pid) and child_type in [Agent, DeviceAuthenticator] do
    with {^child_type, child_pid, :worker, _} <- find_child(pid, child_type) do
      case child_pid |> Process.alive?() do
        true -> child_pid
        false -> get_child_pid(pid, child_type)
      end
    end
  end

  def get_state_pid(supervisor_pid), do: supervisor_pid |> get_child_pid(Agent)
  def get_worker_pid(supervisor_pid), do: supervisor_pid |> get_child_pid(DeviceAuthenticator)

  def get_agent_state(%{state_pid: state_pid}),
    do:
      state_pid
      |> Agent.get(& &1)

  def get_agent_state(%{supervisor_pid: supervisor_pid}),
    do:
      supervisor_pid
      |> get_state_pid()
      |> Agent.get(& &1)

  def get_agent_state(supervisor_pid) when is_pid(supervisor_pid),
    do: get_agent_state(%{supervisor_pid: supervisor_pid})

  def set_agent_state(%{state_pid: state_pid} = worker_state) do
    state_pid
    |> Agent.update(fn _ -> worker_state end)

    worker_state
  end
end
