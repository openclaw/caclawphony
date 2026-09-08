defmodule SymphonyElixir.NotifierTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias SymphonyElixir.Linear.Issue
  alias SymphonyElixir.{Notifier, Orchestrator, TestSupport, Workflow, WorkflowStore}

  setup do
    previous_options = Req.default_options()
    previous_options_present = Application.fetch_env(:req, :default_options) != :error
    previous_workflow = Application.fetch_env(:symphony_elixir, :workflow_file_path)
    previous_env = Map.new(~w(TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID), &{&1, System.get_env(&1)})
    orchestrator = Process.whereis(Orchestrator)
    root = Path.join(System.tmp_dir!(), "caclawphony-notifier-#{System.unique_integer([:positive])}")

    # Restore fixtures before restarting polling, so only this test owns its HTTP plug.
    if is_pid(orchestrator), do: :ok = Supervisor.terminate_child(SymphonyElixir.Supervisor, Orchestrator)

    on_exit(fn ->
      Req.default_options(previous_options)
      unless previous_options_present, do: Application.delete_env(:req, :default_options)
      Enum.each(previous_env, fn {key, value} -> TestSupport.restore_env(key, value) end)

      case previous_workflow do
        {:ok, path} -> Application.put_env(:symphony_elixir, :workflow_file_path, path)
        :error -> Application.delete_env(:symphony_elixir, :workflow_file_path)
      end

      WorkflowStore.force_reload()
      File.rm_rf!(root)
      if is_pid(orchestrator), do: {:ok, _pid} = Supervisor.restart_child(SymphonyElixir.Supervisor, Orchestrator)
    end)

    Enum.each(Map.keys(previous_env), &System.delete_env/1)
    File.mkdir_p!(root)
    workflow = Path.join(root, "WORKFLOW.md")
    TestSupport.write_workflow_file!(workflow)
    Workflow.set_workflow_file_path(workflow)
    Req.default_options(Keyword.put(previous_options, :plug, {Req.Test, __MODULE__}))

    Req.Test.stub(__MODULE__, fn conn ->
      send(self(), {:unexpected_request, conn.request_path})
      raise "unexpected notification request"
    end)

    :ok
  end

  test "notify is best-effort when chat id is missing" do
    System.put_env("TELEGRAM_BOT_TOKEN", "token")
    System.delete_env("TELEGRAM_CHAT_ID")

    log =
      capture_log(fn ->
        assert :ok = Notifier.notify("MT-700", "Prepare Complete")
      end)

    assert log =~ "Telegram notification skipped"
    assert log =~ "MT-700"
    assert log =~ "Prepare Complete"
    assert log =~ "missing_telegram_chat_id"
    assert_no_more_requests()
  end

  for {token, chat_id, reason} <- [
        {nil, "fixture-chat", "missing_telegram_bot_token"},
        {"", "fixture-chat", "missing_telegram_bot_token"},
        {" \t ", "fixture-chat", "missing_telegram_bot_token"},
        {"fixture-token", "", "missing_telegram_chat_id"},
        {"fixture-token", " \t ", "missing_telegram_chat_id"}
      ] do
    test "normalized credentials #{inspect({token, chat_id})} skip without HTTP" do
      TestSupport.write_workflow_file!(Workflow.workflow_file_path(),
        notification_telegram_bot_token: unquote(token),
        notification_telegram_chat_id: unquote(chat_id)
      )

      log = capture_log(fn -> assert :ok = Notifier.notify("TEST-101", "Review Complete") end)
      assert log =~ "Telegram notification skipped"
      assert log =~ unquote(reason)
      assert_no_more_requests()
    end
  end

  for {arity, status} <- [{2, 200}, {1, 202}] do
    test "notify/#{arity} sends the rendered issue once and accepts HTTP #{status}" do
      configure()
      expect_response(&Plug.Conn.send_resp(&1, unquote(status), "{}"))

      log =
        capture_log(fn ->
          if unquote(arity) == 1 do
            assert :ok = Notifier.notify(%Issue{identifier: "TEST-101", state: "Review Complete"})
          else
            assert :ok = Notifier.notify("TEST-101", "Review Complete")
          end
        end)

      assert log == ""
      assert_notification("🧹 TEST-101: moved to Review Complete. Review results in workspace.")
    end
  end

  for template <- [nil, "", " \t ", 123] do
    test "template setting #{inspect(template)} preserves the normalized default" do
      configure(notification_template: unquote(template))
      expect_response(&Req.Test.json(&1, %{"ok" => true}))
      assert :ok = Notifier.notify("TEST-101", "Review Complete")
      assert_notification("🧹 TEST-101: moved to Review Complete. Review results in workspace.")
    end
  end

  test "an omitted template preserves the default" do
    File.write!(Workflow.workflow_file_path(), """
    ---
    notifications:
      telegram:
        bot_token: fixture-token
        chat_id: fixture-chat
    ---
    Notification fixture.
    """)

    :ok = WorkflowStore.force_reload()
    expect_response(&Req.Test.json(&1, %{"ok" => true}))
    assert :ok = Notifier.notify("TEST-101", "Review Complete")
    assert_notification("🧹 TEST-101: moved to Review Complete. Review results in workspace.")
  end

  test "custom template renders issue fields and trims outer whitespace" do
    configure(notification_template: "  {{ issue.identifier }} reached {{ issue.state }}  ")
    expect_response(&Req.Test.json(&1, %{"ok" => true}))
    assert :ok = Notifier.notify("TEST-202", "Prepare Complete")
    assert_notification("TEST-202 reached Prepare Complete")
  end

  test "an empty rendered template uses the meaningful fallback" do
    configure(notification_template: "{% if false %}unused{% endif %}")
    expect_response(&Req.Test.json(&1, %{"ok" => true}))
    log = capture_log(fn -> assert :ok = Notifier.notify("TEST-101", "Review Complete") end)
    refute log =~ "template render failed"
    assert_notification("🧹 TEST-101: moved to Review Complete. Review results in workspace.")
  end

  for template <- ["{% if issue.identifier %}", "{{ issue.missing }}", "{{ issue.identifier | missing_filter }}"] do
    test "invalid or strict template #{inspect(template)} logs and sends the fallback" do
      configure(notification_template: unquote(template))
      expect_response(&Req.Test.json(&1, %{"ok" => true}))
      log = capture_log(fn -> assert :ok = Notifier.notify("TEST-101", "Review Complete") end)
      assert log =~ "Telegram notification template render failed"
      assert_notification("🧹 TEST-101: moved to Review Complete. Review results in workspace.")
    end
  end

  for {identifier, state, expected} <- [
        {nil, nil, "🧹 unknown: moved to unknown. Review results in workspace."},
        {"", "", "🧹 unknown: moved to unknown. Review results in workspace."},
        {nil, "Review Complete", "🧹 unknown: moved to Review Complete. Review results in workspace."},
        {"TEST-101", nil, "🧹 TEST-101: moved to unknown. Review results in workspace."}
      ] do
    test "fallback retains usable fields for #{inspect({identifier, state})}" do
      configure(notification_template: "{% if false %}unused{% endif %}")
      expect_response(&Req.Test.json(&1, %{"ok" => true}))
      assert :ok = Notifier.notify(unquote(identifier), unquote(state))
      assert_notification(unquote(expected))
    end
  end

  test "non-2xx responses remain best-effort and report status and body" do
    configure()
    expect_response(&Plug.Conn.send_resp(&1, 500, "fixture rejection"))
    log = capture_log(fn -> assert :ok = Notifier.notify("TEST-101", "Review Complete") end)
    assert log =~ "Telegram notification failed"
    assert log =~ "status=500"
    assert log =~ ~s(body="fixture rejection")
    assert_notification("🧹 TEST-101: moved to Review Complete. Review results in workspace.")
  end

  test "transport errors remain best-effort and report the error" do
    configure()
    expect_response(&Req.Test.transport_error(&1, :timeout))
    log = capture_log(fn -> assert :ok = Notifier.notify("TEST-101", "Review Complete") end)
    assert log =~ "Telegram notification request error"
    assert log =~ "timeout"
    assert_notification("🧹 TEST-101: moved to Review Complete. Review results in workspace.")
  end

  test "transport callback exceptions remain best-effort and report the crash" do
    configure()
    expect_response(fn _conn -> raise "fixture callback failure" end)
    log = capture_log(fn -> assert :ok = Notifier.notify("TEST-101", "Review Complete") end)
    assert log =~ "Telegram notification crashed"
    assert log =~ "fixture callback failure"
    assert_notification("🧹 TEST-101: moved to Review Complete. Review results in workspace.")
  end

  defp configure(overrides \\ []) do
    TestSupport.write_workflow_file!(
      Workflow.workflow_file_path(),
      Keyword.merge([notification_telegram_bot_token: "fixture-token", notification_telegram_chat_id: "fixture-chat"], overrides)
    )
  end

  defp expect_response(response) do
    Req.Test.expect(__MODULE__, fn conn ->
      # Notifier rescues callback exceptions; record first and assert outside notify.
      send(self(), {:request, %{method: conn.method, host: conn.host, path: conn.request_path, raw: Req.Test.raw_body(conn)}})
      response.(conn)
    end)
  end

  defp assert_notification(text) do
    assert_received {:request, request}
    assert request.method == "POST"
    assert request.host == "api.telegram.org"
    assert request.path == "/botfixture-token/sendMessage"
    assert Jason.decode!(request.raw) == %{"chat_id" => "fixture-chat", "text" => text}
    assert_no_more_requests()
  end

  defp assert_no_more_requests do
    Req.Test.verify!(__MODULE__)
    refute_received {:request, _}
    refute_received {:unexpected_request, _}
  end
end
