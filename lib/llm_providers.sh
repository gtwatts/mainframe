#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/llm_providers.sh - Unified LLM Provider Interface
# =============================================================================
# Description: Pure bash interface for OpenAI, Anthropic, and Ollama LLM APIs.
#              Provides consistent chat, completion, and embedding operations
#              across providers with automatic retry, rate limiting, and
#              USOP-compliant JSON output.
#
# Supported Providers:
#   - openai    (GPT-4, GPT-3.5, embeddings)
#   - anthropic (Claude models via Messages API)
#   - ollama    (Local models: llama2, mistral, etc.)
#
# Environment Variables:
#   OPENAI_API_KEY      API key for OpenAI
#   ANTHROPIC_API_KEY   API key for Anthropic
#   OLLAMA_HOST         Ollama server URL (default: http://localhost:11434)
#
# Version: 1.0.0
# Requires: Bash 4.0+, curl
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_LLM_PROVIDERS_LOADED:-}" ]] && return 0
readonly _MAINFRAME_LLM_PROVIDERS_LOADED=1

# =============================================================================
# CONSTANTS AND DEFAULTS
# =============================================================================

readonly LLM_VERSION="1.0.0"

# Default provider and model
LLM_DEFAULT_PROVIDER="${LLM_DEFAULT_PROVIDER:-openai}"
LLM_DEFAULT_MODEL="${LLM_DEFAULT_MODEL:-gpt-4}"

# Provider endpoints
readonly LLM_OPENAI_API_URL="https://api.openai.com/v1"
readonly LLM_ANTHROPIC_API_URL="https://api.anthropic.com/v1"
LLM_OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

# Default settings
readonly LLM_DEFAULT_TIMEOUT=120
readonly LLM_DEFAULT_MAX_RETRIES=3
readonly LLM_DEFAULT_RETRY_DELAY=1
readonly LLM_DEFAULT_MAX_TOKENS=4096
readonly LLM_DEFAULT_TEMPERATURE=0.7

# Rate limit detection patterns
readonly LLM_RATE_LIMIT_CODES="429 529"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

_llm_log() {
    _mainframe_log "llm" "$@"
}

# Check if curl is available
_llm_require_curl() {
    if ! command -v curl &>/dev/null; then
        _llm_log "error" "curl is required but not found"
        return 1
    fi
    return 0
}

# Validate JSON input
_llm_validate_json() {
    local input="$1"
    if ! json_valid "$input" 2>/dev/null; then
        _llm_log "error" "Invalid JSON input"
        return 1
    fi
    return 0
}

# Build USOP success response
# Usage: _llm_success "content" "model" "prompt_tokens" "completion_tokens"
_llm_success() {
    local content="$1"
    local model="${2:-unknown}"
    local prompt_tokens="${3:-0}"
    local completion_tokens="${4:-0}"

    local escaped_content
    json_escape_v escaped_content "$content"

    json_object \
        "ok:bool=true" \
        "data:raw={\"content\":\"${escaped_content}\",\"model\":\"${model}\",\"usage\":{\"prompt_tokens\":${prompt_tokens},\"completion_tokens\":${completion_tokens}}}"
}

# Build USOP error response
# Usage: _llm_error "error_message" "error_code"
_llm_error() {
    local message="$1"
    local code="${2:-500}"

    local escaped_msg
    json_escape_v escaped_msg "$message"

    json_object \
        "ok:bool=false" \
        "error=${escaped_msg}" \
        "code:number=${code}"
}

# Build USOP success response for embeddings
# Usage: _llm_embed_success "embedding_json_array" "model" "tokens"
_llm_embed_success() {
    local embedding="$1"
    local model="${2:-unknown}"
    local tokens="${3:-0}"

    printf '{"ok":true,"data":{"embedding":%s,"model":"%s","usage":{"total_tokens":%d}}}' \
        "$embedding" "$model" "$tokens"
}

