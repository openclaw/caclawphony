defmodule SymphonyElixir.OrchestratorWorkspaceCleanupTest do
  use SymphonyElixir.TestSupport

  test "orchestrator terminal cleanup does not delete files outside the workspace root" do
    test_root = posix_tmp("symphony-elixir-cleanup-escape-#{System.unique_integer([:positive])}")
    workspace_root = Path.join(test_root, "workspaces")
    outside_dir = Path.join(test_root, "outside")
    outside_file = Path.join(outside_dir, "keep-me.txt")
    issue_id = "issue-escape"
    issue_identifier = "../outside"

    try do
      File.mkdir_p!(workspace_root)
      File.mkdir_p!(outside_dir)
      File.write!(outside_file, "do not delete\n")

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        tracker_active_states: ["Todo", "In Progress"],
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
      )

      assert Path.expand(Config.workspace_root()) == Path.expand(workspace_root)

      state = terminal_cleanup_state(issue_id, issue_identifier)

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        state: "Done",
        title: "Crafted identifier",
        description: "Must stay inside workspace root",
        labels: []
      }

      Orchestrator.reconcile_issue_states_for_test([issue], state)

      assert File.exists?(outside_file)
      assert File.read!(outside_file) == "do not delete\n"
    after
      File.rm_rf(test_root)
    end
  end

  test "orchestrator terminal cleanup deletes the sanitized Linear-like workspace directory" do
    workspace_root = posix_tmp("symphony-elixir-cleanup-linear-#{System.unique_integer([:positive])}")
    issue_id = "issue-linear"
    issue_identifier = "TEAM-42"

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        tracker_active_states: ["Todo", "In Progress"],
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
      )

      assert {:ok, workspace} = Workspace.create_for_issue(issue_identifier)
      assert Path.basename(workspace) == "TEAM-42"
      File.write!(Path.join(workspace, "marker.txt"), "stale\n")

      state = terminal_cleanup_state(issue_id, issue_identifier)

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        state: "Done",
        title: "Linear workspace",
        description: "Normal identifier",
        labels: []
      }

      Orchestrator.reconcile_issue_states_for_test([issue], state)

      refute File.exists?(workspace)
    after
      File.rm_rf(workspace_root)
    end
  end

  test "orchestrator terminal cleanup deletes the create-time sanitized workspace for slashed ids" do
    workspace_root = posix_tmp("symphony-elixir-cleanup-slash-#{System.unique_integer([:positive])}")
    issue_id = "issue-slash"
    issue_identifier = "TEAM/42"

    try do
      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        tracker_active_states: ["Todo", "In Progress"],
        tracker_terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
      )

      assert {:ok, workspace} = Workspace.create_for_issue(issue_identifier)
      assert Path.basename(workspace) == "TEAM_42"
      File.write!(Path.join(workspace, "marker.txt"), "stale\n")

      state = terminal_cleanup_state(issue_id, issue_identifier)

      issue = %Issue{
        id: issue_id,
        identifier: issue_identifier,
        state: "Done",
        title: "Slashed identifier",
        description: "Create-time sanitization must match cleanup",
        labels: []
      }

      Orchestrator.reconcile_issue_states_for_test([issue], state)

      refute File.exists?(workspace)
    after
      File.rm_rf(workspace_root)
    end
  end

  defp posix_tmp(name) do
    System.tmp_dir!()
    |> Path.join(name)
    |> Path.expand()
    |> String.replace("\\", "/")
  end

  defp terminal_cleanup_state(issue_id, issue_identifier) do
    %Orchestrator.State{
      running: %{
        issue_id => %{
          pid: nil,
          ref: nil,
          identifier: issue_identifier,
          issue: %Issue{id: issue_id, state: "Todo", identifier: issue_identifier},
          started_at: DateTime.utc_now()
        }
      },
      claimed: MapSet.new([issue_id]),
      codex_totals: %{input_tokens: 0, output_tokens: 0, total_tokens: 0, seconds_running: 0},
      retry_attempts: %{}
    }
  end
end
