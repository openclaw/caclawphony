defmodule SymphonyElixir.Notifier do
  @moduledoc """
  Sends external notifications for orchestrator gate transitions.
  """

  require Logger
  alias SymphonyElixir.Config
  alias SymphonyElixir.Linear.Issue

  @spec notify(String.t() | nil, String.t() | nil) :: :ok
  def notify(issue_identifier, state_name) do
    issue_context = issue_context(issue_identifier, state_name)
    notifications = Config.notifications()

    case telegram_credentials(notifications) do
      {:ok, token, chat_id} ->
        send_telegram_message(token, chat_id, issue_context, notifications.template)

      {:error, reason} ->
        Logger.warning("Telegram notification skipped for issue=#{inspect(issue_identifier)} state=#{inspect(state_name)} reason=#{inspect(reason)}")
    end

    :ok
  end

  @spec notify(Issue.t()) :: :ok
  def notify(%Issue{} = issue) do
    notify(issue.identifier, issue.state)
  end

  defp send_telegram_message(token, chat_id, issue_context, template) do
    text = render_template(template, issue_context)

    payload = %{
      chat_id: chat_id,
      text: text
    }

    url = "https://api.telegram.org/bot#{token}/sendMessage"

    case Req.post(url, json: payload, connect_options: [timeout: 10_000], receive_timeout: 10_000) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Telegram notification failed for issue=#{inspect(issue_context["identifier"])} state=#{inspect(issue_context["state"])} status=#{status} body=#{inspect(body)}")

      {:error, reason} ->
        Logger.warning("Telegram notification request error for issue=#{inspect(issue_context["identifier"])} state=#{inspect(issue_context["state"])} error=#{inspect(reason)}")
    end
  rescue
    exception ->
      Logger.warning("Telegram notification crashed for issue=#{inspect(issue_context["identifier"])} state=#{inspect(issue_context["state"])} error=#{Exception.message(exception)}")
  end

  defp telegram_credentials(notifications) do
    token = get_in(notifications, [:telegram, :bot_token])
    chat_id = get_in(notifications, [:telegram, :chat_id])

    cond do
      is_nil(token) or token == "" -> {:error, :missing_telegram_bot_token}
      is_nil(chat_id) or chat_id == "" -> {:error, :missing_telegram_chat_id}
      true -> {:ok, token, chat_id}
    end
  end

  defp render_template(template, issue_context) do
    template = String.trim(template)

    try do
      template
      |> Solid.parse!()
      |> Solid.render!(%{"issue" => issue_context}, strict_variables: true, strict_filters: true)
      |> IO.iodata_to_binary()
      |> case do
        "" -> default_message(issue_context)
        rendered -> rendered
      end
    rescue
      error ->
        Logger.warning("Telegram notification template render failed for issue=#{inspect(issue_context["identifier"])} state=#{inspect(issue_context["state"])} error=#{Exception.message(error)}")
        default_message(issue_context)
    end
  end

  defp default_message(issue_context) do
    "🧹 #{format_message_field(issue_context["identifier"])}: moved to #{format_message_field(issue_context["state"])}. Review results in workspace."
  end

  defp issue_context(issue_identifier, state_name) do
    %{
      "identifier" => issue_identifier,
      "state" => state_name
    }
  end

  defp format_message_field(value) when is_binary(value) and byte_size(value) > 0, do: value
  defp format_message_field(_value), do: "unknown"
end