# Execute HTTP request with retry and rate limit handling
# Usage: _llm_http_request "method" "url" "body" "header1" "header2" ...
_llm_http_request() {
    local method="$1"
    local url="$2"
    local body="$3"
    shift 3
    local headers=("$@")

    local max_retries="${LLM_MAX_RETRIES:-$LLM_DEFAULT_MAX_RETRIES}"
    local retry_delay="${LLM_RETRY_DELAY:-$LLM_DEFAULT_RETRY_DELAY}"
    local timeout="${LLM_TIMEOUT:-$LLM_DEFAULT_TIMEOUT}"

    local attempt=1
    local response http_code response_body
    local tmp_file
    tmp_file=$(mktemp)

    while [[ $attempt -le $max_retries ]]; do
        # Build curl command
        local curl_args=(
            -s
            -w "\n%{http_code}"
            -X "$method"
            --max-time "$timeout"
            --connect-timeout 10
        )

        # Add headers
        for header in "${headers[@]}"; do
            [[ -n "$header" ]] && curl_args+=(-H "$header")
        done

        # Add body for POST/PUT
        if [[ -n "$body" ]]; then
            curl_args+=(-d "$body")
        fi

        curl_args+=("$url")

        # Execute request
        response=$(curl "${curl_args[@]}" 2>/dev/null)

        # Extract HTTP code (last line)
        http_code=$(echo "$response" | tail -n1)
        response_body=$(echo "$response" | sed '$d')

        # Check for success (2xx)
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            rm -f "$tmp_file"
            printf '%s' "$response_body"
            return 0
        fi

        # Check for rate limiting
        if [[ " $LLM_RATE_LIMIT_CODES " =~ " $http_code " ]]; then
            _llm_log "warn" "Rate limited (HTTP $http_code), attempt $attempt/$max_retries"

            # Extract retry-after header if present
            local wait_time=$retry_delay
            if [[ "$response_body" =~ \"retry_after\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                wait_time="${BASH_REMATCH[1]}"
            fi

            # Exponential backoff with jitter
            local power=1
            for ((i = 1; i < attempt; i++)); do
                power=$((power * 2))
            done
            wait_time=$((wait_time * power))

            # Add jitter (0-25%)
            local jitter=$((wait_time / 4))
            if [[ $jitter -gt 0 ]]; then
                wait_time=$((wait_time + RANDOM % jitter))
            fi

            sleep "$wait_time"
            ((attempt++))
            continue
        fi

        # Non-retryable error
        rm -f "$tmp_file"
        _llm_log "error" "HTTP request failed: $http_code"
        printf '%s' "$response_body"
        return 1
    done

    rm -f "$tmp_file"
    _llm_log "error" "Max retries ($max_retries) exceeded"
    printf '%s' "$response_body"
    return 1
}

# Parse provider response for content
# Usage: _llm_parse_content "provider" "response_json"
_llm_parse_content() {
    local provider="$1"
    local response="$2"

    case "$provider" in
        openai)
            # OpenAI: .choices[0].message.content
            if [[ "$response" =~ \"content\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                printf '%s' "${BASH_REMATCH[1]}"
            elif [[ "$response" =~ \"content\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
                # Handle escaped content
                printf '%s' "${BASH_REMATCH[1]}"
            fi
            ;;
        anthropic)
            # Anthropic: .content[0].text
            if [[ "$response" =~ \"text\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                printf '%s' "${BASH_REMATCH[1]}"
            elif [[ "$response" =~ \"text\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
                printf '%s' "${BASH_REMATCH[1]}"
            fi
            ;;
        ollama)
            # Ollama: .message.content or .response
            if [[ "$response" =~ \"content\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                printf '%s' "${BASH_REMATCH[1]}"
            elif [[ "$response" =~ \"response\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
                printf '%s' "${BASH_REMATCH[1]}"
            fi
            ;;
    esac
}

# Parse token usage from response
# Usage: _llm_parse_usage "provider" "response_json" "field"
# Fields: prompt_tokens, completion_tokens, total_tokens
_llm_parse_usage() {
    local provider="$1"
    local response="$2"
    local field="$3"

    case "$provider" in
        openai|anthropic)
            if [[ "$response" =~ \"${field}\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                printf '%s' "${BASH_REMATCH[1]}"
            else
                printf '0'
            fi
            ;;
        ollama)
            # Ollama uses different field names
            local ollama_field
            case "$field" in
                prompt_tokens) ollama_field="prompt_eval_count" ;;
                completion_tokens) ollama_field="eval_count" ;;
                total_tokens) ollama_field="total_count" ;;
                *) ollama_field="$field" ;;
            esac
            if [[ "$response" =~ \"${ollama_field}\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
                printf '%s' "${BASH_REMATCH[1]}"
            else
                printf '0'
            fi
            ;;
    esac
}

# Parse model from response
# Usage: _llm_parse_model "provider" "response_json"
_llm_parse_model() {
    local provider="$1"
    local response="$2"

    if [[ "$response" =~ \"model\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf 'unknown'
    fi
}

# Check for API error in response
# Usage: _llm_check_error "provider" "response_json"
# Returns: 0 if no error, 1 if error (prints error message)
_llm_check_error() {
    local provider="$1"
    local response="$2"

    # Common error patterns
    if [[ "$response" =~ \"error\"[[:space:]]*:[[:space:]]*\{[[:space:]]*\"message\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 1
    fi

    if [[ "$response" =~ \"error\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 1
    fi

    # Anthropic-specific
    if [[ "$response" =~ \"type\"[[:space:]]*:[[:space:]]*\"error\" ]]; then
        if [[ "$response" =~ \"message\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return 1
        fi
    fi

    return 0
}

# =============================================================================
# CONFIGURATION FUNCTIONS
# =============================================================================

# Set default LLM provider
# Usage: llm_set_provider "openai"
llm_set_provider() {
    local provider="$1"

    case "$provider" in
        openai|anthropic|ollama)
            LLM_DEFAULT_PROVIDER="$provider"
            _llm_log "debug" "Default provider set to: $provider"
            return 0
            ;;
        *)
            _llm_log "error" "Unknown provider: $provider (valid: openai, anthropic, ollama)"
            return 1
            ;;
    esac
}

# Set default model
# Usage: llm_set_model "gpt-4-turbo"
llm_set_model() {
    local model="$1"

    if [[ -z "$model" ]]; then
        _llm_log "error" "Model name required"
        return 1
    fi

    LLM_DEFAULT_MODEL="$model"
    _llm_log "debug" "Default model set to: $model"
    return 0
}

# Get current configuration as JSON
# Usage: llm_config_get
llm_config_get() {
    local openai_key_status="not_set"
    local anthropic_key_status="not_set"

    [[ -n "${OPENAI_API_KEY:-}" ]] && openai_key_status="set"
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && anthropic_key_status="set"

    json_object \
        "provider=${LLM_DEFAULT_PROVIDER}" \
        "model=${LLM_DEFAULT_MODEL}" \
        "ollama_host=${LLM_OLLAMA_HOST}" \
        "timeout:number=${LLM_TIMEOUT:-$LLM_DEFAULT_TIMEOUT}" \
        "max_retries:number=${LLM_MAX_RETRIES:-$LLM_DEFAULT_MAX_RETRIES}" \
        "openai_api_key=${openai_key_status}" \
        "anthropic_api_key=${anthropic_key_status}"
}

# =============================================================================
# GENERIC INTERFACE FUNCTIONS
# =============================================================================

# Send chat completion request
# Usage: llm_chat "prompt" [--provider openai] [--model gpt-4] [--max-tokens 1024]
llm_chat() {
    local prompt=""
    local provider="${LLM_DEFAULT_PROVIDER}"
    local model="${LLM_DEFAULT_MODEL}"
    local max_tokens="${LLM_DEFAULT_MAX_TOKENS}"
    local temperature="${LLM_DEFAULT_TEMPERATURE}"
    local system_prompt=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider)
                provider="$2"
                shift 2
                ;;
            --model)
                model="$2"
                shift 2
                ;;
            --max-tokens)
                max_tokens="$2"
                shift 2
                ;;
            --temperature)
                temperature="$2"
                shift 2
                ;;
            --system)
                system_prompt="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                _llm_log "error" "Unknown option: $1"
                _llm_error "Unknown option: $1" 400
                return 1
                ;;
            *)
                prompt="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$prompt" ]]; then
        _llm_error "Prompt required" 400
        return 1
    fi

    # Route to provider-specific function
    case "$provider" in
        openai)
            local messages
            if [[ -n "$system_prompt" ]]; then
                local esc_system esc_prompt
                json_escape_v esc_system "$system_prompt"
                json_escape_v esc_prompt "$prompt"
                messages="[{\"role\":\"system\",\"content\":\"${esc_system}\"},{\"role\":\"user\",\"content\":\"${esc_prompt}\"}]"
            else
                local esc_prompt
                json_escape_v esc_prompt "$prompt"
                messages="[{\"role\":\"user\",\"content\":\"${esc_prompt}\"}]"
            fi
            llm_openai_chat "$messages" --model "$model" --max-tokens "$max_tokens" --temperature "$temperature"
            ;;
        anthropic)
            local messages
            local esc_prompt
            json_escape_v esc_prompt "$prompt"
            messages="[{\"role\":\"user\",\"content\":\"${esc_prompt}\"}]"
            if [[ -n "$system_prompt" ]]; then
                llm_anthropic_chat "$messages" --model "$model" --max-tokens "$max_tokens" --system "$system_prompt"
            else
                llm_anthropic_chat "$messages" --model "$model" --max-tokens "$max_tokens"
            fi
            ;;
        ollama)
            local messages
            if [[ -n "$system_prompt" ]]; then
                local esc_system esc_prompt
                json_escape_v esc_system "$system_prompt"
                json_escape_v esc_prompt "$prompt"
                messages="[{\"role\":\"system\",\"content\":\"${esc_system}\"},{\"role\":\"user\",\"content\":\"${esc_prompt}\"}]"
            else
                local esc_prompt
                json_escape_v esc_prompt "$prompt"
                messages="[{\"role\":\"user\",\"content\":\"${esc_prompt}\"}]"
            fi
            llm_ollama_chat "$messages" --model "$model"
            ;;
        *)
            _llm_error "Unknown provider: $provider" 400
            return 1
            ;;
    esac
}

# Send text completion request (legacy API)
# Usage: llm_complete "prompt" [--provider anthropic]
llm_complete() {
    local prompt=""
    local provider="${LLM_DEFAULT_PROVIDER}"
    local model=""
    local max_tokens="${LLM_DEFAULT_MAX_TOKENS}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider)
                provider="$2"
                shift 2
                ;;
            --model)
                model="$2"
                shift 2
                ;;
            --max-tokens)
                max_tokens="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                _llm_log "error" "Unknown option: $1"
                return 1
                ;;
            *)
                prompt="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$prompt" ]]; then
        _llm_error "Prompt required" 400
        return 1
    fi

    case "$provider" in
        openai)
            llm_openai_complete "$prompt" --model "${model:-gpt-3.5-turbo-instruct}" --max-tokens "$max_tokens"
            ;;
        anthropic)
            llm_anthropic_complete "$prompt" --model "${model:-claude-instant-1.2}" --max-tokens "$max_tokens"
            ;;
        ollama)
            llm_ollama_generate "$prompt" --model "${model:-llama2}"
            ;;
        *)
            _llm_error "Unknown provider: $provider" 400
            return 1
            ;;
    esac
}

