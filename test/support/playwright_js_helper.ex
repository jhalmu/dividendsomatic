defmodule DividendsomaticWeb.PlaywrightJsHelper do
  @moduledoc """
  Helper for executing JavaScript in Playwright tests.
  Enables integration with axe-core for accessibility testing.
  """

  alias PlaywrightEx.Frame

  @default_timeout 30_000

  def execute_js(session, javascript) do
    frame_id = get_frame_id(session)

    wrapped_js =
      if needs_wrapping?(javascript) do
        "(async () => { #{javascript} })()"
      else
        javascript
      end

    case Frame.evaluate(frame_id,
           expression: wrapped_js,
           arg: "",
           timeout: @default_timeout
         ) do
      {:ok, result} -> {session, result}
      {:error, reason} -> raise "JavaScript execution failed: #{inspect(reason)}"
    end
  end

  def run_js(session, javascript) do
    {session, _result} = execute_js(session, javascript)
    session
  end

  defp needs_wrapping?(javascript) do
    String.contains?(javascript, "await ") or
      (String.contains?(javascript, "return ") and not String.contains?(javascript, "function"))
  end

  defp get_frame_id(%{frame_id: frame_id}), do: frame_id

  defp get_frame_id(_session) do
    raise """
    Could not find frame_id in session.
    Make sure you're using PhoenixTest.Playwright.Case and have visited a page first.
    """
  end
end
