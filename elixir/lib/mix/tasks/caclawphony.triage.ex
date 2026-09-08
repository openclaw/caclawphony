defmodule Mix.Tasks.Caclawphony.Triage do
  use Mix.Task

  alias SymphonyElixir.Linear.Client

  @shortdoc "Queue GitHub PRs for triage enrichment (creates Backlog issues)"

  @moduledoc """
  Creates lightweight Linear issues in the Backlog column from PR numbers.
  Symphony's enrichment agent will pick them up and expand them into
  structured assessments before moving them to Todo.

  Usage:

      mix caclawphony.triage 35628 35714
      mix caclawphony.triage --priority 2 35628
      mix caclawphony.triage --help

  Options:

      --priority N   Set initial priority (0=none, 1=urgent, 2=high, 3=medium, 4=low)
                     Default: none (enrichment agent will set it)
  """

  @backlog_state_id "33710d02-89f4-4a7b-8b0c-075250c19b3e"
  @project_id "07919ebc-e133-4c0c-82b9-ead654ec06a2"
  @team_key "MAR"

  @team_query """
  query TeamByKey($key: String!) {
    teams(filter: { key: { eq: $key } }, first: 1) {
      nodes { id key }
    }
  }
  """

  @issue_create_mutation """
  mutation CreateIssue($input: IssueCreateInput!) {
    issueCreate(input: $input) {
      success
      issue { id identifier url }
    }
  }
  """

  @impl Mix.Task
  def run(args) do
    {opts, pr_args, invalid} =
      OptionParser.parse(args,
        strict: [help: :boolean, priority: :integer],
        aliases: [h: :help, p: :priority]
      )

    cond do
      opts[:help] ->
        Mix.shell().info(@moduledoc)

      invalid != [] ->
        Mix.raise("Invalid option(s): #{inspect(invalid)}")

      pr_args == [] ->
        Mix.raise("Provide at least one PR number. Example: mix caclawphony.triage 35628 35714")

      true ->
        Mix.Task.run("app.start")

        priority = opts[:priority]

        if priority && priority not in 0..4 do
          Mix.raise("Priority must be 0-4 (got #{priority})")
        end

        pr_numbers = Enum.map(pr_args, &parse_pr_number!/1)
        team_id = fetch_team_id!(@team_key)

        Enum.each(pr_numbers, fn pr_number ->
          pr_title = fetch_pr_field!(pr_number, "title")
          pr_url = fetch_pr_field!(pr_number, "url")

          issue =
            create_backlog_issue!(%{
              title: "PR ##{pr_number}: #{pr_title}",
              description: "#{pr_url}",
              team_id: team_id,
              state_id: @backlog_state_id,
              project_id: @project_id,
              priority: priority
            })

          Mix.shell().info("Queued #{issue["identifier"]} for triage: PR ##{pr_number} (#{issue["url"]})")
        end)
    end
  end

  defp parse_pr_number!(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> Integer.to_string(number)
      _ -> Mix.raise("Invalid PR number: #{inspect(value)}")
    end
  end

  defp fetch_pr_field!(pr_number, field) do
    gh_path =
      case System.find_executable("gh") do
        nil -> Mix.raise("GitHub CLI (gh) is required but was not found in PATH")
        path -> path
      end

    args = ["pr", "view", pr_number, "--repo", "openclaw/openclaw", "--json", field, "-q", ".#{field}"]

    case System.cmd(gh_path, args, stderr_to_stdout: true) do
      {value, 0} ->
        value
        |> String.trim()
        |> case do
          "" -> Mix.raise("PR ##{pr_number} returned an empty #{field}")
          trimmed -> trimmed
        end

      {output, status} ->
        Mix.raise("Failed to read PR ##{pr_number} #{field} via gh (exit #{status}): #{String.trim(output)}")
    end
  end

  defp fetch_team_id!(team_key) do
    body = graphql_or_raise!(@team_query, %{key: team_key}, operation_name: "TeamByKey")

    case get_in(body, ["data", "teams", "nodes"]) do
      [%{"id" => id} | _rest] when is_binary(id) and id != "" -> id
      _ -> Mix.raise("Could not find Linear team with key #{inspect(team_key)}")
    end
  end

  defp create_backlog_issue!(attrs) do
    input =
      %{
        title: attrs.title,
        description: attrs.description,
        teamId: attrs.team_id,
        stateId: attrs.state_id,
        projectId: attrs.project_id
      }
      |> maybe_put(:priority, attrs[:priority])

    body =
      graphql_or_raise!(
        @issue_create_mutation,
        %{input: input},
        operation_name: "CreateIssue"
      )

    issue_create = get_in(body, ["data", "issueCreate"])

    cond do
      !is_map(issue_create) ->
        Mix.raise("Linear issueCreate payload missing")

      issue_create["success"] != true ->
        Mix.raise("Linear issueCreate reported success=false")

      !is_map(issue_create["issue"]) ->
        Mix.raise("Linear issueCreate did not return an issue")

      true ->
        issue_create["issue"]
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp graphql_or_raise!(query, variables, opts) do
    case Client.graphql(query, variables, opts) do
      {:ok, %{"errors" => errors}} when is_list(errors) ->
        Mix.raise("Linear GraphQL returned errors: #{inspect(errors)}")

      {:ok, body} when is_map(body) ->
        body

      {:ok, other} ->
        Mix.raise("Unexpected Linear GraphQL payload: #{inspect(other)}")

      {:error, reason} ->
        Mix.raise("Linear GraphQL request failed: #{inspect(reason)}")
    end
  end
end
