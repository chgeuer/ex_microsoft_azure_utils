defmodule Microsoft.Azure.ActiveDirectory.DeviceAuthenticator do
  alias Microsoft.Azure.AzureEnvironment
  alias Microsoft.Azure.ActiveDirectory.{RestClient}
  alias Microsoft.Azure.ActiveDirectory.Model.{DeviceCodeResponse, TokenResponse}
  alias __MODULE__.State

  use GenServer

  defmodule State do
    # @derive {Inspect, except: [:device_code]}
    @enforce_keys [:tenant_id, :azure_environment, :resource]
    defstruct [
      :tenant_id,
      :azure_environment,
      :resource,
      :stage,
      :device_code_response,
      :token_response,
      :refresh_timer
    ]
  end

  defmodule DeviceAuthenticatorError do
    defstruct [:correlation_id, :error, :error_codes, :error_description, :timestamp, :trace_id]

    def from_json(str), do: str |> Poison.decode!(keys: :atoms, as: %__MODULE__{})
  end

  #
  # Client section
  #

  def start_azure_management(tenant_id \\ "common", azure_environment \\ :azure_global),
    do:
      %State{
        tenant_id: tenant_id,
        azure_environment: azure_environment,
        resource:
          "https://#{AzureEnvironment.get_val(azure_environment, :resource_manager_endpoint)}/"
      }
      |> start()

  def start(state = %State{}, opts \\ []) do
    GenServer.start_link(__MODULE__, state, opts)
  end

  def get_device_code(pid, timeout \\ :infinity) do
    pid |> GenServer.call(:get_device_code, timeout)
  end

  def get_token(pid, timeout \\ :infinity) do
    pid |> GenServer.call(:get_token, timeout)
  end

  def force_refresh(pid) do
    pid |> GenServer.cast(:refresh_token)
  end

  def get_stage(pid) do
    pid |> GenServer.call(:get_stage)
  end

  #
  # Server section
  #

  def init(state = %State{}) do
    {:ok, state |> Map.put(:stage, :initialized)}
  end

  def handle_call(:get_stage, _, state = %State{stage: stage}), do: {:reply, stage, state}

  def handle_call(:get_device_code, _, state = %State{stage: :initialized}) do
    #
    # Make the initial call to trigger device authentication
    #
    case RestClient.get_device_code(state) do
      {:ok, device_code_response = %DeviceCodeResponse{}} ->
        new_state =
          state
          |> Map.put(:stage, :polling)
          |> Map.put(:device_code_response, device_code_response)

        self()
        |> Process.send_after(:poll_for_token, 1000 * new_state.device_code_response.interval)

        {:reply, {:ok, device_code_response}, new_state}

      {:error, body} ->
        {:reply, {:error, body}, state}
    end
  end

  def handle_call(
        :get_device_code,
        _sender,
        state = %State{stage: :polling, device_code_response: device_code_response}
      ) do
    #
    # As long as we're polling for the user signin, return the old device code's response
    #
    {:reply, {:ok, device_code_response}, state}
  end

  def handle_call(:get_device_code, _, state = %State{stage: :refreshing}),
    do: {:reply, {:error, :token_already_issued}, state}

  def handle_call(:get_token, _, state = %State{stage: :initialized}),
    do: {:reply, {:error, :must_call_get_device_code}, state}

  def handle_call(:get_token, _, state = %State{stage: :polling}),
    do: {:reply, {:error, :waiting_for_user_authentication}, state}

  def handle_call(
        :get_token,
        _,
        state = %State{stage: :refreshing, token_response: token_response}
      ),
      do: {:reply, {:ok, token_response}, state}

  def handle_info(:poll_for_token, state = %State{}), do: {:noreply, state |> fetch_token_impl()}

  def handle_info(:refresh_token, state = %State{stage: :refreshing}),
    do: {:noreply, state |> refresh_token_impl()}

  def handle_info(:refresh_token, state = %State{stage: _}), do: {:noreply, state}

  def handle_cast(:refresh_token, state = %State{stage: :refreshing}),
    do: {:noreply, state |> refresh_token_impl()}

  def handle_cast(:refresh_token, state = %State{stage: _}), do: {:noreply, state}

  defp fetch_token_impl(state = %State{}) do
    case RestClient.fetch_device_code_token(state) do
      {:ok, token_response = %TokenResponse{}} ->
        # token_response = token_response |> Map.put(:expires_in, 5)

        new_state =
          state
          |> Map.put(:stage, :refreshing)
          |> Map.put(:token_response, token_response)
          |> Map.delete(:device_code_response)

        timer = self() |> Process.send_after(:refresh_token, 1000 * token_response.expires_in)

        new_state
        |> Map.put(:refresh_timer, timer)

      {:error, _error_doc = %DeviceAuthenticatorError{}} ->
        self() |> Process.send_after(:poll_for_token, 1000 * state.device_code_response.interval)

        state
    end
  end

  defp refresh_token_impl(state = %State{}) do
    case state do
      %State{refresh_timer: refresh_timer} ->
        refresh_timer |> Process.cancel_timer()

      _ ->
        nil
    end

    case RestClient.refresh_token(state) do
      {:ok, token_response = %TokenResponse{}} ->
        new_state =
          state
          |> Map.put(:token_response, token_response)
          |> Map.put(:stage, :refreshing)

        timer = self() |> Process.send_after(:refresh_token, 1000 * token_response.expires_in)

        new_state
        |> Map.put(:refresh_timer, timer)
    end
  end
end