# Generate embeddings
# Usage: llm_embed "text" [--provider openai]
llm_embed() {
    local text=""
    local provider="${LLM_DEFAULT_PROVIDER}"
    local model=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --provider)
                provider="$2"
                shift 2
                ;;
            --model)
                model="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            -*)
                _llm_log "error" "Unknown option: $1"
                return 1
                ;;
            *)
                text="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$text" ]]; then
        _llm_error "Text required" 400
        return 1
    fi

    case "$provider" in
        openai)
            llm_openai_embed "$text" --model "${model:-text-embedding-ada-002}"
            ;;
        ollama)
            llm_ollama_embed "$text" --model "${model:-nomic-embed-text}"
            ;;
        anthropic)
            _llm_error "Anthropic does not provide embedding API" 400
            return 1
            ;;
        *)
            _llm_error "Unknown provider: $provider" 400
            return 1
            ;;
    esac
}

# =============================================================================
# OPENAI FUNCTIONS
# =============================================================================

# OpenAI chat completion
# Usage: llm_openai_chat "messages_json" [--model gpt-4] [--max-tokens 1024]
llm_openai_chat() {
    local messages="$1"
    shift
    local model="${LLM_DEFAULT_MODEL}"
    local max_tokens="${LLM_DEFAULT_MAX_TOKENS}"
    local temperature="${LLM_DEFAULT_TEMPERATURE}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model) model="$2"; shift 2 ;;
            --max-tokens) max_tokens="$2"; shift 2 ;;
            --temperature) temperature="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    _llm_require_curl || return 1

    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        _llm_error "OPENAI_API_KEY not set" 401
        return 1
    fi

    local request_body
    request_body=$(printf '{"model":"%s","messages":%s,"max_tokens":%d,"temperature":%s}' \
        "$model" "$messages" "$max_tokens" "$temperature")

    local response
    response=$(_llm_http_request "POST" "${LLM_OPENAI_API_URL}/chat/completions" "$request_body" \
        "Content-Type: application/json" \
        "Authorization: Bearer ${OPENAI_API_KEY}")

    local rc=$?

    # Check for API error
    local error_msg
    if error_msg=$(_llm_check_error "openai" "$response"); then
        # No error, parse response
        local content resp_model prompt_tokens completion_tokens
        content=$(_llm_parse_content "openai" "$response")
        resp_model=$(_llm_parse_model "openai" "$response")
        prompt_tokens=$(_llm_parse_usage "openai" "$response" "prompt_tokens")
        completion_tokens=$(_llm_parse_usage "openai" "$response" "completion_tokens")

        _llm_success "$content" "$resp_model" "$prompt_tokens" "$completion_tokens"
        return 0
    else
        _llm_error "$error_msg" 500
        return 1
    fi
}

