defmodule SymphonyElixir.Config do
  @moduledoc """
  Runtime configuration loaded from `WORKFLOW.md`.
  """

  alias NimbleOptions
  alias SymphonyElixir.Workflow

  @default_active_states ["Todo", "In Progress"]
  @default_terminal_states ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"]
  @default_linear_endpoint "https://api.linear.app/graphql"
  @default_prompt_template """
  You are working on a Linear issue.

  Identifier: {{ issue.identifier }}
  Title: {{ issue.title }}

  Body:
  {% if issue.description %}
  {{ issue.description }}
  {% else %}
  No description provided.
  {% endif %}
  """
  @default_poll_interval_ms 30_000
  @default_workspace_root Path.join(System.tmp_dir!(), "symphony_workspaces")
  @default_hook_timeout_ms 60_000
  @default_max_concurrent_agents 10
  @default_agent_max_turns 20
  @default_max_retry_backoff_ms 300_000
  @default_agent_retry_base_ms 10_000
  @default_agent_continuation_delay_ms 1_000
  @default_notification_gate_states []
  @default_notification_template "🧹 {{ issue.identifier }}: moved to {{ issue.state }}. Review results in workspace."
  @default_gate_assignee "5bbd2a49-0fde-4fdd-b265-f6991c718e87"
  @default_states %{
    "todo" => "0772f6b2-85fa-4c21-ab14-6705687d475f"
  }
  @default_labels %{
    "recommendation" => %{
      "review" => "884ba56a-fb80-4c83-a35e-90ab4dbff32a",
      "wait" => "e2cfbdbb-13e3-4ccc-adeb-5abd00e2b7f9",
      "skip" => "8488053c-9614-4fba-a84e-f2b8b8e65d32"
    },
    "subsystem" => %{
      "gateway" => "dc7faf59-f14a-4f03-a549-c0f7fa68ae91",
      "channels" => "69c1023d-71ee-43b3-ab2c-c2dbb2a3b93a",
      "browser" => "4d8f75c4-96e0-4ba3-afe0-d47d36ffe48a",
      "agents" => "406758af-c1ca-490e-800e-b8fcaa199d07",
      "config" => "ac615836-f2a0-48b3-906c-fcf5f8e61c72",
      "cli" => "904c5231-c8b2-4f68-9db0-2d7ca16a5607",
      "runtime" => "e2a2870b-cd3e-4b9c-a2ec-6e116e2e1efc",
      "auth" => "34fc1c6d-e47a-4e3e-9a51-b9cdade2f5d9",
      "providers" => "74bb9b68-bd9b-4c88-b5c2-56ec3b0a4bde",
      "docs" => "49152b2e-0c39-470e-9b27-3f71e1f27da7"
    }
  }
  @default_gates %{
    "review_complete" => %{
      "state_id" => "4f363475-bf45-48a0-9466-c38eef79aded",
      "assignee" => @default_gate_assignee,
      "notify" => true
    },
    "prepare_complete" => %{
      "state_id" => "0671e7cc-46b5-424e-aed3-d9408c9d3eb9",
      "assignee" => @default_gate_assignee,
      "notify" => true
    }
  }
  @default_codex_command "codex app-server"
  @default_codex_turn_timeout_ms 3_600_000
  @default_codex_read_timeout_ms 5_000
  @default_codex_stall_timeout_ms 300_000
  @default_codex_approval_policy %{
    "reject" => %{
      "sandbox_approval" => true,
      "rules" => true,
      "mcp_elicitations" => true
    }
  }
  @default_codex_thread_sandbox "workspace-write"
  @default_observability_enabled true
  @default_observability_refresh_ms 1_000
  @default_observability_render_interval_ms 16
  @default_server_host "127.0.0.1"
  @workflow_options_schema NimbleOptions.new!(
                             tracker: [
                               type: :map,
                               default: %{},
                               keys: [
                                 kind: [type: {:or, [:string, nil]}, default: nil],
                                 endpoint: [type: :string, default: @default_linear_endpoint],
                                 api_key: [type: {:or, [:string, nil]}, default: nil],
                                 project_slug: [type: {:or, [:string, nil]}, default: nil],
                                 assignee: [type: {:or, [:string, nil]}, default: nil],
                                 active_states: [
                                   type: {:list, :string},
                                   default: @default_active_states
                                 ],
                                 terminal_states: [
                                   type: {:list, :string},
                                   default: @default_terminal_states
                                 ]
                               ]
                             ],
                             polling: [
                               type: :map,
                               default: %{},
                               keys: [
                                 interval_ms: [type: :integer, default: @default_poll_interval_ms]
                               ]
                             ],
                             workspace: [
                               type: :map,
                               default: %{},
                               keys: [
                                 root: [type: {:or, [:string, nil]}, default: @default_workspace_root]
                               ]
                             ],
                             agent: [
                               type: :map,
                               default: %{},
                               keys: [
                                 max_concurrent_agents: [
                                   type: :integer,
                                   default: @default_max_concurrent_agents
                                 ],
                                 max_turns: [
                                   type: :pos_integer,
                                   default: @default_agent_max_turns
                                 ],
                                 max_retry_backoff_ms: [
                                   type: :pos_integer,
                                   default: @default_max_retry_backoff_ms
                                 ],
                                 retry_base_ms: [
                                   type: :pos_integer,
                                   default: @default_agent_retry_base_ms
                                 ],
                                 continuation_delay_ms: [
                                   type: :pos_integer,
                                   default: @default_agent_continuation_delay_ms
                                 ],
                                 max_concurrent_agents_by_state: [
                                   type: {:map, :string, :pos_integer},
                                   default: %{}
                                 ]
                               ]
                             ],
                             codex: [
                               type: :map,
                               default: %{},
                               keys: [
                                 command: [type: :string, default: @default_codex_command],
                                 turn_timeout_ms: [
                                   type: :integer,
                                   default: @default_codex_turn_timeout_ms
                                 ],
                                 read_timeout_ms: [
                                   type: :integer,
                                   default: @default_codex_read_timeout_ms
                                 ],
                                 stall_timeout_ms: [
                                   type: :integer,
                                   default: @default_codex_stall_timeout_ms
                                 ]
                               ]
                             ],
                             hooks: [
                               type: :map,
                               default: %{},
                               keys: [
                                 after_create: [type: {:or, [:string, nil]}, default: nil],
                                 before_run: [type: {:or, [:string, nil]}, default: nil],
                                 after_run: [type: {:or, [:string, nil]}, default: nil],
                                 before_remove: [type: {:or, [:string, nil]}, default: nil],
                                 timeout_ms: [type: :pos_integer, default: @default_hook_timeout_ms]
                               ]
                             ],
                             observability: [
                               type: :map,
                               default: %{},
                               keys: [
                                 dashboard_enabled: [
                                   type: :boolean,
                                   default: @default_observability_enabled
                                 ],
                                 refresh_ms: [
                                   type: :integer,
                                   default: @default_observability_refresh_ms
                                 ],
                                 render_interval_ms: [
                                   type: :integer,
                                   default: @default_observability_render_interval_ms
                                 ]
                               ]
                             ],
                             server: [
                               type: :map,
                               default: %{},
                               keys: [
                                 port: [type: {:or, [:non_neg_integer, nil]}, default: nil],
                                 host: [type: :string, default: @default_server_host]
                               ]
                             ],
                             notifications: [
                               type: :map,
                               default: %{},
                               keys: [
                                 telegram: [
                                   type: :map,
                                   default: %{},
                                   keys: [
                                     bot_token: [type: {:or, [:string, nil]}, default: nil],
                                     chat_id: [type: {:or, [:string, nil]}, default: nil]
                                   ]
                                 ],
                                 gate_states: [
                                   type: {:list, :string},
                                   default: @default_notification_gate_states
                                 ],
                                 template: [type: :string, default: @default_notification_template]
                               ]
                             ],
                             gates: [
                               type: {:map, :string, :map},
                               default: %{}
                             ],
                             labels: [
                               type: {:map, :string, :any},
                               default: %{}
                             ],
                             states: [
                               type: {:map, :string, :string},
                               default: %{}
                             ]
                           )

  @type workflow_payload :: Workflow.loaded_workflow()
  @type tracker_kind :: String.t() | nil
  @type codex_runtime_settings :: %{
          approval_policy: String.t() | map(),
          thread_sandbox: String.t(),
          turn_sandbox_policy: map()
        }
  @type workspace_hooks :: %{
          after_create: String.t() | nil,
          before_run: String.t() | nil,
          after_run: String.t() | nil,
          before_remove: String.t() | nil,
          timeout_ms: pos_integer()
        }

  @spec current_workflow() :: {:ok, workflow_payload()} | {:error, term()}
  def current_workflow do
    Workflow.current()
  end

  @spec tracker_kind() :: tracker_kind()
  def tracker_kind do
    get_in(validated_workflow_options(), [:tracker, :kind])
  end

  @spec linear_endpoint() :: String.t()
  def linear_endpoint do
    get_in(validated_workflow_options(), [:tracker, :endpoint])
  end

  @spec linear_api_token() :: String.t() | nil
  def linear_api_token do
    validated_workflow_options()
    |> get_in([:tracker, :api_key])
    |> resolve_env_value(System.get_env("LINEAR_API_KEY"))
    |> normalize_secret_value()
  end

  @spec linear_project_slug() :: String.t() | nil
  def linear_project_slug do
    get_in(validated_workflow_options(), [:tracker, :project_slug])
  end

  @spec linear_assignee() :: String.t() | nil
  def linear_assignee do
    validated_workflow_options()
    |> get_in([:tracker, :assignee])
    |> resolve_env_value(System.get_env("LINEAR_ASSIGNEE"))
    |> normalize_secret_value()
  end

  @spec linear_active_states() :: [String.t()]
  def linear_active_states do
    get_in(validated_workflow_options(), [:tracker, :active_states])
  end

  @spec linear_terminal_states() :: [String.t()]
  def linear_terminal_states do
    get_in(validated_workflow_options(), [:tracker, :terminal_states])
  end

  @spec poll_interval_ms() :: pos_integer()
  def poll_interval_ms do
    get_in(validated_workflow_options(), [:polling, :interval_ms])
  end

  @spec workspace_root() :: Path.t()
  def workspace_root do
    validated_workflow_options()
    |> get_in([:workspace, :root])
    |> resolve_path_value(@default_workspace_root)
  end

  @spec workspace_hooks() :: workspace_hooks()
  def workspace_hooks do
    hooks = get_in(validated_workflow_options(), [:hooks])

    %{
      after_create: Map.get(hooks, :after_create),
      before_run: Map.get(hooks, :before_run),
      after_run: Map.get(hooks, :after_run),
      before_remove: Map.get(hooks, :before_remove),
      timeout_ms: Map.get(hooks, :timeout_ms)
    }
  end

  @spec hook_timeout_ms() :: pos_integer()
  def hook_timeout_ms do
    get_in(validated_workflow_options(), [:hooks, :timeout_ms])
  end

  @spec max_concurrent_agents() :: pos_integer()
  def max_concurrent_agents do
    get_in(validated_workflow_options(), [:agent, :max_concurrent_agents])
  end

  @spec max_retry_backoff_ms() :: pos_integer()
  def max_retry_backoff_ms do
    get_in(validated_workflow_options(), [:agent, :max_retry_backoff_ms])
  end

  @spec agent_retry_base_ms() :: pos_integer()
  def agent_retry_base_ms do
    get_in(validated_workflow_options(), [:agent, :retry_base_ms])
  end

  @spec agent_continuation_delay_ms() :: pos_integer()
  def agent_continuation_delay_ms do
    get_in(validated_workflow_options(), [:agent, :continuation_delay_ms])
  end

  @spec agent_max_turns() :: pos_integer()
  def agent_max_turns do
    get_in(validated_workflow_options(), [:agent, :max_turns])
  end

  @spec max_concurrent_agents_for_state(term()) :: pos_integer()
  def max_concurrent_agents_for_state(state_name) when is_binary(state_name) do
    state_limits = get_in(validated_workflow_options(), [:agent, :max_concurrent_agents_by_state])
    global_limit = max_concurrent_agents()
    Map.get(state_limits, normalize_issue_state(state_name), global_limit)
  end

  def max_concurrent_agents_for_state(_state_name), do: max_concurrent_agents()

  @spec codex_command() :: String.t()
  def codex_command do
    get_in(validated_workflow_options(), [:codex, :command])
  end

  @spec codex_turn_timeout_ms() :: pos_integer()
  def codex_turn_timeout_ms do
    get_in(validated_workflow_options(), [:codex, :turn_timeout_ms])
  end

  @spec codex_approval_policy() :: String.t() | map()
  def codex_approval_policy do
    case resolve_codex_approval_policy() do
      {:ok, approval_policy} -> approval_policy
      {:error, _reason} -> @default_codex_approval_policy
    end
  end

  @spec codex_thread_sandbox() :: String.t()
  def codex_thread_sandbox do
    case resolve_codex_thread_sandbox() do
      {:ok, thread_sandbox} -> thread_sandbox
      {:error, _reason} -> @default_codex_thread_sandbox
    end
  end

  @spec codex_turn_sandbox_policy(Path.t() | nil) :: map()
  def codex_turn_sandbox_policy(workspace \\ nil) do
    case resolve_codex_turn_sandbox_policy(workspace) do
      {:ok, turn_sandbox_policy} -> turn_sandbox_policy
      {:error, _reason} -> default_codex_turn_sandbox_policy(workspace)
    end
  end

  @spec codex_read_timeout_ms() :: pos_integer()
  def codex_read_timeout_ms do
    get_in(validated_workflow_options(), [:codex, :read_timeout_ms])
  end

  @spec codex_stall_timeout_ms() :: non_neg_integer()
  def codex_stall_timeout_ms do
    validated_workflow_options()
    |> get_in([:codex, :stall_timeout_ms])
    |> max(0)
  end

  @spec workflow_prompt() :: String.t()
  def workflow_prompt do
    case current_workflow() do
      {:ok, %{prompt_template: prompt}} ->
        if String.trim(prompt) == "", do: @default_prompt_template, else: prompt

      _ ->
        @default_prompt_template
    end
  end

  @spec notifications() :: %{
          telegram: %{
            bot_token: String.t() | nil,
            chat_id: String.t() | nil
          },
          gate_states: [String.t()],
          template: String.t()
        }
  def notifications do
    notification_settings = get_in(validated_workflow_options(), [:notifications])
    telegram_settings = Map.get(notification_settings, :telegram, %{})

    %{
      telegram: %{
        bot_token:
          telegram_settings
          |> Map.get(:bot_token)
          |> resolve_env_value(System.get_env("TELEGRAM_BOT_TOKEN"))
          |> normalize_secret_value(),
        chat_id:
          telegram_settings
          |> Map.get(:chat_id)
          |> resolve_env_value(System.get_env("TELEGRAM_CHAT_ID"))
          |> normalize_secret_value()
      },
      gate_states: notification_gate_states(),
      template: Map.get(notification_settings, :template, @default_notification_template)
    }
  end

  @spec gates() :: %{String.t() => %{String.t() => String.t() | boolean() | nil}}
  def gates do
    configured_gates = get_in(validated_workflow_options(), [:gates]) || %{}
    default_assignee = @default_gate_assignee

    @default_gates
    |> merge_gate_definitions(configured_gates)
    |> Enum.into(%{}, fn {gate_name, gate_options} ->
      {gate_name, normalize_gate_options(gate_options, default_assignee)}
    end)
  end

  @spec labels() :: %{String.t() => term()}
  def labels do
    configured_labels = get_in(validated_workflow_options(), [:labels]) || %{}

    @default_labels
    |> deep_merge_maps(configured_labels)
    |> keep_string_values_only()
    |> case do
      :omit -> %{}
      labels -> labels
    end
  end

  @spec states() :: %{String.t() => String.t()}
  def states do
    configured_states = get_in(validated_workflow_options(), [:states]) || %{}

    @default_states
    |> Map.merge(normalize_keys(configured_states))
    |> Enum.reduce(%{}, fn {state_name, state_id}, acc ->
      case state_id |> resolve_env_value(nil) |> normalize_secret_value() do
        nil -> acc
        resolved_state_id -> Map.put(acc, state_name, resolved_state_id)
      end
    end)
  end

  @spec notification_gate_states() :: [String.t()]
  def notification_gate_states do
    configured_gate_states = get_in(validated_workflow_options(), [:notifications, :gate_states]) || []

    case configured_gate_states do
      [] ->
        gates()
        |> Enum.reduce([], fn {gate_name, gate_options}, acc ->
          if gate_options["notify"] == true do
            [gate_name_to_state(gate_name) | acc]
          else
            acc
          end
        end)
        |> Enum.reverse()

      states ->
        states
    end
  end

  @spec notification_template() :: String.t()
  def notification_template do
    notifications().template
  end

  @spec observability_enabled?() :: boolean()
  def observability_enabled? do
    get_in(validated_workflow_options(), [:observability, :dashboard_enabled])
  end

  @spec observability_refresh_ms() :: pos_integer()
  def observability_refresh_ms do
    get_in(validated_workflow_options(), [:observability, :refresh_ms])
  end

  @spec observability_render_interval_ms() :: pos_integer()
  def observability_render_interval_ms do
    get_in(validated_workflow_options(), [:observability, :render_interval_ms])
  end

  @spec server_port() :: non_neg_integer() | nil
  def server_port do
    case Application.get_env(:symphony_elixir, :server_port_override) do
      port when is_integer(port) and port >= 0 ->
        port

      _ ->
        get_in(validated_workflow_options(), [:server, :port])
    end
  end

  @spec server_host() :: String.t()
  def server_host do
    get_in(validated_workflow_options(), [:server, :host])
  end

  @spec validate!() :: :ok | {:error, term()}
  def validate! do
    with {:ok, _workflow} <- current_workflow(),
         :ok <- require_tracker_kind(),
         :ok <- require_linear_token(),
         :ok <- require_linear_project(),
         :ok <- require_valid_codex_runtime_settings() do
      require_codex_command()
    end
  end

  @spec codex_runtime_settings(Path.t() | nil) :: {:ok, codex_runtime_settings()} | {:error, term()}
  def codex_runtime_settings(workspace \\ nil) do
    with {:ok, approval_policy} <- resolve_codex_approval_policy(),
         {:ok, thread_sandbox} <- resolve_codex_thread_sandbox(),
         {:ok, turn_sandbox_policy} <- resolve_codex_turn_sandbox_policy(workspace) do
      {:ok,
       %{
         approval_policy: approval_policy,
         thread_sandbox: thread_sandbox,
         turn_sandbox_policy: turn_sandbox_policy
       }}
    end
  end

  defp require_tracker_kind do
    case tracker_kind() do
      "linear" -> :ok
      "memory" -> :ok
      nil -> {:error, :missing_tracker_kind}
      other -> {:error, {:unsupported_tracker_kind, other}}
    end
  end

  defp require_linear_token do
    case tracker_kind() do
      "linear" ->
        if is_binary(linear_api_token()) do
          :ok
        else
          {:error, :missing_linear_api_token}
        end

      _ ->
        :ok
    end
  end

  defp require_linear_project do
    case tracker_kind() do
      "linear" ->
        if is_binary(linear_project_slug()) do
          :ok
        else
          {:error, :missing_linear_project_slug}
        end

      _ ->
        :ok
    end
  end

  defp require_codex_command do
    if byte_size(String.trim(codex_command())) > 0 do
      :ok
    else
      {:error, :missing_codex_command}
    end
  end

  defp require_valid_codex_runtime_settings do
    case codex_runtime_settings() do
      {:ok, _settings} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validated_workflow_options do
    workflow_config()
    |> extract_workflow_options()
    |> NimbleOptions.validate!(@workflow_options_schema)
  end

  defp extract_workflow_options(config) do
    %{
      tracker: extract_tracker_options(section_map(config, "tracker")),
      polling: extract_polling_options(section_map(config, "polling")),
      workspace: extract_workspace_options(section_map(config, "workspace")),
      agent: extract_agent_options(section_map(config, "agent")),
      codex: extract_codex_options(section_map(config, "codex")),
      hooks: extract_hooks_options(section_map(config, "hooks")),
      observability: extract_observability_options(section_map(config, "observability")),
      server: extract_server_options(section_map(config, "server")),
      notifications: extract_notifications_options(section_map(config, "notifications")),
      gates: extract_gates_options(section_map(config, "gates")),
      labels: extract_labels_options(section_map(config, "labels")),
      states: extract_states_options(section_map(config, "states"))
    }
  end

  defp extract_tracker_options(section) do
    %{}
    |> put_if_present(:kind, normalize_tracker_kind(scalar_string_value(Map.get(section, "kind"))))
    |> put_if_present(:endpoint, scalar_string_value(Map.get(section, "endpoint")))
    |> put_if_present(:api_key, binary_value(Map.get(section, "api_key"), allow_empty: true))
    |> put_if_present(:project_slug, scalar_string_value(Map.get(section, "project_slug")))
    |> put_if_present(:active_states, csv_value(Map.get(section, "active_states")))
    |> put_if_present(:terminal_states, csv_value(Map.get(section, "terminal_states")))
  end

  defp extract_polling_options(section) do
    %{}
    |> put_if_present(:interval_ms, integer_value(Map.get(section, "interval_ms")))
  end

  defp extract_workspace_options(section) do
    %{}
    |> put_if_present(:root, binary_value(Map.get(section, "root")))
  end

  defp extract_agent_options(section) do
    %{}
    |> put_if_present(:max_concurrent_agents, integer_value(Map.get(section, "max_concurrent_agents")))
    |> put_if_present(:max_turns, positive_integer_value(Map.get(section, "max_turns")))
    |> put_if_present(:max_retry_backoff_ms, positive_integer_value(Map.get(section, "max_retry_backoff_ms")))
    |> put_if_present(:retry_base_ms, positive_integer_value(Map.get(section, "retry_base_ms")))
    |> put_if_present(
      :continuation_delay_ms,
      positive_integer_value(Map.get(section, "continuation_delay_ms"))
    )
    |> put_if_present(
      :max_concurrent_agents_by_state,
      state_limits_value(Map.get(section, "max_concurrent_agents_by_state"))
    )
  end

  defp extract_codex_options(section) do
    %{}
    |> put_if_present(:command, command_value(Map.get(section, "command")))
    |> put_if_present(:turn_timeout_ms, integer_value(Map.get(section, "turn_timeout_ms")))
    |> put_if_present(:read_timeout_ms, integer_value(Map.get(section, "read_timeout_ms")))
    |> put_if_present(:stall_timeout_ms, integer_value(Map.get(section, "stall_timeout_ms")))
  end

  defp extract_hooks_options(section) do
    %{}
    |> put_if_present(:after_create, hook_command_value(Map.get(section, "after_create")))
    |> put_if_present(:before_run, hook_command_value(Map.get(section, "before_run")))
    |> put_if_present(:after_run, hook_command_value(Map.get(section, "after_run")))
    |> put_if_present(:before_remove, hook_command_value(Map.get(section, "before_remove")))
    |> put_if_present(:timeout_ms, positive_integer_value(Map.get(section, "timeout_ms")))
  end

  defp extract_observability_options(section) do
    %{}
    |> put_if_present(:dashboard_enabled, boolean_value(Map.get(section, "dashboard_enabled")))
    |> put_if_present(:refresh_ms, integer_value(Map.get(section, "refresh_ms")))
    |> put_if_present(:render_interval_ms, integer_value(Map.get(section, "render_interval_ms")))
  end

  defp extract_server_options(section) do
    %{}
    |> put_if_present(:port, non_negative_integer_value(Map.get(section, "port")))
    |> put_if_present(:host, scalar_string_value(Map.get(section, "host")))
  end

  defp extract_notifications_options(section) do
    %{}
    |> put_if_present(:telegram, extract_notification_telegram_options(section_map(section, "telegram")))
    |> put_if_present(:gate_states, csv_value(Map.get(section, "gate_states")))
    |> put_if_present(:template, notification_template_value(Map.get(section, "template")))
  end

  defp extract_gates_options(section) when is_map(section) do
    Enum.reduce(section, %{}, fn {gate_name, gate_options}, acc ->
      normalized_gate_name = normalize_gate_name(gate_name)

      case extract_gate_options(gate_options) do
        :omit -> acc
        normalized_gate_options -> Map.put(acc, normalized_gate_name, normalized_gate_options)
      end
    end)
  end

  defp extract_gates_options(_section), do: %{}

  defp extract_gate_options(gate_options) when is_map(gate_options) do
    gate_options = normalize_keys(gate_options)

    gate_options =
      %{}
      |> put_if_present(:state_id, binary_value(Map.get(gate_options, "state_id")))
      |> put_if_present(:assignee, binary_value(Map.get(gate_options, "assignee"), allow_empty: true))
      |> put_if_present(:notify, boolean_value(Map.get(gate_options, "notify")))

    if map_size(gate_options) > 0 do
      gate_options
    else
      :omit
    end
  end

  defp extract_gate_options(_gate_options), do: :omit

  defp extract_labels_options(section) when is_map(section) do
    case nested_string_map_value(section) do
      %{} = labels when map_size(labels) > 0 -> labels
      _ -> %{}
    end
  end

  defp extract_labels_options(_section), do: %{}

  defp extract_states_options(section) when is_map(section) do
    section
    |> normalize_keys()
    |> Enum.reduce(%{}, fn {state_name, raw_state_id}, acc ->
      case scalar_string_value(raw_state_id) do
        :omit -> acc
        "" -> acc
        state_id -> Map.put(acc, state_name, state_id)
      end
    end)
    |> case do
      states when map_size(states) > 0 -> states
      _ -> %{}
    end
  end

  defp extract_states_options(_section), do: %{}

  defp extract_notification_telegram_options(section) do
    %{}
    |> put_if_present(:bot_token, binary_value(Map.get(section, "bot_token"), allow_empty: true))
    |> put_if_present(:chat_id, binary_value(Map.get(section, "chat_id"), allow_empty: true))
  end

  defp section_map(config, key) do
    case Map.get(config, key) do
      section when is_map(section) -> section
      _ -> %{}
    end
  end

  defp put_if_present(map, _key, :omit), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)

  defp scalar_string_value(nil), do: :omit
  defp scalar_string_value(value) when is_binary(value), do: String.trim(value)
  defp scalar_string_value(value) when is_boolean(value), do: to_string(value)
  defp scalar_string_value(value) when is_integer(value), do: to_string(value)
  defp scalar_string_value(value) when is_float(value), do: to_string(value)
  defp scalar_string_value(value) when is_atom(value), do: Atom.to_string(value)
  defp scalar_string_value(_value), do: :omit

  defp binary_value(value, opts \\ [])

  defp binary_value(value, opts) when is_binary(value) do
    allow_empty = Keyword.get(opts, :allow_empty, false)

    if value == "" and not allow_empty do
      :omit
    else
      value
    end
  end

  defp binary_value(_value, _opts), do: :omit

  defp command_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :omit
      trimmed -> trimmed
    end
  end

  defp command_value(_value), do: :omit

  defp hook_command_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :omit
      _ -> String.trim_trailing(value)
    end
  end

  defp hook_command_value(_value), do: :omit

  defp notification_template_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :omit
      _ -> value
    end
  end

  defp notification_template_value(_value), do: :omit

  defp csv_value(values) when is_list(values) do
    values
    |> Enum.reduce([], fn value, acc -> maybe_append_csv_value(acc, value) end)
    |> Enum.reverse()
    |> case do
      [] -> :omit
      normalized_values -> normalized_values
    end
  end

  defp csv_value(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> :omit
      normalized_values -> normalized_values
    end
  end

  defp csv_value(_value), do: :omit

  defp maybe_append_csv_value(acc, value) do
    case scalar_string_value(value) do
      :omit ->
        acc

      normalized ->
        append_csv_value_if_present(acc, normalized)
    end
  end

  defp append_csv_value_if_present(acc, value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      acc
    else
      [trimmed | acc]
    end
  end

  defp integer_value(value) do
    case parse_integer(value) do
      {:ok, parsed} -> parsed
      :error -> :omit
    end
  end

  defp positive_integer_value(value) do
    case parse_positive_integer(value) do
      {:ok, parsed} -> parsed
      :error -> :omit
    end
  end

  defp non_negative_integer_value(value) do
    case parse_non_negative_integer(value) do
      {:ok, parsed} -> parsed
      :error -> :omit
    end
  end

  defp boolean_value(value) when is_boolean(value), do: value

  defp boolean_value(value) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> true
      "false" -> false
      _ -> :omit
    end
  end

  defp boolean_value(_value), do: :omit

  defp state_limits_value(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {state_name, limit}, acc ->
      case parse_positive_integer(limit) do
        {:ok, parsed} ->
          Map.put(acc, normalize_issue_state(to_string(state_name)), parsed)

        :error ->
          acc
      end
    end)
  end

  defp state_limits_value(_value), do: :omit

  defp parse_integer(value) when is_integer(value), do: {:ok, value}

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, _} -> {:ok, parsed}
      :error -> :error
    end
  end

  defp parse_integer(_value), do: :error

  defp parse_positive_integer(value) do
    case parse_integer(value) do
      {:ok, parsed} when parsed > 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_non_negative_integer(value) do
    case parse_integer(value) do
      {:ok, parsed} when parsed >= 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp fetch_value(paths, default) do
    config = workflow_config()

    case resolve_config_value(config, paths) do
      :missing -> default
      value -> value
    end
  end

  defp resolve_codex_approval_policy do
    case fetch_value([["codex", "approval_policy"]], :missing) do
      :missing ->
        {:ok, @default_codex_approval_policy}

      nil ->
        {:ok, @default_codex_approval_policy}

      value when is_binary(value) ->
        approval_policy = String.trim(value)

        if approval_policy == "" do
          {:error, {:invalid_codex_approval_policy, value}}
        else
          {:ok, approval_policy}
        end

      value when is_map(value) ->
        {:ok, value}

      value ->
        {:error, {:invalid_codex_approval_policy, value}}
    end
  end

  defp resolve_codex_thread_sandbox do
    case fetch_value([["codex", "thread_sandbox"]], :missing) do
      :missing ->
        {:ok, @default_codex_thread_sandbox}

      nil ->
        {:ok, @default_codex_thread_sandbox}

      value when is_binary(value) ->
        thread_sandbox = String.trim(value)

        if thread_sandbox == "" do
          {:error, {:invalid_codex_thread_sandbox, value}}
        else
          {:ok, thread_sandbox}
        end

      value ->
        {:error, {:invalid_codex_thread_sandbox, value}}
    end
  end

  defp resolve_codex_turn_sandbox_policy(workspace) do
    case fetch_value([["codex", "turn_sandbox_policy"]], :missing) do
      :missing ->
        {:ok, default_codex_turn_sandbox_policy(workspace)}

      nil ->
        {:ok, default_codex_turn_sandbox_policy(workspace)}

      value when is_map(value) ->
        {:ok, value}

      value ->
        {:error, {:invalid_codex_turn_sandbox_policy, {:unsupported_value, value}}}
    end
  end

  defp default_codex_turn_sandbox_policy(workspace) do
    writable_root =
      if is_binary(workspace) and String.trim(workspace) != "" do
        Path.expand(workspace)
      else
        Path.expand(workspace_root())
      end

    %{
      "type" => "workspaceWrite",
      "writableRoots" => [writable_root],
      "readOnlyAccess" => %{"type" => "fullAccess"},
      "networkAccess" => false,
      "excludeTmpdirEnvVar" => false,
      "excludeSlashTmp" => false
    }
  end

  defp normalize_issue_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_tracker_kind(kind) when is_binary(kind) do
    kind
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_tracker_kind(_kind), do: nil

  defp normalize_gate_name(gate_name) when is_binary(gate_name) do
    gate_name
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_gate_name(gate_name) when is_atom(gate_name) do
    gate_name
    |> Atom.to_string()
    |> normalize_gate_name()
  end

  defp normalize_gate_name(gate_name), do: gate_name |> to_string() |> normalize_gate_name()

  defp gate_name_to_state(gate_name) when is_binary(gate_name) do
    gate_name
    |> String.trim()
    |> String.split("_", trim: true)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp gate_name_to_state(_gate_name), do: nil

  defp nested_string_map_value(value) when is_map(value) do
    value
    |> normalize_keys()
    |> Enum.reduce(%{}, fn {key, nested_value}, acc ->
      case nested_string_map_value(nested_value) do
        :omit -> acc
        normalized_value -> Map.put(acc, key, normalized_value)
      end
    end)
    |> case do
      result when map_size(result) > 0 -> result
      _ -> :omit
    end
  end

  defp nested_string_map_value(value) do
    case scalar_string_value(value) do
      :omit -> :omit
      "" -> :omit
      normalized_value -> normalized_value
    end
  end

  defp merge_gate_definitions(default_gates, configured_gates) do
    normalized_configured_gates = normalize_keys(configured_gates)

    Map.merge(default_gates, normalized_configured_gates, fn _gate_name, default_gate, configured_gate ->
      Map.merge(default_gate, configured_gate)
    end)
  end

  defp deep_merge_maps(default_map, configured_map)
       when is_map(default_map) and is_map(configured_map) do
    normalized_configured_map = normalize_keys(configured_map)

    Map.merge(default_map, normalized_configured_map, fn _key, default_value, configured_value ->
      deep_merge_maps(default_value, configured_value)
    end)
  end

  defp deep_merge_maps(_default_value, configured_value), do: configured_value

  defp keep_string_values_only(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {key, nested_value}, acc ->
      case keep_string_values_only(nested_value) do
        :omit -> acc
        normalized_value -> Map.put(acc, key, normalized_value)
      end
    end)
    |> case do
      result when map_size(result) > 0 -> result
      _ -> :omit
    end
  end

  defp keep_string_values_only(value) when is_binary(value), do: value
  defp keep_string_values_only(_value), do: :omit

  defp normalize_gate_options(gate_options, default_assignee) when is_map(gate_options) do
    state_id =
      gate_options
      |> Map.get("state_id")
      |> resolve_env_value(nil)
      |> normalize_secret_value()

    assignee =
      gate_options
      |> Map.get("assignee")
      |> resolve_env_value(default_assignee)
      |> normalize_secret_value()

    %{
      "state_id" => state_id,
      "assignee" => assignee,
      "notify" => if(is_boolean(gate_options["notify"]), do: gate_options["notify"], else: true)
    }
  end

  defp normalize_gate_options(_gate_options, default_assignee) do
    %{
      "state_id" => nil,
      "assignee" => normalize_secret_value(default_assignee),
      "notify" => true
    }
  end

  defp workflow_config do
    case current_workflow() do
      {:ok, %{config: config}} when is_map(config) ->
        normalize_keys(config)

      _ ->
        %{}
    end
  end

  defp resolve_config_value(%{} = config, paths) do
    Enum.reduce_while(paths, :missing, fn path, _acc ->
      case get_in_path(config, path) do
        :missing -> {:cont, :missing}
        value -> {:halt, value}
      end
    end)
  end

  defp get_in_path(config, path) when is_list(path) and is_map(config) do
    get_in_path(config, path, 0)
  end

  defp get_in_path(_, _), do: :missing

  defp get_in_path(config, [], _depth), do: config

  defp get_in_path(%{} = current, [segment | rest], _depth) do
    case Map.fetch(current, normalize_key(segment)) do
      {:ok, value} -> get_in_path(value, rest, 0)
      :error -> :missing
    end
  end

  defp get_in_path(_, _, _depth), do: :missing

  defp normalize_keys(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, raw_value}, normalized ->
      Map.put(normalized, normalize_key(key), normalize_keys(raw_value))
    end)
  end

  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value

  defp normalize_key(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_key(value), do: to_string(value)

  defp resolve_path_value(:missing, default), do: default
  defp resolve_path_value(nil, default), do: default

  defp resolve_path_value(value, default) when is_binary(value) do
    case normalize_path_token(value) do
      :missing ->
        default

      path ->
        path
        |> String.trim()
        |> preserve_command_name()
        |> then(fn
          "" -> default
          resolved -> resolved
        end)
    end
  end

  defp resolve_path_value(_value, default), do: default

  defp preserve_command_name(path) do
    cond do
      uri_path?(path) ->
        path

      String.contains?(path, "/") or String.contains?(path, "\\") ->
        Path.expand(path)

      true ->
        path
    end
  end

  defp uri_path?(path) do
    String.match?(to_string(path), ~r/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//)
  end

  defp resolve_env_value(:missing, fallback), do: fallback
  defp resolve_env_value(nil, fallback), do: fallback

  defp resolve_env_value(value, fallback) when is_binary(value) do
    trimmed = String.trim(value)

    case env_reference_name(trimmed) do
      {:ok, env_name} ->
        env_name
        |> System.get_env()
        |> then(fn
          nil -> fallback
          "" -> nil
          env_value -> env_value
        end)

      :error ->
        trimmed
    end
  end

  defp resolve_env_value(_value, fallback), do: fallback

  defp normalize_path_token(value) when is_binary(value) do
    trimmed = String.trim(value)

    case env_reference_name(trimmed) do
      {:ok, env_name} -> resolve_env_token(env_name)
      :error -> trimmed
    end
  end

  defp env_reference_name("$" <> env_name) do
    if String.match?(env_name, ~r/^[A-Za-z_][A-Za-z0-9_]*$/) do
      {:ok, env_name}
    else
      :error
    end
  end

  defp env_reference_name(_value), do: :error

  defp resolve_env_token(value) do
    case System.get_env(value) do
      nil -> :missing
      env_value -> env_value
    end
  end

  defp normalize_secret_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_secret_value(_value), do: nil
end
