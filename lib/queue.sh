#!/usr/bin/env bash
# =============================================================================
# MAINFRAME/lib/queue.sh - Queue, Stack, Deque, Priority Queue & Ring Buffer
# =============================================================================
# Description: Comprehensive data structures for sequential and priority-based
#              data processing with Design-by-Contract validation.
# Version: 1.0.0
# Requires: Bash 4.0+
# =============================================================================
# "Mainframe can make a computer do anything short of tap dance."
# =============================================================================

# Prevent double-sourcing
[[ -n "${_MAINFRAME_QUEUE_LOADED:-}" ]] && return 0
readonly _MAINFRAME_QUEUE_LOADED=1

# =============================================================================
# DEPENDENCIES
# =============================================================================

# shellcheck source=./common.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/common.sh" 2>/dev/null || true
# shellcheck source=./json.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/json.sh" 2>/dev/null || true
# shellcheck source=./contract.sh
source "${MAINFRAME_ROOT:-${HOME}/.mainframe}/lib/contract.sh" 2>/dev/null || true

# =============================================================================
# CONFIGURATION
# =============================================================================

# Maximum queue size to prevent runaway memory usage
readonly QUEUE_MAX_SIZE="${QUEUE_MAX_SIZE:-1000000}"

# Enable/disable contract checking (can be disabled for performance)
QUEUE_CONTRACTS="${QUEUE_CONTRACTS:-1}"

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# JSON escape for USOP output
_queue_escape_json() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Emit USOP JSON error
_queue_error() {
    local code="${1:-1}"
    local msg="${2:-unknown error}"
    local func="${FUNCNAME[1]:-unknown}"

    local escaped_msg escaped_func
    escaped_msg=$(_queue_escape_json "$msg")
    escaped_func=$(_queue_escape_json "$func")

    printf '{"ok":false,"error":{"code":%d,"msg":"%s","func":"%s"}}\n' \
        "$code" "$escaped_msg" "$escaped_func" >&2
    return "$code"
}

# Emit USOP JSON success
_queue_success() {
    local data="${1:-null}"
    printf '{"ok":true,"data":%s}\n' "$data"
}

# Validate that a function exists and is callable
_queue_is_callable() {
    local name="$1"
    [[ -n "$name" ]] && declare -f "$name" &>/dev/null
}

# =============================================================================
# QUEUE (FIFO) OPERATIONS
# =============================================================================

# -----------------------------------------------------------------------------
# queue_create - Initialize a new queue
# -----------------------------------------------------------------------------
# @description Create an empty queue using a nameref array
# @pre         none
# @post        queue array is initialized to empty
# @idempotent  Yes - reinitializing clears the queue
# @param       $1 queue - Queue array (nameref)
# @return      0 on success
#
# Usage:
#   queue_create myqueue
#   queue_push myqueue "first"
# -----------------------------------------------------------------------------
queue_create() {
    local -n _qc_queue=$1
    _qc_queue=()
    return 0
}