# OpenAI legacy completion
# Usage: llm_openai_complete "prompt" [--model gpt-3.5-turbo-instruct]
llm_openai_complete() {
    local prompt="$1"
    shift
    local model="gpt-3.5-turbo-instruct"
    local max_tokens="${LLM_DEFAULT_MAX_TOKENS}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model) model="$2"; shift 2 ;;
            --max-tokens) max_tokens="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    _llm_require_curl || return 1

    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        _llm_error "OPENAI_API_KEY not set" 401
        return 1
    fi

    local escaped_prompt
    json_escape_v escaped_prompt "$prompt"

    local request_body
    request_body=$(printf '{"model":"%s","prompt":"%s","max_tokens":%d}' \
        "$model" "$escaped_prompt" "$max_tokens")

    local response
    response=$(_llm_http_request "POST" "${LLM_OPENAI_API_URL}/completions" "$request_body" \
        "Content-Type: application/json" \
        "Authorization: Bearer ${OPENAI_API_KEY}")

    local error_msg
    if error_msg=$(_llm_check_error "openai" "$response"); then
        # Parse completion response - .choices[0].text
        local content resp_model prompt_tokens completion_tokens
        if [[ "$response" =~ \"text\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
            content="${BASH_REMATCH[1]}"
        fi
        resp_model=$(_llm_parse_model "openai" "$response")
        prompt_tokens=$(_llm_parse_usage "openai" "$response" "prompt_tokens")
        completion_tokens=$(_llm_parse_usage "openai" "$response" "completion_tokens")

        _llm_success "$content" "$resp_model" "$prompt_tokens" "$completion_tokens"
        return 0
    else
        _llm_error "$error_msg" 500
        return 1
    fi
}

# OpenAI embeddings
# Usage: llm_openai_embed "text" [--model text-embedding-ada-002]
llm_openai_embed() {
    local text="$1"
    shift
    local model="text-embedding-ada-002"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model) model="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    _llm_require_curl || return 1

    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        _llm_error "OPENAI_API_KEY not set" 401
        return 1
    fi

    local escaped_text
    json_escape_v escaped_text "$text"

    local request_body
    request_body=$(printf '{"model":"%s","input":"%s"}' "$model" "$escaped_text")

    local response
    response=$(_llm_http_request "POST" "${LLM_OPENAI_API_URL}/embeddings" "$request_body" \
        "Content-Type: application/json" \
        "Authorization: Bearer ${OPENAI_API_KEY}")

    local error_msg
    if error_msg=$(_llm_check_error "openai" "$response"); then
        # Extract embedding array - .data[0].embedding
        local embedding tokens resp_model
        if [[ "$response" =~ \"embedding\"[[:space:]]*:[[:space:]]*(\[[^]]+\]) ]]; then
            embedding="${BASH_REMATCH[1]}"
        else
            embedding="[]"
        fi
        tokens=$(_llm_parse_usage "openai" "$response" "total_tokens")
        resp_model=$(_llm_parse_model "openai" "$response")

        _llm_embed_success "$embedding" "$resp_model" "$tokens"
        return 0
    else
        _llm_error "$error_msg" 500
        return 1
    fi
}

# List OpenAI models
# Usage: llm_openai_models
llm_openai_models() {
    _llm_require_curl || return 1

    if [[ -z "${OPENAI_API_KEY:-}" ]]; then
        _llm_error "OPENAI_API_KEY not set" 401
        return 1
    fi

    local response
    response=$(_llm_http_request "GET" "${LLM_OPENAI_API_URL}/models" "" \
        "Authorization: Bearer ${OPENAI_API_KEY}")

    local error_msg
    if error_msg=$(_llm_check_error "openai" "$response"); then
        printf '{"ok":true,"data":%s}' "$response"
        return 0
    else
        _llm_error "$error_msg" 500
        return 1
    fi
}

# =============================================================================
# ANTHROPIC FUNCTIONS
# =============================================================================

# Anthropic Messages API chat
# Usage: llm_anthropic_chat "messages_json" [--model claude-3-opus] [--max-tokens 1024]
llm_anthropic_chat() {
    local messages="$1"
    shift
    local model="claude-3-sonnet-20240229"
    local max_tokens="${LLM_DEFAULT_MAX_TOKENS}"
    local system_prompt=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model) model="$2"; shift 2 ;;
            --max-tokens) max_tokens="$2"; shift 2 ;;
            --system) system_prompt="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    _llm_require_curl || return 1

    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        _llm_error "ANTHROPIC_API_KEY not set" 401
        return 1
    fi

    local request_body
    if [[ -n "$system_prompt" ]]; then
        local escaped_system
        json_escape_v escaped_system "$system_prompt"
        request_body=$(printf '{"model":"%s","max_tokens":%d,"system":"%s","messages":%s}' \
            "$model" "$max_tokens" "$escaped_system" "$messages")
    else
        request_body=$(printf '{"model":"%s","max_tokens":%d,"messages":%s}' \
            "$model" "$max_tokens" "$messages")
    fi

    local response
    response=$(_llm_http_request "POST" "${LLM_ANTHROPIC_API_URL}/messages" "$request_body" \
        "Content-Type: application/json" \
        "x-api-key: ${ANTHROPIC_API_KEY}" \
        "anthropic-version: 2023-06-01")

    local error_msg
    if error_msg=$(_llm_check_error "anthropic" "$response"); then
        local content resp_model input_tokens output_tokens
        content=$(_llm_parse_content "anthropic" "$response")
        resp_model=$(_llm_parse_model "anthropic" "$response")
        input_tokens=$(_llm_parse_usage "anthropic" "$response" "input_tokens")
        output_tokens=$(_llm_parse_usage "anthropic" "$response" "output_tokens")

        _llm_success "$content" "$resp_model" "$input_tokens" "$output_tokens"
        return 0
    else
        _llm_error "$error_msg" 500
        return 1
    fi
}

