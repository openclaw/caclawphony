defmodule Mix.Tasks.Caclawphony.IntakeTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias Mix.Tasks.Caclawphony.{Review, Triage}
  alias SymphonyElixir.{Orchestrator, TestSupport, Workflow, WorkflowStore}

  @triage_state "0b100831-6a06-431d-848a-6d20980ec7e5"
  @review_state "2b76930f-a193-4b8f-ade5-97afed5414aa"
  @backlog_state "33710d02-89f4-4a7b-8b0c-075250c19b3e"
  @project "07919ebc-e133-4c0c-82b9-ead654ec06a2"
  @env_keys ~w(PATH INTAKE_GH_LOG INTAKE_GH_MODE LINEAR_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID)

  setup do
    previous_env = Map.new(@env_keys, &{&1, System.get_env(&1)})
    previous_shell = Mix.shell()
    previous_options = Req.default_options()
    previous_options_present = Application.fetch_env(:req, :default_options) != :error
    previous_workflow = Application.fetch_env(:symphony_elixir, :workflow_file_path)
    orchestrator = Process.whereis(Orchestrator)
    root = Path.join(System.tmp_dir!(), "caclawphony-intake-#{System.unique_integer([:positive])}")
    bin = Path.join(root, "bin")
    log = Path.join(root, "gh.log")

    # Polling must not consume HTTP expectations while global fixtures are installed.
    if is_pid(orchestrator), do: :ok = Supervisor.terminate_child(SymphonyElixir.Supervisor, Orchestrator)

    on_exit(fn ->
      Req.default_options(previous_options)
      unless previous_options_present, do: Application.delete_env(:req, :default_options)
      Mix.shell(previous_shell)
      Enum.each(previous_env, fn {key, value} -> TestSupport.restore_env(key, value) end)

      case previous_workflow do
        {:ok, path} -> Application.put_env(:symphony_elixir, :workflow_file_path, path)
        :error -> Application.delete_env(:symphony_elixir, :workflow_file_path)
      end

      WorkflowStore.force_reload()
      File.rm_rf!(root)
      if is_pid(orchestrator), do: {:ok, _pid} = Supervisor.restart_child(SymphonyElixir.Supervisor, Orchestrator)
    end)

    File.mkdir_p!(bin)
    File.write!(log, "")
    File.write!(Path.join(bin, "gh"), gh_script())
    File.chmod!(Path.join(bin, "gh"), 0o755)
    Enum.each(@env_keys, &System.delete_env/1)
    System.put_env(%{"PATH" => bin, "INTAKE_GH_LOG" => log, "INTAKE_GH_MODE" => "ok"})
    workflow = Path.join(root, "WORKFLOW.md")
    TestSupport.write_workflow_file!(workflow, tracker_api_token: "fixture-linear-token")
    Workflow.set_workflow_file_path(workflow)
    Mix.shell(Mix.Shell.Process)
    Req.default_options(Keyword.put(previous_options, :plug, {Req.Test, __MODULE__}))

    Req.Test.stub(__MODULE__, fn conn ->
      send(self(), {:unexpected_request, conn.request_path})
      raise "unexpected intake request"
    end)

    :ok
  end

  for task <- [Review, Triage] do
    test "#{inspect(task)} prints help without external operations" do
      for flag <- ["--help", "-h"] do
        unquote(task).run([flag])
        assert_received {:mix_shell, :info, [help]}
        assert help =~ "Usage:"
        assert help =~ "--help"
        assert_no_more_operations()
      end

      assert gh_calls() == []
    end

    test "#{inspect(task)} rejects invalid input before external operations" do
      for {args, message} <- [
            {[], "Provide at least one PR number"},
            {["--unknown"], "Invalid option"},
            {["abc"], "Invalid PR number"},
            {["0"], "Invalid PR number"},
            {["--", "-1"], "Invalid PR number"},
            {["12tail"], "Invalid PR number"}
          ] do
        error = assert_raise Mix.Error, fn -> unquote(task).run(args) end
        assert error.message =~ message
        assert_no_more_operations()
      end

      assert gh_calls() == []
    end

    test "#{inspect(task)} rejects a missing gh executable before creating issues" do
      expect_team()
      System.put_env("PATH", "")

      assert_raise Mix.Error, "GitHub CLI (gh) is required but was not found in PATH", fn ->
        unquote(task).run(["101"])
      end

      assert_team_request()
      assert gh_calls() == []
      assert_no_more_operations()
    end

    for {mode, field, message} <- [
          {"blank-title", "title", "PR #101 returned an empty title"},
          {"blank-url", "url", "PR #101 returned an empty url"},
          {"exit-title", "title", "Failed to read PR #101 title via gh (exit 17): fixture failure"},
          {"exit-url", "url", "Failed to read PR #101 url via gh (exit 17): fixture failure"}
        ] do
      test "#{inspect(task)} handles gh #{mode} without creating an issue" do
        expect_team()
        System.put_env("INTAKE_GH_MODE", unquote(mode))
        assert_raise Mix.Error, unquote(message), fn -> unquote(task).run(["101"]) end
        assert_team_request()
        fields = if unquote(field) == "title", do: ["title"], else: ["title", "url"]
        assert gh_calls() == Enum.map(fields, &gh_argv("101", &1))
        assert_no_more_operations()
      end
    end

    test "#{inspect(task)} rejects teams without a usable id before gh" do
      for nodes <- [[], [%{"id" => nil}], [%{"id" => ""}], [%{"id" => 42}], [%{"key" => "MAR"}]] do
        expect_json(%{"data" => %{"teams" => %{"nodes" => nodes}}})

        assert_raise Mix.Error, ~r/Could not find Linear team with key "MAR"/, fn ->
          unquote(task).run(["101"])
        end

        assert_team_request()
        assert gh_calls() == []
        assert_no_more_operations()
      end
    end

    test "#{inspect(task)} reports GraphQL and HTTP failures without writes" do
      for {response, message} <- [
            {fn conn -> Req.Test.json(conn, %{"errors" => [%{"message" => "fixture denial"}]}) end, "Linear GraphQL returned errors"},
            {fn conn -> Req.Test.json(conn, 42) end, "Unexpected Linear GraphQL payload: 42"},
            {fn conn -> Plug.Conn.send_resp(conn, 400, "fixture rejection") end, "linear_api_status, 400"},
            {fn conn -> Req.Test.transport_error(conn, :timeout) end, "Req.TransportError"}
          ] do
        expect_response(response)

        capture_log(fn ->
          error = assert_raise Mix.Error, fn -> unquote(task).run(["101"]) end
          assert error.message =~ message
        end)

        assert_team_request()
        assert gh_calls() == []
        assert_no_more_operations()
      end
    end

    for {payload, message} <- [
          {nil, "Linear issueCreate payload missing"},
          {%{"success" => false}, "Linear issueCreate reported success=false"},
          {%{"success" => true}, "Linear issueCreate did not return an issue"}
        ] do
      test "#{inspect(task)} rejects creation response #{message} without reporting success" do
        expect_team()
        expect_json(%{"data" => %{"issueCreate" => unquote(Macro.escape(payload))}})
        assert_raise Mix.Error, unquote(message), fn -> unquote(task).run(["101"]) end
        assert_team_request()
        request = take_request()
        assert request.body["operationName"] == "CreateIssue"
        assert request.gh == expected_gh_calls(["101"])
        assert gh_calls() == expected_gh_calls(["101"])
        assert_no_more_operations()
      end
    end
  end

  for {task, options, prs, state, priority} <- [
        {Review, [], ["101"], @triage_state, :omitted},
        {Review, [], ["101", "202"], @triage_state, :omitted},
        {Review, ["--direct"], ["101"], @review_state, :omitted},
        {Review, ["-d"], ["101"], @review_state, :omitted},
        {Triage, [], ["101"], @backlog_state, :omitted},
        {Triage, [], ["101", "202"], @backlog_state, :omitted},
        {Triage, ["--priority", "0"], ["101"], @backlog_state, 0},
        {Triage, ["--priority", "4"], ["101"], @backlog_state, 4},
        {Triage, ["-p", "2"], ["101"], @backlog_state, 2}
      ] do
    test "#{inspect(task)} imports #{inspect(options ++ prs)} with its public payload contract" do
      assert_intake(unquote(task), unquote(options), unquote(prs), unquote(state), unquote(priority))
    end
  end

  test "triage rejects invalid priority before external operations" do
    for {priority, message} <- [{"-1", "Priority must be 0-4"}, {"5", "Priority must be 0-4"}, {"high", "Invalid option"}, {"2tail", "Invalid option"}] do
      error = assert_raise Mix.Error, fn -> Triage.run(["--priority", priority, "101"]) end
      assert error.message =~ message
      assert_no_more_operations()
    end

    assert gh_calls() == []
  end

  defp assert_intake(task, options, prs, state, priority) do
    expect_team()

    Enum.each(prs, fn pr ->
      expect_json(%{"data" => %{"issueCreate" => %{"success" => true, "issue" => %{"identifier" => "TEST-#{pr}", "url" => "https://example.org/issues/#{pr}"}}}})
    end)

    before_call = DateTime.utc_now() |> DateTime.truncate(:second)
    task.run(options ++ prs)
    after_call = DateTime.utc_now() |> DateTime.truncate(:second)
    assert_team_request()

    prs
    |> Enum.with_index(1)
    |> Enum.each(fn {pr, count} ->
      request = take_request()
      assert request.body["operationName"] == "CreateIssue"
      assert request.body["query"] =~ "mutation CreateIssue("
      assert request.gh == expected_gh_calls(Enum.take(prs, count))
      input = request.body["variables"]["input"]
      assert input["title"] == "PR ##{pr}: Example PR #{pr}"
      assert input["teamId"] == "fixture-team"
      assert input["stateId"] == state
      assert input["projectId"] == @project

      if priority == :omitted, do: refute(Map.has_key?(input, "priority")), else: assert(input["priority"] == priority)

      assert_received {:mix_shell, :info, [output]}

      if task == Review do
        assert output == "Created TEST-#{pr} for PR ##{pr} (https://example.org/issues/#{pr})"
        assert input["description"] =~ "- PR Number: ##{pr}\n"
        assert input["description"] =~ "- PR Title: Example PR #{pr}\n"
        assert input["description"] =~ "- PR URL: https://example.org/pr/#{pr}\n"
        assert input["description"] =~ "- Imported By: `mix caclawphony.review`"
        [_, timestamp] = Regex.run(~r/^- Imported At \(UTC\): (.+)$/m, input["description"])
        assert {:ok, imported, 0} = DateTime.from_iso8601(timestamp)
        assert imported.microsecond == {0, 0}
        assert DateTime.compare(imported, before_call) in [:eq, :gt]
        assert DateTime.compare(imported, after_call) in [:eq, :lt]
      else
        assert output == "Queued TEST-#{pr} for triage: PR ##{pr} (https://example.org/issues/#{pr})"
        assert input["description"] == "https://example.org/pr/#{pr}"
      end
    end)

    assert gh_calls() == expected_gh_calls(prs)
    assert_no_more_operations()
  end

  defp expect_team, do: expect_json(%{"data" => %{"teams" => %{"nodes" => [%{"id" => "fixture-team"}]}}})
  defp expect_json(body), do: expect_response(&Req.Test.json(&1, body))

  defp expect_response(response) do
    Req.Test.expect(__MODULE__, fn conn ->
      send(self(), {:request, %{method: conn.method, host: conn.host, path: conn.request_path, headers: conn.req_headers, raw: Req.Test.raw_body(conn), gh: gh_calls()}})
      response.(conn)
    end)
  end

  defp take_request do
    assert_received {:request, request}
    assert request.method == "POST"
    assert request.host == "api.linear.app"
    assert request.path == "/graphql"
    assert {"authorization", "fixture-linear-token"} in request.headers
    Map.put(request, :body, Jason.decode!(request.raw))
  end

  defp assert_team_request do
    request = take_request()
    assert request.body["operationName"] == "TeamByKey"
    assert request.body["query"] =~ "query TeamByKey("
    assert request.body["variables"] == %{"key" => "MAR"}
    assert request.gh == []
  end

  defp assert_no_more_operations do
    Req.Test.verify!(__MODULE__)
    refute_received {:request, _}
    refute_received {:unexpected_request, _}
    refute_received {:mix_shell, :info, _}
  end

  defp expected_gh_calls(prs), do: for(pr <- prs, field <- ["title", "url"], do: gh_argv(pr, field))
  defp gh_argv(pr, field), do: ["pr", "view", pr, "--repo", "openclaw/openclaw", "--json", field, "-q", ".#{field}"]

  defp gh_calls do
    System.fetch_env!("INTAKE_GH_LOG")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&String.split(&1, <<0>>, trim: true))
  end

  defp gh_script do
    """
    #!/bin/sh
    printf '%s\\0' "$@" >> "$INTAKE_GH_LOG"
    printf '\\n' >> "$INTAKE_GH_LOG"
    case "$INTAKE_GH_MODE:$7" in
      blank-title:title|blank-url:url) printf ' \\n'; exit 0 ;;
      exit-title:title|exit-url:url) printf ' fixture failure \\n' >&2; exit 17 ;;
    esac
    case "$7" in
      title) printf '  Example PR %s  \\n' "$3" ;;
      url) printf '  https://example.org/pr/%s  \\n' "$3" ;;
      *) exit 99 ;;
    esac
    """
  end
end
