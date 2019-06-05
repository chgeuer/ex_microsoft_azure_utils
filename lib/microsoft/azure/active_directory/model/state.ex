defmodule Microsoft.Azure.ActiveDirectory.DeviceAuthenticator.Model.State do
  # @derive {Inspect, except: [:device_code]}
  # @enforce_keys [:tenant_id, :azure_environment, :resource]

  defstruct [
    :tenant_id,
    :azure_environment,
    :resource,
    :stage,
    :device_code_response,
    :token_response,
    :refresh_timer,
    :supervisor_pid,
    :agent_pid
  ]
end