# Anthropic legacy completion (deprecated but supported)
# Usage: llm_anthropic_complete "prompt" [--model claude-instant-1.2]
llm_anthropic_complete() {
    local prompt="$1"
    shift
    local model="claude-instant-1.2"
    local max_tokens="${LLM_DEFAULT_MAX_TOKENS}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model) model="$2"; shift 2 ;;
            --max-tokens) max_tokens="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    _llm_require_curl || return 1

    if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
        _llm_error "ANTHROPIC_API_KEY not set" 401
        return 1
    fi

    # Use Messages API with single user message
    local escaped_prompt
    json_escape_v escaped_prompt "$prompt"

    local messages
    messages="[{\"role\":\"user\",\"content\":\"${escaped_prompt}\"}]"

    llm_anthropic_chat "$messages" --model "$model" --max-tokens "$max_tokens"
}

# List Anthropic models (static list as API doesn't provide this)
# Usage: llm_anthropic_models
llm_anthropic_models() {
    local models='["claude-3-opus-20240229","claude-3-sonnet-20240229","claude-3-haiku-20240307","claude-2.1","claude-2.0","claude-instant-1.2"]'
    printf '{"ok":true,"data":{"models":%s}}' "$models"
}

# =============================================================================
# OLLAMA FUNCTIONS
# =============================================================================

