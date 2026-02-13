# _rlm-common.sh — Shared code for bin/rlm and bin/llm
# shellcheck shell=bash
# Sourced by both scripts. Do NOT add set -euo pipefail or a shebang here.

# --- API Key -----------------------------------------------------------------

if [ -z "${OPENROUTER_API_KEY:-}" ]; then
	if [ -f /etc/rlm/api-key ]; then
		OPENROUTER_API_KEY="$(cat /etc/rlm/api-key)"
		export OPENROUTER_API_KEY
	fi
fi
# Note: API key is not required for mock mode (_RLM_MOCK_DIR)

if [ -z "${_RLM_MOCK_DIR:-}" ] && [ -z "${OPENROUTER_API_KEY:-}" ]; then
	echo "rlm: no API key found. Set OPENROUTER_API_KEY or create /etc/rlm/api-key" >&2
	exit 1
fi

# --- call_llm ----------------------------------------------------------------

call_llm() {
	# Call the LLM and print the response to stdout.
	#
	# Arguments:
	#   $1 — iteration number (1-based), used to select the mock response file
	#   $2 — (optional) system prompt override. Defaults to $SYSTEM_PROMPT.
	#   stdin — JSON messages array (from build_messages)
	#
	# When _RLM_MOCK_DIR is set, reads from $_RLM_MOCK_DIR/{n}.md instead of
	# calling the API. This is the testing seam for unit/integration tests.

	local iteration="$1"
	local sys_prompt="${2:-$SYSTEM_PROMPT}"

	if [ -n "${_RLM_MOCK_DIR:-}" ]; then
		local mock_file="$_RLM_MOCK_DIR/$iteration.md"
		if [ ! -f "$mock_file" ]; then
			echo "rlm: mock file not found: $mock_file" >&2
			return 1
		fi
		cat "$mock_file"
		return 0
	fi

	local messages_json
	messages_json="$(cat)"

	local request_body
	request_body=$(jq -n \
		--arg model "$RLM_MODEL" \
		--argjson max_tokens "$RLM_MAX_TOKENS" \
		--arg system "$sys_prompt" \
		--argjson messages "$messages_json" \
		'{
			model: $model,
			max_tokens: $max_tokens,
			tools: [],
			tool_choice: "none",
			messages: ([{role: "system", content: $system}] + $messages)
		}')

	# Retry loop: some models (Gemini) intermittently fail with
	# MALFORMED_FUNCTION_CALL or return empty content. Retry up to 3 times.
	local max_retries="${_RLM_MAX_API_RETRIES:-3}"
	local attempt

	for ((attempt=1; attempt<=max_retries; attempt++)); do
		local http_code
		local response_file
		response_file="$(mktemp)"
		local header_file
		header_file="$(mktemp)"

		http_code=$(curl -s -w '%{http_code}' \
			-o "$response_file" \
			-D "$header_file" \
			-X POST \
			-H "Content-Type: application/json" \
			-H "Authorization: Bearer $OPENROUTER_API_KEY" \
			--max-time 240 \
			--retry 0 \
			"https://openrouter.ai/api/v1/chat/completions" \
			-d "$request_body" 2>/dev/null) || {
			local curl_exit=$?
			echo "rlm: curl failed with exit code $curl_exit (attempt $attempt/$max_retries)" >&2
			rm -f "$response_file" "$header_file"
			if [ "$attempt" -lt "$max_retries" ]; then sleep 2; continue; fi
			return 1
		}

		if [ "$http_code" -eq 429 ]; then
			echo "rlm: rate limited (HTTP 429, attempt $attempt/$max_retries)" >&2
			rm -f "$response_file" "$header_file"
			if [ "$attempt" -lt "$max_retries" ]; then sleep 5; continue; fi
			return 1
		fi

		if [ "$http_code" -ne 200 ]; then
			echo "rlm: API error (HTTP $http_code, attempt $attempt/$max_retries)" >&2
			rm -f "$response_file" "$header_file"
			if [ "$attempt" -lt "$max_retries" ]; then sleep 2; continue; fi
			return 1
		fi

		local content
		content=$(jq -r '.choices[0].message.content // empty' "$response_file" 2>/dev/null) || {
			echo "rlm: failed to parse API response (attempt $attempt/$max_retries)" >&2
			rm -f "$response_file" "$header_file"
			if [ "$attempt" -lt "$max_retries" ]; then sleep 2; continue; fi
			return 1
		}

		if [ -z "$content" ]; then
			# Gemini MALFORMED_FUNCTION_CALL workaround
			local finish_reason
			finish_reason=$(jq -r '.choices[0].native_finish_reason // "unknown"' "$response_file" 2>/dev/null)
			echo "rlm: empty content (finish=$finish_reason, attempt $attempt/$max_retries)" >&2
			rm -f "$response_file" "$header_file"
			if [ "$attempt" -lt "$max_retries" ]; then sleep 2; continue; fi
			return 1
		fi

		rm -f "$response_file" "$header_file"
		printf '%s' "$content"
		return 0
	done

	return 1
}
