defmodule SportsFanatic.Predictions.Inference do
  @moduledoc """
  Thin HTTP client for the Python `/inference/hit` endpoint.

  Single-call contract: ship training + inference rows, receive predictions.
  See architect spec §ML Inference Strategy. Uses the existing circuit
  breaker so a broken Python helper does not stall the whole pipeline.
  """

  require Logger

  alias SportsFanatic.PythonBridge.CircuitBreaker

  @timeout 120_000
  @path "/inference/hit"

  @spec score([map], [map]) ::
          {:ok, [%{required(String.t()) => term()}], String.t() | nil} | {:error, term()}
  def score(training_rows, inference_rows)
      when is_list(training_rows) and is_list(inference_rows) do
    case do_request(training_rows, inference_rows) do
      {:ok, %{"predictions" => predictions, "model_version" => version}} ->
        {:ok, predictions, version}

      {:ok, %{"predictions" => predictions}} ->
        {:ok, predictions, nil}

      {:ok, other} ->
        {:error, {:bad_response_shape, other}}

      err ->
        err
    end
  end

  defp do_request(training, inference) do
    base = Application.get_env(:sports_fanatic, :python_bridge_url, "http://localhost:8000")
    url = base <> @path
    body = %{"training_rows" => training, "inference_rows" => inference}

    cb_available = Process.whereis(CircuitBreaker) != nil

    if cb_available do
      case CircuitBreaker.check() do
        :open ->
          Logger.warning("Inference: circuit open; skipping")
          {:error, :circuit_open}

        _ ->
          do_post(url, body, true)
      end
    else
      do_post(url, body, false)
    end
  end

  defp do_post(url, body, use_cb?) do
    case Req.post(url, json: body, receive_timeout: @timeout) do
      {:ok, %{status: 200, body: resp}} ->
        if use_cb?, do: CircuitBreaker.record_success()
        {:ok, resp}

      {:ok, %{status: s, body: resp}} ->
        if use_cb?, do: CircuitBreaker.record_failure()
        {:error, {s, resp}}

      {:error, reason} ->
        if use_cb?, do: CircuitBreaker.record_failure()
        {:error, reason}
    end
  end
end