# Ollama chat completion
# Usage: llm_ollama_chat "messages_json" [--model llama2]
llm_ollama_chat() {
    local messages="$1"
    shift
    local model="llama2"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model) model="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    _llm_require_curl || return 1

    local request_body
    request_body=$(printf '{"model":"%s","messages":%s,"stream":false}' "$model" "$messages")

    local response
    response=$(_llm_http_request "POST" "${LLM_OLLAMA_HOST}/api/chat" "$request_body" \
        "Content-Type: application/json")

    local error_msg
    if error_msg=$(_llm_check_error "ollama" "$response"); then
        local content resp_model prompt_tokens completion_tokens
        content=$(_llm_parse_content "ollama" "$response")
        resp_model=$(_llm_parse_model "ollama" "$response")
        prompt_tokens=$(_llm_parse_usage "ollama" "$response" "prompt_tokens")
        completion_tokens=$(_llm_parse_usage "ollama" "$response" "completion_tokens")

        _llm_success "$content" "$resp_model" "$prompt_tokens" "$completion_tokens"
        return 0
    else
        _llm_error "$error_msg" 500
        return 1
    fi
}

# Ollama generate (text completion)
# Usage: llm_ollama_generate "prompt" [--model llama2]
llm_ollama_generate() {
    local prompt="$1"
    shift
    local model="llama2"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model) model="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    _llm_require_curl || return 1

    local escaped_prompt
    json_escape_v escaped_prompt "$prompt"

    local request_body
    request_body=$(printf '{"model":"%s","prompt":"%s","stream":false}' "$model" "$escaped_prompt")

    local response
    response=$(_llm_http_request "POST" "${LLM_OLLAMA_HOST}/api/generate" "$request_body" \
        "Content-Type: application/json")

    local error_msg
    if error_msg=$(_llm_check_error "ollama" "$response"); then
        local content resp_model prompt_tokens completion_tokens
        content=$(_llm_parse_content "ollama" "$response")
        resp_model=$(_llm_parse_model "ollama" "$response")
        prompt_tokens=$(_llm_parse_usage "ollama" "$response" "prompt_tokens")
        completion_tokens=$(_llm_parse_usage "ollama" "$response" "completion_tokens")

        _llm_success "$content" "$resp_model" "$prompt_tokens" "$completion_tokens"
        return 0
    else
        _llm_error "$error_msg" 500
        return 1
    fi
}