# -----------------------------------------------------------------------------
# queue_push - Add element to back of queue (enqueue)
# -----------------------------------------------------------------------------
# @description Add an element to the end of the queue
# @pre         queue exists
# @post        element added to back of queue
# @idempotent  No - each call adds an element
# @param       $1 queue - Queue array (nameref)
# @param       $2 element - Element to add
# @return      0 on success, 1 if queue full
#
# Usage:
#   queue_push myqueue "item"
# -----------------------------------------------------------------------------
queue_push() {
    local -n _qp_queue=$1
    local element="$2"

    # Contract: check max size
    if [[ "$QUEUE_CONTRACTS" == "1" ]]; then
        if (( ${#_qp_queue[@]} >= QUEUE_MAX_SIZE )); then
            _queue_error 1 "queue full (max size: $QUEUE_MAX_SIZE)"
            return 1
        fi
    fi

    _qp_queue+=("$element")
    return 0
}

# -----------------------------------------------------------------------------
# queue_pop - Remove and return element from front of queue (dequeue)
# -----------------------------------------------------------------------------
# @description Remove the front element and output its value
# @pre         queue is not empty
# @post        front element removed, remaining elements shifted
# @idempotent  No - modifies queue state
# @param       $1 queue - Queue array (nameref)
# @stdout      The removed element
# @return      0 on success, 1 if empty
#
# Usage:
#   value=$(queue_pop myqueue)
# -----------------------------------------------------------------------------
queue_pop() {
    local -n _qpop_queue=$1

    # Contract: queue must not be empty
    if (( ${#_qpop_queue[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "queue is empty"
        return 1
    fi

    # Output front element
    printf '%s' "${_qpop_queue[0]}"

    # Remove front element (shift all elements)
    _qpop_queue=("${_qpop_queue[@]:1}")
    return 0
}

# -----------------------------------------------------------------------------
# queue_pop_v - Remove element from front, store in variable (zero subshell)
# -----------------------------------------------------------------------------
# @description Remove front element and store in nameref variable
# @pre         queue is not empty
# @post        front element removed, value stored in output variable
# @idempotent  No - modifies queue state
# @param       $1 queue - Queue array (nameref)
# @param       $2 output - Output variable (nameref)
# @return      0 on success, 1 if empty
#
# Usage:
#   queue_pop_v myqueue result
# -----------------------------------------------------------------------------
queue_pop_v() {
    local -n _qpopv_queue=$1
    local -n _qpopv_out=$2

    if (( ${#_qpopv_queue[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "queue is empty"
        return 1
    fi

    _qpopv_out="${_qpopv_queue[0]}"
    _qpopv_queue=("${_qpopv_queue[@]:1}")
    return 0
}

# -----------------------------------------------------------------------------
# queue_peek - View front element without removing
# -----------------------------------------------------------------------------
# @description Get the front element without modifying the queue
# @pre         queue is not empty
# @post        queue unchanged
# @idempotent  Yes
# @param       $1 queue - Queue array (nameref)
# @stdout      The front element
# @return      0 on success, 1 if empty
#
# Usage:
#   front=$(queue_peek myqueue)
# -----------------------------------------------------------------------------
queue_peek() {
    local -n _qpeek_queue=$1

    if (( ${#_qpeek_queue[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "queue is empty"
        return 1
    fi

    printf '%s' "${_qpeek_queue[0]}"
    return 0
}

# -----------------------------------------------------------------------------
# queue_peek_v - View front element, store in variable (zero subshell)
# -----------------------------------------------------------------------------
# @description Get front element and store in nameref variable
# @pre         queue is not empty
# @post        queue unchanged, value stored in output variable
# @idempotent  Yes
# @param       $1 queue - Queue array (nameref)
# @param       $2 output - Output variable (nameref)
# @return      0 on success, 1 if empty
#
# Usage:
#   queue_peek_v myqueue result
# -----------------------------------------------------------------------------
queue_peek_v() {
    local -n _qpeekv_queue=$1
    local -n _qpeekv_out=$2

    if (( ${#_qpeekv_queue[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "queue is empty"
        return 1
    fi

    _qpeekv_out="${_qpeekv_queue[0]}"
    return 0
}

# -----------------------------------------------------------------------------
# queue_peek_back - View back element without removing
# -----------------------------------------------------------------------------
# @description Get the back (last) element without modifying the queue
# @pre         queue is not empty
# @post        queue unchanged
# @idempotent  Yes
# @param       $1 queue - Queue array (nameref)
# @stdout      The back element
# @return      0 on success, 1 if empty
#
# Usage:
#   back=$(queue_peek_back myqueue)
# -----------------------------------------------------------------------------
queue_peek_back() {
    local -n _qpb_queue=$1

    local len=${#_qpb_queue[@]}
    if (( len == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "queue is empty"
        return 1
    fi

    printf '%s' "${_qpb_queue[$((len - 1))]}"
    return 0
}

# -----------------------------------------------------------------------------
# queue_size - Get number of elements in queue
# -----------------------------------------------------------------------------
# @description Return the current queue length
# @pre         none
# @post        queue unchanged
# @idempotent  Yes
# @param       $1 queue - Queue array (nameref)
# @stdout      Number of elements
# @return      0 on success
#
# Usage:
#   size=$(queue_size myqueue)
# -----------------------------------------------------------------------------
queue_size() {
    local -n _qs_queue=$1
    printf '%d' "${#_qs_queue[@]}"
    return 0
}

# -----------------------------------------------------------------------------
# queue_is_empty - Check if queue has no elements
# -----------------------------------------------------------------------------
# @description Test if queue is empty
# @pre         none
# @post        queue unchanged
# @idempotent  Yes
# @param       $1 queue - Queue array (nameref)
# @return      0 if empty, 1 if not empty
#
# Usage:
#   queue_is_empty myqueue && echo "empty"
# -----------------------------------------------------------------------------
queue_is_empty() {
    local -n _qie_queue=$1
    (( ${#_qie_queue[@]} == 0 ))
}

# -----------------------------------------------------------------------------
# queue_clear - Remove all elements from queue
# -----------------------------------------------------------------------------
# @description Reset queue to empty state
# @pre         none
# @post        queue is empty
# @idempotent  Yes
# @param       $1 queue - Queue array (nameref)
# @return      0 on success
#
# Usage:
#   queue_clear myqueue
# -----------------------------------------------------------------------------
queue_clear() {
    local -n _qclear_queue=$1
    _qclear_queue=()
    return 0
}

# -----------------------------------------------------------------------------
# queue_to_array - Convert queue to regular array
# -----------------------------------------------------------------------------
# @description Copy queue contents to an output array
# @pre         none
# @post        queue unchanged, output array contains copy
# @idempotent  Yes
# @param       $1 queue - Queue array (nameref)
# @param       $2 output - Output array (nameref)
# @return      0 on success
#
# Usage:
#   queue_to_array myqueue result
# -----------------------------------------------------------------------------
queue_to_array() {
    local -n _qta_queue=$1
    local -n _qta_output=$2

    _qta_output=("${_qta_queue[@]}")
    return 0
}

# -----------------------------------------------------------------------------
# queue_from_array - Create queue from existing array
# -----------------------------------------------------------------------------
# @description Initialize queue with contents of an array
# @pre         none
# @post        queue contains array elements in order
# @idempotent  Yes - replaces existing queue contents
# @param       $1 queue - Queue array (nameref)
# @param       $2 source - Source array (nameref)
# @return      0 on success
#
# Usage:
#   arr=(1 2 3)
#   queue_from_array myqueue arr
# -----------------------------------------------------------------------------
queue_from_array() {
    local -n _qfa_queue=$1
    local -n _qfa_source=$2

    _qfa_queue=("${_qfa_source[@]}")
    return 0
}

# =============================================================================
# STACK (LIFO) OPERATIONS
# =============================================================================

# -----------------------------------------------------------------------------
# stack_create - Initialize a new stack
# -----------------------------------------------------------------------------
# @description Create an empty stack using a nameref array
# @pre         none
# @post        stack array is initialized to empty
# @idempotent  Yes - reinitializing clears the stack
# @param       $1 stack - Stack array (nameref)
# @return      0 on success
#
# Usage:
#   stack_create mystack
#   stack_push mystack "first"
# -----------------------------------------------------------------------------
stack_create() {
    local -n _sc_stack=$1
    _sc_stack=()
    return 0
}

# -----------------------------------------------------------------------------
# stack_push - Push element onto top of stack
# -----------------------------------------------------------------------------
# @description Add an element to the top of the stack
# @pre         stack exists
# @post        element added to top of stack
# @idempotent  No - each call adds an element
# @param       $1 stack - Stack array (nameref)
# @param       $2 element - Element to push
# @return      0 on success, 1 if stack full
#
# Usage:
#   stack_push mystack "item"
# -----------------------------------------------------------------------------
stack_push() {
    local -n _sp_stack=$1
    local element="$2"

    # Contract: check max size
    if [[ "$QUEUE_CONTRACTS" == "1" ]]; then
        if (( ${#_sp_stack[@]} >= QUEUE_MAX_SIZE )); then
            _queue_error 1 "stack full (max size: $QUEUE_MAX_SIZE)"
            return 1
        fi
    fi

    _sp_stack+=("$element")
    return 0
}

# -----------------------------------------------------------------------------
# stack_pop - Remove and return element from top of stack
# -----------------------------------------------------------------------------
# @description Remove the top element and output its value
# @pre         stack is not empty
# @post        top element removed
# @idempotent  No - modifies stack state
# @param       $1 stack - Stack array (nameref)
# @stdout      The removed element
# @return      0 on success, 1 if empty
#
# Usage:
#   value=$(stack_pop mystack)
# -----------------------------------------------------------------------------
stack_pop() {
    local -n _spop_stack=$1

    local len=${#_spop_stack[@]}
    if (( len == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "stack is empty"
        return 1
    fi

    # Output top element
    printf '%s' "${_spop_stack[$((len - 1))]}"

    # Remove top element
    unset "_spop_stack[$((len - 1))]"
    return 0
}

# -----------------------------------------------------------------------------
# stack_pop_v - Pop element from top, store in variable (zero subshell)
# -----------------------------------------------------------------------------
# @description Remove top element and store in nameref variable
# @pre         stack is not empty
# @post        top element removed, value stored in output variable
# @idempotent  No - modifies stack state
# @param       $1 stack - Stack array (nameref)
# @param       $2 output - Output variable (nameref)
# @return      0 on success, 1 if empty
#
# Usage:
#   stack_pop_v mystack result
# -----------------------------------------------------------------------------
stack_pop_v() {
    local -n _spopv_stack=$1
    local -n _spopv_out=$2

    local len=${#_spopv_stack[@]}
    if (( len == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "stack is empty"
        return 1
    fi

    _spopv_out="${_spopv_stack[$((len - 1))]}"
    unset "_spopv_stack[$((len - 1))]"
    return 0
}

# -----------------------------------------------------------------------------
# stack_peek - View top element without removing
# -----------------------------------------------------------------------------
# @description Get the top element without modifying the stack
# @pre         stack is not empty
# @post        stack unchanged
# @idempotent  Yes
# @param       $1 stack - Stack array (nameref)
# @stdout      The top element
# @return      0 on success, 1 if empty
#
# Usage:
#   top=$(stack_peek mystack)
# -----------------------------------------------------------------------------
stack_peek() {
    local -n _speek_stack=$1

    local len=${#_speek_stack[@]}
    if (( len == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "stack is empty"
        return 1
    fi

    printf '%s' "${_speek_stack[$((len - 1))]}"
    return 0
}

# -----------------------------------------------------------------------------
# stack_peek_v - View top element, store in variable (zero subshell)
# -----------------------------------------------------------------------------
# @description Get top element and store in nameref variable
# @pre         stack is not empty
# @post        stack unchanged, value stored in output variable
# @idempotent  Yes
# @param       $1 stack - Stack array (nameref)
# @param       $2 output - Output variable (nameref)
# @return      0 on success, 1 if empty
#
# Usage:
#   stack_peek_v mystack result
# -----------------------------------------------------------------------------
stack_peek_v() {
    local -n _speekv_stack=$1
    local -n _speekv_out=$2

    local len=${#_speekv_stack[@]}
    if (( len == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "stack is empty"
        return 1
    fi

    _speekv_out="${_speekv_stack[$((len - 1))]}"
    return 0
}

# -----------------------------------------------------------------------------
# stack_size - Get number of elements in stack
# -----------------------------------------------------------------------------
# @description Return the current stack depth
# @pre         none
# @post        stack unchanged
# @idempotent  Yes
# @param       $1 stack - Stack array (nameref)
# @stdout      Number of elements
# @return      0 on success
#
# Usage:
#   depth=$(stack_size mystack)
# -----------------------------------------------------------------------------
stack_size() {
    local -n _ss_stack=$1
    printf '%d' "${#_ss_stack[@]}"
    return 0
}

# -----------------------------------------------------------------------------
# stack_is_empty - Check if stack has no elements
# -----------------------------------------------------------------------------
# @description Test if stack is empty
# @pre         none
# @post        stack unchanged
# @idempotent  Yes
# @param       $1 stack - Stack array (nameref)
# @return      0 if empty, 1 if not empty
#
# Usage:
#   stack_is_empty mystack && echo "empty"
# -----------------------------------------------------------------------------
stack_is_empty() {
    local -n _sie_stack=$1
    (( ${#_sie_stack[@]} == 0 ))
}

# -----------------------------------------------------------------------------
# stack_clear - Remove all elements from stack
# -----------------------------------------------------------------------------
# @description Reset stack to empty state
# @pre         none
# @post        stack is empty
# @idempotent  Yes
# @param       $1 stack - Stack array (nameref)
# @return      0 on success
#
# Usage:
#   stack_clear mystack
# -----------------------------------------------------------------------------
stack_clear() {
    local -n _sclear_stack=$1
    _sclear_stack=()
    return 0
}

# -----------------------------------------------------------------------------
# stack_reverse - Reverse the order of stack elements
# -----------------------------------------------------------------------------
# @description Reverse stack in place
# @pre         none
# @post        stack elements in reverse order
# @idempotent  No - double reverse restores original
# @param       $1 stack - Stack array (nameref)
# @return      0 on success
#
# Usage:
#   stack_reverse mystack
# -----------------------------------------------------------------------------
stack_reverse() {
    local -n _sr_stack=$1

    local len=${#_sr_stack[@]}
    (( len <= 1 )) && return 0

    local i j temp
    for (( i = 0, j = len - 1; i < j; i++, j-- )); do
        temp="${_sr_stack[$i]}"
        _sr_stack[$i]="${_sr_stack[$j]}"
        _sr_stack[$j]="$temp"
    done

    return 0
}

# -----------------------------------------------------------------------------
# stack_to_array - Convert stack to regular array
# -----------------------------------------------------------------------------
# @description Copy stack contents to an output array
# @pre         none
# @post        stack unchanged, output array contains copy
# @idempotent  Yes
# @param       $1 stack - Stack array (nameref)
# @param       $2 output - Output array (nameref)
# @return      0 on success
#
# Usage:
#   stack_to_array mystack result
# -----------------------------------------------------------------------------
stack_to_array() {
    local -n _sta_stack=$1
    local -n _sta_output=$2

    _sta_output=("${_sta_stack[@]}")
    return 0
}

# =============================================================================
# DEQUE (DOUBLE-ENDED QUEUE) OPERATIONS
# =============================================================================

# -----------------------------------------------------------------------------
# deque_create - Initialize a new deque
# -----------------------------------------------------------------------------
# @description Create an empty double-ended queue
# @pre         none
# @post        deque array is initialized to empty
# @idempotent  Yes
# @param       $1 deque - Deque array (nameref)
# @return      0 on success
#
# Usage:
#   deque_create mydeque
# -----------------------------------------------------------------------------
deque_create() {
    local -n _dc_deque=$1
    _dc_deque=()
    return 0
}

# -----------------------------------------------------------------------------
# deque_push_front - Add element to front of deque
# -----------------------------------------------------------------------------
# @description Insert an element at the beginning
# @pre         deque exists
# @post        element added to front
# @idempotent  No
# @param       $1 deque - Deque array (nameref)
# @param       $2 element - Element to add
# @return      0 on success, 1 if full
#
# Usage:
#   deque_push_front mydeque "item"
# -----------------------------------------------------------------------------
deque_push_front() {
    local -n _dpf_deque=$1
    local element="$2"

    if [[ "$QUEUE_CONTRACTS" == "1" ]]; then
        if (( ${#_dpf_deque[@]} >= QUEUE_MAX_SIZE )); then
            _queue_error 1 "deque full (max size: $QUEUE_MAX_SIZE)"
            return 1
        fi
    fi

    _dpf_deque=("$element" "${_dpf_deque[@]}")
    return 0
}

# -----------------------------------------------------------------------------
# deque_push_back - Add element to back of deque
# -----------------------------------------------------------------------------
# @description Append an element at the end
# @pre         deque exists
# @post        element added to back
# @idempotent  No
# @param       $1 deque - Deque array (nameref)
# @param       $2 element - Element to add
# @return      0 on success, 1 if full
#
# Usage:
#   deque_push_back mydeque "item"
# -----------------------------------------------------------------------------
deque_push_back() {
    local -n _dpb_deque=$1
    local element="$2"

    if [[ "$QUEUE_CONTRACTS" == "1" ]]; then
        if (( ${#_dpb_deque[@]} >= QUEUE_MAX_SIZE )); then
            _queue_error 1 "deque full (max size: $QUEUE_MAX_SIZE)"
            return 1
        fi
    fi

    _dpb_deque+=("$element")
    return 0
}

# -----------------------------------------------------------------------------
# deque_pop_front - Remove and return element from front
# -----------------------------------------------------------------------------
# @description Remove the front element and output its value
# @pre         deque is not empty
# @post        front element removed
# @idempotent  No
# @param       $1 deque - Deque array (nameref)
# @stdout      The removed element
# @return      0 on success, 1 if empty
#
# Usage:
#   value=$(deque_pop_front mydeque)
# -----------------------------------------------------------------------------
deque_pop_front() {
    local -n _dpof_deque=$1

    if (( ${#_dpof_deque[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "deque is empty"
        return 1
    fi

    printf '%s' "${_dpof_deque[0]}"
    _dpof_deque=("${_dpof_deque[@]:1}")
    return 0
}

# -----------------------------------------------------------------------------
# deque_pop_front_v - Remove front element, store in variable
# -----------------------------------------------------------------------------
# @description Remove front element and store in nameref variable
# @pre         deque is not empty
# @post        front element removed, value stored
# @idempotent  No
# @param       $1 deque - Deque array (nameref)
# @param       $2 output - Output variable (nameref)
# @return      0 on success, 1 if empty
#
# Usage:
#   deque_pop_front_v mydeque result
# -----------------------------------------------------------------------------
deque_pop_front_v() {
    local -n _dpofv_deque=$1
    local -n _dpofv_out=$2

    if (( ${#_dpofv_deque[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "deque is empty"
        return 1
    fi

    _dpofv_out="${_dpofv_deque[0]}"
    _dpofv_deque=("${_dpofv_deque[@]:1}")
    return 0
}

# -----------------------------------------------------------------------------
# deque_pop_back - Remove and return element from back
# -----------------------------------------------------------------------------
# @description Remove the back element and output its value
# @pre         deque is not empty
# @post        back element removed
# @idempotent  No
# @param       $1 deque - Deque array (nameref)
# @stdout      The removed element
# @return      0 on success, 1 if empty
#
# Usage:
#   value=$(deque_pop_back mydeque)
# -----------------------------------------------------------------------------
deque_pop_back() {
    local -n _dpob_deque=$1

    local len=${#_dpob_deque[@]}
    if (( len == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "deque is empty"
        return 1
    fi

    printf '%s' "${_dpob_deque[$((len - 1))]}"
    unset "_dpob_deque[$((len - 1))]"
    return 0
}

# -----------------------------------------------------------------------------
# deque_pop_back_v - Remove back element, store in variable
# -----------------------------------------------------------------------------
# @description Remove back element and store in nameref variable
# @pre         deque is not empty
# @post        back element removed, value stored
# @idempotent  No
# @param       $1 deque - Deque array (nameref)
# @param       $2 output - Output variable (nameref)
# @return      0 on success, 1 if empty
#
# Usage:
#   deque_pop_back_v mydeque result
# -----------------------------------------------------------------------------
deque_pop_back_v() {
    local -n _dpobv_deque=$1
    local -n _dpobv_out=$2

    local len=${#_dpobv_deque[@]}
    if (( len == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "deque is empty"
        return 1
    fi

    _dpobv_out="${_dpobv_deque[$((len - 1))]}"
    unset "_dpobv_deque[$((len - 1))]"
    return 0
}

# -----------------------------------------------------------------------------
# deque_peek_front - View front element without removing
# -----------------------------------------------------------------------------
# @description Get the front element without modifying the deque
# @pre         deque is not empty
# @post        deque unchanged
# @idempotent  Yes
# @param       $1 deque - Deque array (nameref)
# @stdout      The front element
# @return      0 on success, 1 if empty
#
# Usage:
#   front=$(deque_peek_front mydeque)
# -----------------------------------------------------------------------------
deque_peek_front() {
    local -n _dpef_deque=$1

    if (( ${#_dpef_deque[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "deque is empty"
        return 1
    fi

    printf '%s' "${_dpef_deque[0]}"
    return 0
}

# -----------------------------------------------------------------------------
# deque_peek_back - View back element without removing
# -----------------------------------------------------------------------------
# @description Get the back element without modifying the deque
# @pre         deque is not empty
# @post        deque unchanged
# @idempotent  Yes
# @param       $1 deque - Deque array (nameref)
# @stdout      The back element
# @return      0 on success, 1 if empty
#
# Usage:
#   back=$(deque_peek_back mydeque)
# -----------------------------------------------------------------------------
deque_peek_back() {
    local -n _dpeb_deque=$1

    local len=${#_dpeb_deque[@]}
    if (( len == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "deque is empty"
        return 1
    fi

    printf '%s' "${_dpeb_deque[$((len - 1))]}"
    return 0
}

# -----------------------------------------------------------------------------
# deque_size - Get number of elements in deque
# -----------------------------------------------------------------------------
# @description Return the current deque length
# @pre         none
# @post        deque unchanged
# @idempotent  Yes
# @param       $1 deque - Deque array (nameref)
# @stdout      Number of elements
# @return      0 on success
#
# Usage:
#   size=$(deque_size mydeque)
# -----------------------------------------------------------------------------
deque_size() {
    local -n _ds_deque=$1
    printf '%d' "${#_ds_deque[@]}"
    return 0
}

# -----------------------------------------------------------------------------
# deque_is_empty - Check if deque has no elements
# -----------------------------------------------------------------------------
# @description Test if deque is empty
# @pre         none
# @post        deque unchanged
# @idempotent  Yes
# @param       $1 deque - Deque array (nameref)
# @return      0 if empty, 1 if not empty
#
# Usage:
#   deque_is_empty mydeque && echo "empty"
# -----------------------------------------------------------------------------
deque_is_empty() {
    local -n _die_deque=$1
    (( ${#_die_deque[@]} == 0 ))
}

# -----------------------------------------------------------------------------
# deque_clear - Remove all elements from deque
# -----------------------------------------------------------------------------
# @description Reset deque to empty state
# @pre         none
# @post        deque is empty
# @idempotent  Yes
# @param       $1 deque - Deque array (nameref)
# @return      0 on success
#
# Usage:
#   deque_clear mydeque
# -----------------------------------------------------------------------------
deque_clear() {
    local -n _dclear_deque=$1
    _dclear_deque=()
    return 0
}

# -----------------------------------------------------------------------------
# deque_rotate_left - Rotate elements to the left
# -----------------------------------------------------------------------------
# @description Move front element to back (rotate left by 1)
# @pre         deque is not empty
# @post        front element moved to back
# @idempotent  No
# @param       $1 deque - Deque array (nameref)
# @param       $2 count - Number of rotations (default: 1)
# @return      0 on success, 1 if empty
#
# Usage:
#   deque_rotate_left mydeque
#   deque_rotate_left mydeque 3
# -----------------------------------------------------------------------------
deque_rotate_left() {
    local -n _drl_deque=$1
    local count="${2:-1}"

    local len=${#_drl_deque[@]}
    (( len == 0 )) && return 0
    (( count %= len ))
    (( count == 0 )) && return 0

    # Take first 'count' elements and move to end
    local front=("${_drl_deque[@]:0:$count}")
    _drl_deque=("${_drl_deque[@]:$count}" "${front[@]}")
    return 0
}

# -----------------------------------------------------------------------------
# deque_rotate_right - Rotate elements to the right
# -----------------------------------------------------------------------------
# @description Move back element to front (rotate right by 1)
# @pre         deque is not empty
# @post        back element moved to front
# @idempotent  No
# @param       $1 deque - Deque array (nameref)
# @param       $2 count - Number of rotations (default: 1)
# @return      0 on success, 1 if empty
#
# Usage:
#   deque_rotate_right mydeque
#   deque_rotate_right mydeque 3
# -----------------------------------------------------------------------------
deque_rotate_right() {
    local -n _drr_deque=$1
    local count="${2:-1}"

    local len=${#_drr_deque[@]}
    (( len == 0 )) && return 0
    (( count %= len ))
    (( count == 0 )) && return 0

    # Take last 'count' elements and move to front
    local back=("${_drr_deque[@]:$((len - count))}")
    _drr_deque=("${back[@]}" "${_drr_deque[@]:0:$((len - count))}")
    return 0
}

# =============================================================================
# PRIORITY QUEUE OPERATIONS
# =============================================================================
# Priority queue implemented as a sorted array with binary insertion.
# Each element is stored as "priority:value" pair.
# Higher priority values are dequeued first (max-heap semantics).
# =============================================================================

# -----------------------------------------------------------------------------
# pqueue_create - Initialize a new priority queue
# -----------------------------------------------------------------------------
# @description Create an empty priority queue
# @pre         none
# @post        priority queue is initialized to empty
# @idempotent  Yes
# @param       $1 pqueue - Priority queue array (nameref)
# @return      0 on success
#
# Usage:
#   pqueue_create mypqueue
# -----------------------------------------------------------------------------
pqueue_create() {
    local -n _pqc_pqueue=$1
    _pqc_pqueue=()
    return 0
}

# -----------------------------------------------------------------------------
# pqueue_push - Add element with priority
# -----------------------------------------------------------------------------
# @description Insert element maintaining sorted order by priority
# @pre         priority is a valid integer
# @post        element inserted at correct position
# @idempotent  No
# @param       $1 pqueue - Priority queue array (nameref)
# @param       $2 priority - Integer priority (higher = more urgent)
# @param       $3 element - Element to add
# @return      0 on success, 1 on invalid priority
#
# Usage:
#   pqueue_push mypqueue 10 "high priority task"
#   pqueue_push mypqueue 1 "low priority task"
# -----------------------------------------------------------------------------
pqueue_push() {
    local -n _pqp_pqueue=$1
    local priority="$2"
    local element="$3"

    # Contract: priority must be integer
    if [[ "$QUEUE_CONTRACTS" == "1" ]]; then
        if [[ ! "$priority" =~ ^-?[0-9]+$ ]]; then
            _queue_error 1 "priority must be an integer, got '$priority'"
            return 1
        fi
        if (( ${#_pqp_pqueue[@]} >= QUEUE_MAX_SIZE )); then
            _queue_error 1 "priority queue full (max size: $QUEUE_MAX_SIZE)"
            return 1
        fi
    fi

    local entry="${priority}:${element}"

    # Empty queue - just add
    if (( ${#_pqp_pqueue[@]} == 0 )); then
        _pqp_pqueue=("$entry")
        return 0
    fi

    # Binary search for insertion point (descending order by priority)
    local left=0
    local right=${#_pqp_pqueue[@]}
    local mid existing_priority

    while (( left < right )); do
        mid=$(( (left + right) / 2 ))
        existing_priority="${_pqp_pqueue[$mid]%%:*}"
        if (( priority > existing_priority )); then
            right=$mid
        else
            left=$((mid + 1))
        fi
    done

    # Insert at position 'left'
    _pqp_pqueue=("${_pqp_pqueue[@]:0:$left}" "$entry" "${_pqp_pqueue[@]:$left}")
    return 0
}

# -----------------------------------------------------------------------------
# pqueue_pop - Remove and return highest priority element
# -----------------------------------------------------------------------------
# @description Remove the element with highest priority
# @pre         priority queue is not empty
# @post        highest priority element removed
# @idempotent  No
# @param       $1 pqueue - Priority queue array (nameref)
# @stdout      The element value (without priority)
# @return      0 on success, 1 if empty
#
# Usage:
#   task=$(pqueue_pop mypqueue)
# -----------------------------------------------------------------------------
pqueue_pop() {
    local -n _pqpop_pqueue=$1

    if (( ${#_pqpop_pqueue[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "priority queue is empty"
        return 1
    fi

    # Front element has highest priority
    local entry="${_pqpop_pqueue[0]}"
    local value="${entry#*:}"

    printf '%s' "$value"
    _pqpop_pqueue=("${_pqpop_pqueue[@]:1}")
    return 0
}

# -----------------------------------------------------------------------------
# pqueue_pop_v - Pop highest priority element into variable
# -----------------------------------------------------------------------------
# @description Remove highest priority element, store value in variable
# @pre         priority queue is not empty
# @post        element removed, value stored
# @idempotent  No
# @param       $1 pqueue - Priority queue array (nameref)
# @param       $2 output - Output variable (nameref)
# @return      0 on success, 1 if empty
#
# Usage:
#   pqueue_pop_v mypqueue result
# -----------------------------------------------------------------------------
pqueue_pop_v() {
    local -n _pqpopv_pqueue=$1
    local -n _pqpopv_out=$2

    if (( ${#_pqpopv_pqueue[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "priority queue is empty"
        return 1
    fi

    local entry="${_pqpopv_pqueue[0]}"
    _pqpopv_out="${entry#*:}"
    _pqpopv_pqueue=("${_pqpopv_pqueue[@]:1}")
    return 0
}

# -----------------------------------------------------------------------------
# pqueue_peek - View highest priority element without removing
# -----------------------------------------------------------------------------
# @description Get the highest priority element value
# @pre         priority queue is not empty
# @post        queue unchanged
# @idempotent  Yes
# @param       $1 pqueue - Priority queue array (nameref)
# @stdout      The element value (without priority)
# @return      0 on success, 1 if empty
#
# Usage:
#   next_task=$(pqueue_peek mypqueue)
# -----------------------------------------------------------------------------
pqueue_peek() {
    local -n _pqpeek_pqueue=$1

    if (( ${#_pqpeek_pqueue[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "priority queue is empty"
        return 1
    fi

    local entry="${_pqpeek_pqueue[0]}"
    printf '%s' "${entry#*:}"
    return 0
}

# -----------------------------------------------------------------------------
# pqueue_peek_priority - View priority of highest priority element
# -----------------------------------------------------------------------------
# @description Get the priority value of the front element
# @pre         priority queue is not empty
# @post        queue unchanged
# @idempotent  Yes
# @param       $1 pqueue - Priority queue array (nameref)
# @stdout      The priority value
# @return      0 on success, 1 if empty
#
# Usage:
#   priority=$(pqueue_peek_priority mypqueue)
# -----------------------------------------------------------------------------
pqueue_peek_priority() {
    local -n _pqpp_pqueue=$1

    if (( ${#_pqpp_pqueue[@]} == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "priority queue is empty"
        return 1
    fi

    local entry="${_pqpp_pqueue[0]}"
    printf '%s' "${entry%%:*}"
    return 0
}

# -----------------------------------------------------------------------------
# pqueue_size - Get number of elements in priority queue
# -----------------------------------------------------------------------------
# @description Return the current priority queue length
# @pre         none
# @post        queue unchanged
# @idempotent  Yes
# @param       $1 pqueue - Priority queue array (nameref)
# @stdout      Number of elements
# @return      0 on success
#
# Usage:
#   size=$(pqueue_size mypqueue)
# -----------------------------------------------------------------------------
pqueue_size() {
    local -n _pqs_pqueue=$1
    printf '%d' "${#_pqs_pqueue[@]}"
    return 0
}

# -----------------------------------------------------------------------------
# pqueue_is_empty - Check if priority queue has no elements
# -----------------------------------------------------------------------------
# @description Test if priority queue is empty
# @pre         none
# @post        queue unchanged
# @idempotent  Yes
# @param       $1 pqueue - Priority queue array (nameref)
# @return      0 if empty, 1 if not empty
#
# Usage:
#   pqueue_is_empty mypqueue && echo "empty"
# -----------------------------------------------------------------------------
pqueue_is_empty() {
    local -n _pqie_pqueue=$1
    (( ${#_pqie_pqueue[@]} == 0 ))
}

# -----------------------------------------------------------------------------
# pqueue_clear - Remove all elements from priority queue
# -----------------------------------------------------------------------------
# @description Reset priority queue to empty state
# @pre         none
# @post        priority queue is empty
# @idempotent  Yes
# @param       $1 pqueue - Priority queue array (nameref)
# @return      0 on success
#
# Usage:
#   pqueue_clear mypqueue
# -----------------------------------------------------------------------------
pqueue_clear() {
    local -n _pqclear_pqueue=$1
    _pqclear_pqueue=()
    return 0
}

# -----------------------------------------------------------------------------
# pqueue_update_priority - Change priority of an existing element
# -----------------------------------------------------------------------------
# @description Find element by value and update its priority
# @pre         element exists in queue
# @post        element repositioned according to new priority
# @idempotent  Yes - same result if called multiple times
# @param       $1 pqueue - Priority queue array (nameref)
# @param       $2 element - Element value to find
# @param       $3 new_priority - New priority value
# @return      0 on success, 1 if element not found
#
# Usage:
#   pqueue_update_priority mypqueue "task-1" 99
# -----------------------------------------------------------------------------
pqueue_update_priority() {
    local -n _pqup_pqueue=$1
    local element="$2"
    local new_priority="$3"

    # Contract: new_priority must be integer
    if [[ "$QUEUE_CONTRACTS" == "1" ]]; then
        if [[ ! "$new_priority" =~ ^-?[0-9]+$ ]]; then
            _queue_error 1 "priority must be an integer, got '$new_priority'"
            return 1
        fi
    fi

    # Find and remove element
    local i found=false
    for i in "${!_pqup_pqueue[@]}"; do
        local entry="${_pqup_pqueue[$i]}"
        local value="${entry#*:}"
        if [[ "$value" == "$element" ]]; then
            unset "_pqup_pqueue[$i]"
            # Reindex array
            _pqup_pqueue=("${_pqup_pqueue[@]}")
            found=true
            break
        fi
    done

    if ! $found; then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "element not found in priority queue"
        return 1
    fi

    # Re-insert with new priority
    pqueue_push _pqup_pqueue "$new_priority" "$element"
    return 0
}

# =============================================================================
# RING BUFFER (CIRCULAR BUFFER) OPERATIONS
# =============================================================================
# Ring buffer with fixed capacity. When full, new elements overwrite the oldest.
# Uses two arrays: one for data, one for metadata (capacity, head, tail).
# Format: ring_data=(...), ring_meta=(capacity head count)
# =============================================================================

# -----------------------------------------------------------------------------
# ring_create - Create a ring buffer with fixed capacity
# -----------------------------------------------------------------------------
# @description Initialize a fixed-size circular buffer
# @pre         capacity > 0
# @post        ring buffer initialized with specified capacity
# @idempotent  Yes - reinitializing clears the buffer
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @param       $3 capacity - Maximum number of elements
# @return      0 on success, 1 on invalid capacity
#
# Usage:
#   ring_create mybuffer mybuffer_meta 10
# -----------------------------------------------------------------------------
ring_create() {
    local -n _rc_ring=$1
    local -n _rc_meta=$2
    local capacity="$3"

    # Contract: capacity must be positive integer
    if [[ "$QUEUE_CONTRACTS" == "1" ]]; then
        if [[ ! "$capacity" =~ ^[1-9][0-9]*$ ]]; then
            _queue_error 1 "capacity must be a positive integer, got '$capacity'"
            return 1
        fi
    fi

    # Initialize empty ring
    _rc_ring=()
    # Meta: (capacity, head_index, count)
    _rc_meta=("$capacity" 0 0)
    return 0
}

# -----------------------------------------------------------------------------
# ring_push - Add element to ring buffer
# -----------------------------------------------------------------------------
# @description Add element, overwriting oldest if buffer is full
# @pre         ring buffer initialized
# @post        element added, oldest overwritten if full
# @idempotent  No
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @param       $3 element - Element to add
# @return      0 on success
#
# Usage:
#   ring_push mybuffer mybuffer_meta "item"
# -----------------------------------------------------------------------------
ring_push() {
    local -n _rp_ring=$1
    local -n _rp_meta=$2
    local element="$3"

    local capacity="${_rp_meta[0]}"
    local head="${_rp_meta[1]}"
    local count="${_rp_meta[2]}"

    # Calculate insertion index
    local tail=$(( (head + count) % capacity ))

    if (( count < capacity )); then
        # Not full - add normally
        _rp_ring[$tail]="$element"
        _rp_meta[2]=$((count + 1))
    else
        # Full - overwrite oldest (at head position)
        _rp_ring[$head]="$element"
        # Move head forward
        _rp_meta[1]=$(( (head + 1) % capacity ))
    fi

    return 0
}

# -----------------------------------------------------------------------------
# ring_pop - Remove and return oldest element
# -----------------------------------------------------------------------------
# @description Remove the oldest element (FIFO behavior)
# @pre         ring buffer is not empty
# @post        oldest element removed
# @idempotent  No
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @stdout      The oldest element
# @return      0 on success, 1 if empty
#
# Usage:
#   oldest=$(ring_pop mybuffer mybuffer_meta)
# -----------------------------------------------------------------------------
ring_pop() {
    local -n _rpop_ring=$1
    local -n _rpop_meta=$2

    local count="${_rpop_meta[2]}"

    if (( count == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "ring buffer is empty"
        return 1
    fi

    local head="${_rpop_meta[1]}"
    local capacity="${_rpop_meta[0]}"

    # Output oldest element
    printf '%s' "${_rpop_ring[$head]}"

    # Move head forward and decrement count
    _rpop_meta[1]=$(( (head + 1) % capacity ))
    _rpop_meta[2]=$((count - 1))

    return 0
}

# -----------------------------------------------------------------------------
# ring_pop_v - Remove oldest element, store in variable
# -----------------------------------------------------------------------------
# @description Remove oldest element and store in nameref variable
# @pre         ring buffer is not empty
# @post        oldest element removed, value stored
# @idempotent  No
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @param       $3 output - Output variable (nameref)
# @return      0 on success, 1 if empty
#
# Usage:
#   ring_pop_v mybuffer mybuffer_meta result
# -----------------------------------------------------------------------------
ring_pop_v() {
    local -n _rpopv_ring=$1
    local -n _rpopv_meta=$2
    local -n _rpopv_out=$3

    local count="${_rpopv_meta[2]}"

    if (( count == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "ring buffer is empty"
        return 1
    fi

    local head="${_rpopv_meta[1]}"
    local capacity="${_rpopv_meta[0]}"

    _rpopv_out="${_rpopv_ring[$head]}"
    _rpopv_meta[1]=$(( (head + 1) % capacity ))
    _rpopv_meta[2]=$((count - 1))

    return 0
}

# -----------------------------------------------------------------------------
# ring_peek - View oldest element without removing
# -----------------------------------------------------------------------------
# @description Get the oldest element without modifying the buffer
# @pre         ring buffer is not empty
# @post        buffer unchanged
# @idempotent  Yes
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @stdout      The oldest element
# @return      0 on success, 1 if empty
#
# Usage:
#   oldest=$(ring_peek mybuffer mybuffer_meta)
# -----------------------------------------------------------------------------
ring_peek() {
    local -n _rpeek_ring=$1
    local -n _rpeek_meta=$2

    local count="${_rpeek_meta[2]}"

    if (( count == 0 )); then
        [[ "$QUEUE_CONTRACTS" == "1" ]] && _queue_error 1 "ring buffer is empty"
        return 1
    fi

    local head="${_rpeek_meta[1]}"
    printf '%s' "${_rpeek_ring[$head]}"
    return 0
}

# -----------------------------------------------------------------------------
# ring_size - Get current number of elements
# -----------------------------------------------------------------------------
# @description Return current element count
# @pre         none
# @post        buffer unchanged
# @idempotent  Yes
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @stdout      Number of elements
# @return      0 on success
#
# Usage:
#   size=$(ring_size mybuffer mybuffer_meta)
# -----------------------------------------------------------------------------
ring_size() {
    local -n _rs_ring=$1
    local -n _rs_meta=$2
    printf '%d' "${_rs_meta[2]}"
    return 0
}

# -----------------------------------------------------------------------------
# ring_capacity - Get maximum capacity
# -----------------------------------------------------------------------------
# @description Return the fixed capacity of the ring buffer
# @pre         none
# @post        buffer unchanged
# @idempotent  Yes
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @stdout      Maximum capacity
# @return      0 on success
#
# Usage:
#   cap=$(ring_capacity mybuffer mybuffer_meta)
# -----------------------------------------------------------------------------
ring_capacity() {
    local -n _rcap_ring=$1
    local -n _rcap_meta=$2
    printf '%d' "${_rcap_meta[0]}"
    return 0
}

# -----------------------------------------------------------------------------
# ring_is_empty - Check if ring buffer has no elements
# -----------------------------------------------------------------------------
# @description Test if ring buffer is empty
# @pre         none
# @post        buffer unchanged
# @idempotent  Yes
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @return      0 if empty, 1 if not empty
#
# Usage:
#   ring_is_empty mybuffer mybuffer_meta && echo "empty"
# -----------------------------------------------------------------------------
ring_is_empty() {
    local -n _rie_ring=$1
    local -n _rie_meta=$2
    (( ${_rie_meta[2]} == 0 ))
}

# -----------------------------------------------------------------------------
# ring_is_full - Check if ring buffer is at capacity
# -----------------------------------------------------------------------------
# @description Test if ring buffer is full
# @pre         none
# @post        buffer unchanged
# @idempotent  Yes
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @return      0 if full, 1 if not full
#
# Usage:
#   ring_is_full mybuffer mybuffer_meta && echo "full"
# -----------------------------------------------------------------------------
ring_is_full() {
    local -n _rif_ring=$1
    local -n _rif_meta=$2
    (( ${_rif_meta[2]} == ${_rif_meta[0]} ))
}

# -----------------------------------------------------------------------------
# ring_clear - Remove all elements from ring buffer
# -----------------------------------------------------------------------------
# @description Reset ring buffer to empty state (preserving capacity)
# @pre         none
# @post        buffer is empty, capacity unchanged
# @idempotent  Yes
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @return      0 on success
#
# Usage:
#   ring_clear mybuffer mybuffer_meta
# -----------------------------------------------------------------------------
ring_clear() {
    local -n _rclear_ring=$1
    local -n _rclear_meta=$2

    local capacity="${_rclear_meta[0]}"
    _rclear_ring=()
    _rclear_meta=("$capacity" 0 0)
    return 0
}

# -----------------------------------------------------------------------------
# ring_to_array - Convert ring buffer to regular array
# -----------------------------------------------------------------------------
# @description Copy ring buffer contents to array in FIFO order
# @pre         none
# @post        buffer unchanged, output contains elements oldest-to-newest
# @idempotent  Yes
# @param       $1 ring - Ring buffer data array (nameref)
# @param       $2 meta - Ring buffer metadata array (nameref)
# @param       $3 output - Output array (nameref)
# @return      0 on success
#
# Usage:
#   ring_to_array mybuffer mybuffer_meta result
# -----------------------------------------------------------------------------
ring_to_array() {
    local -n _rta_ring=$1
    local -n _rta_meta=$2
    local -n _rta_output=$3

    local capacity="${_rta_meta[0]}"
    local head="${_rta_meta[1]}"
    local count="${_rta_meta[2]}"

    _rta_output=()

    local i idx
    for (( i = 0; i < count; i++ )); do
        idx=$(( (head + i) % capacity ))
        _rta_output+=("${_rta_ring[$idx]}")
    done

    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# queue_drain - Remove all elements and return as array
# -----------------------------------------------------------------------------
# @description Pop all elements from queue into output array
# @pre         none
# @post        queue is empty, output contains all elements
# @idempotent  No - empties the queue
# @param       $1 queue - Queue array (nameref)
# @param       $2 output - Output array (nameref)
# @return      0 on success
#
# Usage:
#   queue_drain myqueue result
# -----------------------------------------------------------------------------
queue_drain() {
    local -n _qd_queue=$1
    local -n _qd_output=$2

    _qd_output=("${_qd_queue[@]}")
    _qd_queue=()
    return 0
}

# -----------------------------------------------------------------------------
# queue_each - Iterate over queue with callback
# -----------------------------------------------------------------------------
# @description Call function for each element without modifying queue
# @pre         callback is a valid function
# @post        queue unchanged, callback called for each element
# @idempotent  Yes (if callback is idempotent)
# @param       $1 queue - Queue array (nameref)
# @param       $2 callback - Function to call for each element
# @return      0 on success, 1 on invalid callback
#
# Usage:
#   process_item() { echo "Processing: $1"; }
#   queue_each myqueue process_item
# -----------------------------------------------------------------------------
queue_each() {
    local -n _qe_queue=$1
    local callback="$2"

    if [[ "$QUEUE_CONTRACTS" == "1" ]]; then
        if ! _queue_is_callable "$callback"; then
            _queue_error 1 "callback '$callback' is not a valid function"
            return 1
        fi
    fi

    local elem
    for elem in "${_qe_queue[@]}"; do
        "$callback" "$elem"
    done

    return 0
}

# -----------------------------------------------------------------------------
# queue_filter - Filter queue elements in place
# -----------------------------------------------------------------------------
# @description Keep only elements matching predicate
# @pre         predicate is a valid function returning 0 to keep
# @post        queue contains only matching elements
# @idempotent  Yes
# @param       $1 queue - Queue array (nameref)
# @param       $2 predicate - Function returning 0 to keep element
# @return      0 on success, 1 on invalid predicate
#
# Usage:
#   is_positive() { (( $1 > 0 )); }
#   queue_filter myqueue is_positive
# -----------------------------------------------------------------------------
queue_filter() {
    local -n _qf_queue=$1
    local predicate="$2"

    if [[ "$QUEUE_CONTRACTS" == "1" ]]; then
        if ! _queue_is_callable "$predicate"; then
            _queue_error 1 "predicate '$predicate' is not a valid function"
            return 1
        fi
    fi

    local result=()
    local elem
    for elem in "${_qf_queue[@]}"; do
        if "$predicate" "$elem"; then
            result+=("$elem")
        fi
    done

    _qf_queue=("${result[@]}")
    return 0
}

# -----------------------------------------------------------------------------
# queue_to_json - Serialize queue to JSON array
# -----------------------------------------------------------------------------
# @description Convert queue contents to JSON array format
# @pre         none
# @post        queue unchanged
# @idempotent  Yes
# @param       $1 queue - Queue array (nameref)
# @stdout      JSON array ["elem1","elem2",...]
# @return      0 on success
#
# Usage:
#   json=$(queue_to_json myqueue)
# -----------------------------------------------------------------------------
queue_to_json() {
    local -n _qtj_queue=$1

    local first=true
    printf '['

    local elem
    for elem in "${_qtj_queue[@]}"; do
        $first || printf ','
        first=false

        local escaped
        escaped=$(_queue_escape_json "$elem")
        printf '"%s"' "$escaped"
    done

    printf ']'
    return 0
}

# -----------------------------------------------------------------------------
# queue_from_json - Deserialize JSON array to queue
# -----------------------------------------------------------------------------
# @description Parse JSON array and populate queue
# @pre         json is a valid JSON array of strings
# @post        queue contains parsed elements
# @idempotent  Yes - replaces existing contents
# @param       $1 queue - Queue array (nameref)
# @param       $2 json - JSON array string
# @return      0 on success, 1 on parse error
#
# Usage:
#   queue_from_json myqueue '["a","b","c"]'
# -----------------------------------------------------------------------------
queue_from_json() {
    local -n _qfj_queue=$1
    local json="$2"

    _qfj_queue=()

    # Remove outer brackets
    json="${json#[}"
    json="${json%]}"

    # Handle empty array
    [[ -z "${json// /}" ]] && return 0

    # Parse string elements
    local in_string=false
    local current=""
    local escaped=false
    local char
    local i

    for (( i = 0; i < ${#json}; i++ )); do
        char="${json:i:1}"

        if $escaped; then
            current+="$char"
            escaped=false
            continue
        fi

        if [[ "$char" == '\' ]]; then
            escaped=true
            continue
        fi

        if [[ "$char" == '"' ]]; then
            if $in_string; then
                # End of string
                _qfj_queue+=("$current")
                current=""
                in_string=false
            else
                # Start of string
                in_string=true
            fi
            continue
        fi

        if $in_string; then
            current+="$char"
        fi
    done

    return 0
}

# -----------------------------------------------------------------------------
# pqueue_to_json - Serialize priority queue to JSON
# -----------------------------------------------------------------------------
# @description Convert priority queue to JSON array of objects
# @pre         none
# @post        queue unchanged
# @idempotent  Yes
# @param       $1 pqueue - Priority queue array (nameref)
# @stdout      JSON array [{"priority":N,"value":"..."},...]
# @return      0 on success
#
# Usage:
#   json=$(pqueue_to_json mypqueue)
# -----------------------------------------------------------------------------
pqueue_to_json() {
    local -n _pqtj_pqueue=$1

    local first=true
    printf '['

    local entry priority value
    for entry in "${_pqtj_pqueue[@]}"; do
        $first || printf ','
        first=false

        priority="${entry%%:*}"
        value="${entry#*:}"
        local escaped_value
        escaped_value=$(_queue_escape_json "$value")

        printf '{"priority":%d,"value":"%s"}' "$priority" "$escaped_value"
    done

    printf ']'
    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

QUEUE_EXPORTS=(
    # Queue (FIFO)
    queue_create queue_push queue_pop queue_pop_v
    queue_peek queue_peek_v queue_peek_back
    queue_size queue_is_empty queue_clear
    queue_to_array queue_from_array

    # Stack (LIFO)
    stack_create stack_push stack_pop stack_pop_v
    stack_peek stack_peek_v
    stack_size stack_is_empty stack_clear stack_reverse
    stack_to_array

    # Deque (double-ended)
    deque_create
    deque_push_front deque_push_back
    deque_pop_front deque_pop_front_v deque_pop_back deque_pop_back_v
    deque_peek_front deque_peek_back
    deque_size deque_is_empty deque_clear
    deque_rotate_left deque_rotate_right

    # Priority Queue
    pqueue_create pqueue_push pqueue_pop pqueue_pop_v
    pqueue_peek pqueue_peek_priority
    pqueue_size pqueue_is_empty pqueue_clear
    pqueue_update_priority

    # Ring Buffer
    ring_create ring_push ring_pop ring_pop_v ring_peek
    ring_size ring_capacity
    ring_is_empty ring_is_full ring_clear
    ring_to_array

    # Utilities
    queue_drain queue_each queue_filter
    queue_to_json queue_from_json pqueue_to_json
)
