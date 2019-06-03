defmodule Microsoft.Azure.ActiveDirectory.DeviceAuthenticator do
  alias Microsoft.Azure.AzureEnvironment
  alias Microsoft.Azure.ActiveDirectory.{RestClient}
  alias __MODULE__.Model.{DeviceCodeResponse, TokenResponse, DeviceAuthenticatorState, DeviceAuthenticatorError}

  use GenServer

  #
  # Client section
  #
  def start_azure_management(tenant_id \\ "common", azure_environment \\ :azure_global),
    do:
      %DeviceAuthenticatorState{
        tenant_id: tenant_id,
        azure_environment: azure_environment,
        resource:
          "https://#{AzureEnvironment.get_val(azure_environment, :resource_manager_endpoint)}/"
      }
      |> start()

  def start(state = %DeviceAuthenticatorState{}, opts \\ []) do
    GenServer.start_link(__MODULE__, state, opts)
  end

  @spec get_device_code(pid(), integer()) :: struct()
  def get_device_code(pid, timeout \\ :infinity) do
    pid |> GenServer.call(:get_device_code, timeout)
  end

  @spec get_token(pid(), integer()) :: struct()
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

  @impl GenServer
  def init(state = %DeviceAuthenticatorState{}) do
    {:ok, state |> Map.put(:stage, :initialized)}
  end

  @impl GenServer
  def handle_call(:get_stage, _, state = %DeviceAuthenticatorState{stage: stage}), do: {:reply, stage, state}

  def handle_call(:get_device_code, _, state = %DeviceAuthenticatorState{stage: :initialized}) do
    #
    # Make the initial call to trigger device authentication

    case RestClient.get_device_code(state) do
      {:ok, device_code_response = %DeviceCodeResponse{expires_in: expires_in}} ->
        # remember when the code authN code expires
        expires_on = Timex.now() |> Timex.add(Timex.Duration.from_seconds(expires_in))

        new_state =
          state
          |> Map.put(:stage, :polling)
          |> Map.put(
            :device_code_response,
            device_code_response |> Map.put(:expires_on, expires_on)
          )

        self()
        |> Process.send_after(:poll_for_token, 1000 * new_state.device_code_response.interval)

        {:reply, {:ok, new_state.device_code_response}, new_state}

      {:error, body} ->
        {:reply, {:error, body}, state}
    end
  end

  def handle_call(
        :get_device_code,
        _sender,
        state = %DeviceAuthenticatorState{
          stage: :polling,
          device_code_response: device_code_response = %{expires_on: expires_on}
        }
      )
      when expires_on != nil do
    #
    # As long as we're polling for the user signin, return the old device code's response
    #
    seconds_left = device_code_response |> DeviceCodeResponse.expires_in()

    cond do
      seconds_left > 0 -> {:reply, {:ok, device_code_response}, state}
      # Process should exit if the current device code is expired
      true -> {:stop, :normal, {:error, :cannot_use_expired_code_request}, state}
    end
  end

  def handle_call(:get_device_code, _, state = %DeviceAuthenticatorState{stage: :refreshing}),
    do: {:reply, {:error, :token_already_issued}, state}

  def handle_call(:get_token, _, state = %DeviceAuthenticatorState{stage: :initialized}),
    do: {:reply, {:error, :must_call_get_device_code}, state}

  def handle_call(:get_token, _, state = %DeviceAuthenticatorState{stage: :polling}),
    do: {:reply, {:error, :waiting_for_user_authentication}, state}

  def handle_call(
        :get_token,
        _,
        state = %DeviceAuthenticatorState{stage: :refreshing, token_response: token_response}
      ),
      do: {:reply, {:ok, token_response}, state}

  @impl GenServer
  def handle_info(:poll_for_token, state = %DeviceAuthenticatorState{device_code_response: device_code_response}) do
    seconds_left = device_code_response |> DeviceCodeResponse.expires_in()

    cond do
      seconds_left > 0 -> {:noreply, state |> fetch_token_impl()}
      # Process should exit if the current device code is expired
      true -> {:stop, :normal, state}
    end
  end

  def handle_info(:refresh_token, state = %DeviceAuthenticatorState{stage: :refreshing}),
    do: {:noreply, state |> refresh_token_impl()}

  def handle_info(:refresh_token, state = %DeviceAuthenticatorState{stage: _}), do: {:noreply, state}

  @impl GenServer
  def handle_cast(:refresh_token, state = %DeviceAuthenticatorState{stage: :refreshing}),
    do: {:noreply, state |> refresh_token_impl()}

  def handle_cast(:refresh_token, state = %DeviceAuthenticatorState{stage: _}), do: {:noreply, state}

  defp fetch_token_impl(state = %DeviceAuthenticatorState{device_code_response: device_code_response}) do
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

        #
        # Each time we polled without success, decrement the :expires_in seconds
        #
        state
        |> Map.put(
          :device_code_response,
          device_code_response
          |> Map.put(:expires_in, device_code_response |> DeviceCodeResponse.expires_in())
        )
    end
  end

  defp refresh_token_impl(state = %DeviceAuthenticatorState{}) do
    case state do
      %DeviceAuthenticatorState{refresh_timer: refresh_timer} ->
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