# Ollama embeddings
# Usage: llm_ollama_embed "text" [--model nomic-embed-text]
llm_ollama_embed() {
    local text="$1"
    shift
    local model="nomic-embed-text"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model) model="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    _llm_require_curl || return 1

    local escaped_text
    json_escape_v escaped_text "$text"

    local request_body
    request_body=$(printf '{"model":"%s","prompt":"%s"}' "$model" "$escaped_text")

    local response
    response=$(_llm_http_request "POST" "${LLM_OLLAMA_HOST}/api/embeddings" "$request_body" \
        "Content-Type: application/json")

    local error_msg
    if error_msg=$(_llm_check_error "ollama" "$response"); then
        # Extract embedding array
        local embedding
        if [[ "$response" =~ \"embedding\"[[:space:]]*:[[:space:]]*(\[[^]]+\]) ]]; then
            embedding="${BASH_REMATCH[1]}"
        else
            embedding="[]"
        fi

        _llm_embed_success "$embedding" "$model" "0"
        return 0
    else
        _llm_error "$error_msg" 500
        return 1
    fi
}

# List local Ollama models
# Usage: llm_ollama_list
llm_ollama_list() {
    _llm_require_curl || return 1

    local response
    response=$(_llm_http_request "GET" "${LLM_OLLAMA_HOST}/api/tags" "" \
        "Content-Type: application/json")

    local error_msg
    if error_msg=$(_llm_check_error "ollama" "$response"); then
        printf '{"ok":true,"data":%s}' "$response"
        return 0
    else
        _llm_error "$error_msg" 500
        return 1
    fi
}

# Pull a model from Ollama registry
# Usage: llm_ollama_pull "model_name"
llm_ollama_pull() {
    local model="$1"

    if [[ -z "$model" ]]; then
        _llm_error "Model name required" 400
        return 1
    fi

    _llm_require_curl || return 1

    local request_body
    request_body=$(printf '{"name":"%s"}' "$model")

    _llm_log "info" "Pulling model: $model"

    local response
    response=$(_llm_http_request "POST" "${LLM_OLLAMA_HOST}/api/pull" "$request_body" \
        "Content-Type: application/json")

    local error_msg
    if error_msg=$(_llm_check_error "ollama" "$response"); then
        json_object "ok:bool=true" "message=Model $model pulled successfully"
        return 0
    else
        _llm_error "$error_msg" 500
        return 1
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if a provider is available (API key set or service running)
# Usage: llm_provider_available "openai"
llm_provider_available() {
    local provider="$1"

    case "$provider" in
        openai)
            [[ -n "${OPENAI_API_KEY:-}" ]]
            ;;
        anthropic)
            [[ -n "${ANTHROPIC_API_KEY:-}" ]]
            ;;
        ollama)
            # Try to connect to Ollama
            curl -sf "${LLM_OLLAMA_HOST}/api/tags" --max-time 2 &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Get provider status for all providers
# Usage: llm_status
llm_status() {
    local openai_status="unavailable"
    local anthropic_status="unavailable"
    local ollama_status="unavailable"

    llm_provider_available "openai" && openai_status="available"
    llm_provider_available "anthropic" && anthropic_status="available"
    llm_provider_available "ollama" && ollama_status="available"

    json_object \
        "ok:bool=true" \
        "openai=${openai_status}" \
        "anthropic=${anthropic_status}" \
        "ollama=${ollama_status}" \
        "default_provider=${LLM_DEFAULT_PROVIDER}" \
        "default_model=${LLM_DEFAULT_MODEL}"
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

LLM_PROVIDERS_EXPORTS=(
    # Configuration
    llm_set_provider
    llm_set_model
    llm_config_get

    # Generic interface
    llm_chat
    llm_complete
    llm_embed

    # OpenAI
    llm_openai_chat
    llm_openai_complete
    llm_openai_embed
    llm_openai_models

    # Anthropic
    llm_anthropic_chat
    llm_anthropic_complete
    llm_anthropic_models

    # Ollama
    llm_ollama_chat
    llm_ollama_generate
    llm_ollama_embed
    llm_ollama_list
    llm_ollama_pull

    # Utilities
    llm_provider_available
    llm_status
)
