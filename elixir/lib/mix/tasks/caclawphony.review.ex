defmodule Mix.Tasks.Caclawphony.Review do
  use Mix.Task

  alias SymphonyElixir.Linear.Client

  @shortdoc "Create Linear review issues from GitHub PR numbers"

  @moduledoc """
  Creates Linear review issues from one or more GitHub PR numbers.

  Usage:

      mix caclawphony.review 34511 34554
      mix caclawphony.review --direct 34511    # skip triage, go straight to review
      mix caclawphony.review --help
  """

  @triage_state_id "0b100831-6a06-431d-848a-6d20980ec7e5"
  @review_state_id "2b76930f-a193-4b8f-ade5-97afed5414aa"
  @project_id "07919ebc-e133-4c0c-82b9-ead654ec06a2"
  @team_key "MAR"

  @team_query """
  query TeamByKey($key: String!) {
    teams(filter: { key: { eq: $key } }, first: 1) {
      nodes {
        id
        key
      }
    }
  }
  """

  @issue_create_mutation """
  mutation CreateIssue($input: IssueCreateInput!) {
    issueCreate(input: $input) {
      success
      issue {
        id
        identifier
        url
      }
    }
  }
  """

  @doc """
  Creates one Linear review issue per provided pull request number.
  """
  @impl Mix.Task
  def run(args) do
    {opts, pr_args, invalid} =
      OptionParser.parse(args, strict: [help: :boolean, direct: :boolean], aliases: [h: :help, d: :direct])

    cond do
      opts[:help] ->
        Mix.shell().info(@moduledoc)

      invalid != [] ->
        Mix.raise("Invalid option(s): #{inspect(invalid)}")

      pr_args == [] ->
        Mix.raise("Provide at least one PR number. Example: mix caclawphony.review 34511 34554")

      true ->
        Mix.Task.run("app.start")

        pr_numbers = Enum.map(pr_args, &parse_pr_number!/1)
        team_id = fetch_team_id!(@team_key)
        state_id = if opts[:direct], do: @review_state_id, else: @triage_state_id

        Enum.each(pr_numbers, fn pr_number ->
          pr_title = fetch_pr_field!(pr_number, "title")
          pr_url = fetch_pr_field!(pr_number, "url")

          issue =
            create_review_issue!(%{
              title: "PR ##{pr_number}: #{pr_title}",
              description: build_description(pr_number, pr_title, pr_url),
              team_id: team_id,
              state_id: state_id,
              project_id: @project_id
            })

          Mix.shell().info("Created #{issue["identifier"]} for PR ##{pr_number} (#{issue["url"]})")
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
      [%{"id" => id} | _rest] when is_binary(id) and id != "" ->
        id

      _ ->
        Mix.raise("Could not find Linear team with key #{inspect(team_key)}")
    end
  end

  defp create_review_issue!(attrs) do
    body =
      graphql_or_raise!(
        @issue_create_mutation,
        %{
          input: %{
            title: attrs.title,
            description: attrs.description,
            teamId: attrs.team_id,
            stateId: attrs.state_id,
            projectId: attrs.project_id
          }
        },
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

  defp build_description(pr_number, pr_title, pr_url) do
    imported_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    """
    GitHub PR intake for review.

    - PR Number: ##{pr_number}
    - PR Title: #{pr_title}
    - PR URL: #{pr_url}
    - Imported At (UTC): #{imported_at}
    - Imported By: `mix caclawphony.review`
    """
    |> String.trim()
  end
end
