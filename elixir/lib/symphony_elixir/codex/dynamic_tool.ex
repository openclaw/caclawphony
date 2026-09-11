defmodule SymphonyElixir.Codex.DynamicTool do
  @moduledoc """
  Executes client-side tool calls requested by Codex app-server turns.
  """

  alias SymphonyElixir.Linear.Client

  @linear_graphql_tool "linear_graphql"
  @linear_graphql_description """
  Execute a raw GraphQL query against Linear using Symphony's configured auth. Mutation and subscription documents are refused.
  """
  @linear_graphql_input_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["query"],
    "properties" => %{
      "query" => %{
        "type" => "string",
        "description" => "GraphQL query document to execute against Linear. Mutations and subscriptions are refused."
      },
      "variables" => %{
        "type" => ["object", "null"],
        "description" => "Optional GraphQL variables object.",
        "additionalProperties" => true
      }
    }
  }

  @spec execute(String.t() | nil, term(), keyword()) :: map()
  def execute(tool, arguments, opts \\ []) do
    case tool do
      @linear_graphql_tool ->
        execute_linear_graphql(arguments, opts)

      other ->
        failure_response(%{
          "error" => %{
            "message" => "Unsupported dynamic tool: #{inspect(other)}.",
            "supportedTools" => supported_tool_names()
          }
        })
    end
  end

  @spec tool_specs() :: [map()]
  def tool_specs do
    [
      %{
        "name" => @linear_graphql_tool,
        "description" => @linear_graphql_description,
        "inputSchema" => @linear_graphql_input_schema
      }
    ]
  end

  defp execute_linear_graphql(arguments, opts) do
    linear_client = Keyword.get(opts, :linear_client, &Client.graphql/3)

    with {:ok, query, variables} <- normalize_linear_graphql_arguments(arguments),
         :ok <- reject_non_query_document(query),
         {:ok, response} <- linear_client.(query, variables, []) do
      graphql_response(response)
    else
      {:error, reason} ->
        failure_response(tool_error_payload(reason))
    end
  end

  defp normalize_linear_graphql_arguments(arguments) when is_binary(arguments) do
    case String.trim(arguments) do
      "" -> {:error, :missing_query}
      query -> {:ok, query, %{}}
    end
  end

  defp normalize_linear_graphql_arguments(arguments) when is_map(arguments) do
    case normalize_query(arguments) do
      {:ok, query} ->
        case normalize_variables(arguments) do
          {:ok, variables} ->
            {:ok, query, variables}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_linear_graphql_arguments(_arguments), do: {:error, :invalid_arguments}

  defp normalize_query(arguments) do
    case Map.get(arguments, "query") || Map.get(arguments, :query) do
      query when is_binary(query) ->
        case String.trim(query) do
          "" -> {:error, :missing_query}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, :missing_query}
    end
  end

  defp normalize_variables(arguments) do
    case Map.get(arguments, "variables") || Map.get(arguments, :variables) || %{} do
      variables when is_map(variables) -> {:ok, variables}
      _ -> {:error, :invalid_variables}
    end
  end

  defp reject_non_query_document(document) do
    if query_only_document?(document) do
      :ok
    else
      {:error, :graphql_non_query_document}
    end
  end

  defp query_only_document?(document) do
    case graphql_operation_kinds(document) do
      [] ->
        false

      kinds ->
        Enum.all?(kinds, &(&1 == :query))
    end
  end

  defp graphql_operation_kinds(document) do
    case strip_graphql_noise(document) do
      {:ok, stripped} ->
        stripped
        |> scan_graphql_operations(0, 0, [])
        |> Enum.reverse()

      :unclosed_string ->
        [:unknown]
    end
  end

  defp strip_graphql_noise(document), do: strip_graphql_noise(document, [])

  defp strip_graphql_noise("", acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

  defp strip_graphql_noise(<<"\"\"\"", rest::binary>>, acc) do
    case skip_block_string(rest) do
      {:ok, after_string} -> strip_graphql_noise(after_string, [?\s | acc])
      :unclosed_string -> :unclosed_string
    end
  end

  defp strip_graphql_noise(<<"\"", rest::binary>>, acc) do
    case skip_quoted_string(rest) do
      {:ok, after_string} -> strip_graphql_noise(after_string, [?\s | acc])
      :unclosed_string -> :unclosed_string
    end
  end

  defp strip_graphql_noise(<<"#", rest::binary>>, acc) do
    strip_graphql_noise(skip_line_comment(rest), [?\s | acc])
  end

  defp strip_graphql_noise(<<char, rest::binary>>, acc) do
    strip_graphql_noise(rest, [char | acc])
  end

  defp skip_block_string(""), do: :unclosed_string
  defp skip_block_string(<<"\"\"\"", rest::binary>>), do: {:ok, rest}
  defp skip_block_string(<<_char, rest::binary>>), do: skip_block_string(rest)

  defp skip_quoted_string(""), do: :unclosed_string
  defp skip_quoted_string(<<"\"", rest::binary>>), do: {:ok, rest}
  defp skip_quoted_string(<<"\\", _char, rest::binary>>), do: skip_quoted_string(rest)
  defp skip_quoted_string(<<"\\", _rest::binary>>), do: :unclosed_string
  defp skip_quoted_string(<<_char, rest::binary>>), do: skip_quoted_string(rest)

  defp skip_line_comment(""), do: ""
  defp skip_line_comment(<<"\n", rest::binary>>), do: rest
  defp skip_line_comment(<<_char, rest::binary>>), do: skip_line_comment(rest)

  defp scan_graphql_operations("", _brace_depth, _paren_depth, acc), do: acc

  defp scan_graphql_operations(<<char, rest::binary>> = remaining, brace_depth, paren_depth, acc) do
    cond do
      whitespace?(char) ->
        scan_graphql_operations(rest, brace_depth, paren_depth, acc)

      brace_depth > 0 or paren_depth > 0 ->
        {next_brace, next_paren} = update_depths(char, brace_depth, paren_depth)
        scan_graphql_operations(rest, next_brace, next_paren, acc)

      true ->
        scan_top_level_token(remaining, brace_depth, paren_depth, acc)
    end
  end

  defp scan_top_level_token(<<char, rest::binary>> = remaining, brace_depth, paren_depth, acc) do
    cond do
      char == ?{ ->
        scan_graphql_operations(rest, brace_depth + 1, paren_depth, [:query | acc])

      identifier_start?(char) ->
        scan_top_level_identifier(remaining, brace_depth, paren_depth, acc)

      true ->
        [:unknown | acc]
    end
  end

  defp scan_top_level_identifier(remaining, brace_depth, paren_depth, acc) do
    {word, after_word} = take_identifier(remaining)

    case classify_definition(word) do
      {:operation, kind} ->
        {after_header, next_brace, next_paren} = skip_definition_header(after_word, brace_depth, paren_depth)
        scan_graphql_operations(after_header, next_brace, next_paren, [kind | acc])

      :fragment ->
        {after_header, next_brace, next_paren} = skip_definition_header(after_word, brace_depth, paren_depth)
        scan_graphql_operations(after_header, next_brace, next_paren, acc)

      :unknown ->
        [:unknown | acc]
    end
  end

  defp classify_definition("query"), do: {:operation, :query}
  defp classify_definition("mutation"), do: {:operation, :mutation}
  defp classify_definition("subscription"), do: {:operation, :subscription}
  defp classify_definition("fragment"), do: :fragment
  defp classify_definition(_word), do: :unknown

  defp skip_definition_header("", brace_depth, paren_depth), do: {"", brace_depth, paren_depth}

  defp skip_definition_header(<<char, rest::binary>>, brace_depth, paren_depth) do
    if brace_depth == 0 and paren_depth == 0 and char == ?{ do
      {rest, 1, 0}
    else
      {next_brace, next_paren} = update_depths(char, brace_depth, paren_depth)
      skip_definition_header(rest, next_brace, next_paren)
    end
  end

  defp update_depths(?{, brace_depth, paren_depth), do: {brace_depth + 1, paren_depth}
  defp update_depths(?}, brace_depth, paren_depth), do: {max(brace_depth - 1, 0), paren_depth}
  defp update_depths(?(, brace_depth, paren_depth), do: {brace_depth, paren_depth + 1}
  defp update_depths(?), brace_depth, paren_depth), do: {brace_depth, max(paren_depth - 1, 0)}
  defp update_depths(_char, brace_depth, paren_depth), do: {brace_depth, paren_depth}

  defp take_identifier(<<char, rest::binary>>) do
    take_identifier_chars(rest, <<char>>)
  end

  defp take_identifier_chars(<<char, rest::binary>>, acc) when char in ?0..?9 or char in ?A..?Z or char in ?a..?z or char == ?_ do
    take_identifier_chars(rest, acc <> <<char>>)
  end

  defp take_identifier_chars(rest, acc), do: {acc, rest}

  defp whitespace?(char) when char in [?\s, ?\t, ?\n, ?\r, ?,, 0xFEFF], do: true
  defp whitespace?(_char), do: false

  defp identifier_start?(char) when char in ?A..?Z or char in ?a..?z or char == ?_, do: true
  defp identifier_start?(_char), do: false

  defp graphql_response(response) do
    success =
      case response do
        %{"errors" => errors} when is_list(errors) and errors != [] -> false
        %{errors: errors} when is_list(errors) and errors != [] -> false
        _ -> true
      end

    %{
      "success" => success,
      "contentItems" => [
        %{
          "type" => "inputText",
          "text" => encode_payload(response)
        }
      ]
    }
  end

  defp failure_response(payload) do
    %{
      "success" => false,
      "contentItems" => [
        %{
          "type" => "inputText",
          "text" => encode_payload(payload)
        }
      ]
    }
  end

  defp encode_payload(payload) when is_map(payload) or is_list(payload) do
    Jason.encode!(payload, pretty: true)
  end

  defp encode_payload(payload), do: inspect(payload)

  defp tool_error_payload(:missing_query) do
    %{
      "error" => %{
        "message" => "`linear_graphql` requires a non-empty `query` string."
      }
    }
  end

  defp tool_error_payload(:invalid_arguments) do
    %{
      "error" => %{
        "message" => "`linear_graphql` expects either a GraphQL query string or an object with `query` and optional `variables`."
      }
    }
  end

  defp tool_error_payload(:invalid_variables) do
    %{
      "error" => %{
        "message" => "`linear_graphql.variables` must be a JSON object when provided."
      }
    }
  end

  defp tool_error_payload(:graphql_non_query_document) do
    %{
      "error" => %{
        "message" => "`linear_graphql` only accepts GraphQL query documents. Mutation and subscription operations are refused."
      }
    }
  end

  defp tool_error_payload(:missing_linear_api_token) do
    %{
      "error" => %{
        "message" => "Symphony is missing Linear auth. Set `linear.api_key` in `WORKFLOW.md` or export `LINEAR_API_KEY`."
      }
    }
  end

  defp tool_error_payload({:linear_api_status, status}) do
    %{
      "error" => %{
        "message" => "Linear GraphQL request failed with HTTP #{status}.",
        "status" => status
      }
    }
  end

  defp tool_error_payload({:linear_api_request, reason}) do
    %{
      "error" => %{
        "message" => "Linear GraphQL request failed before receiving a successful response.",
        "reason" => inspect(reason)
      }
    }
  end

  defp tool_error_payload(reason) do
    %{
      "error" => %{
        "message" => "Linear GraphQL tool execution failed.",
        "reason" => inspect(reason)
      }
    }
  end

  defp supported_tool_names do
    Enum.map(tool_specs(), & &1["name"])
  end
end
