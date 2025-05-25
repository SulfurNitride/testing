#!/bin/bash
# -------------------------------------------------------------------
# error.sh
# Error handling functions for MO2 Helper
# -------------------------------------------------------------------

# Error context tracking
declare -a ERROR_CONTEXT_STACK=()

# Push error context
push_error_context() {
    local context="$1"
    ERROR_CONTEXT_STACK+=("$context")
}

# Pop error context
pop_error_context() {
    if [ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]; then
        unset 'ERROR_CONTEXT_STACK[-1]'
    fi
}

# Get current error context
get_error_context() {
    if [ ${#ERROR_CONTEXT_STACK[@]} -gt 0 ]; then
        echo "${ERROR_CONTEXT_STACK[-1]}"
    else
        echo "Unknown context"
    fi
}

# Enhanced error handler with context
handle_error() {
    local error_message="$1"
    local exit_script=${2:-true}
    local error_code=${3:-1}
    local help_message="$4"

    # Add context to error message
    local context=$(get_error_context)
    LAST_ERROR="[$context] $error_message"

    log_error "$LAST_ERROR"

    # Display error with formatting
    echo -e "\n${color_red}═══ ERROR ═══${color_reset}"
    echo -e "${color_red}Context:${color_reset} $context"
    echo -e "${color_red}Error:${color_reset} $error_message"

    if [ -n "$help_message" ]; then
        echo -e "${color_yellow}Help:${color_reset} $help_message"
    fi

    # Suggest checking logs
    echo -e "\n${color_yellow}For more details, check the log file:${color_reset}"
    echo -e "${color_blue}$log_file${color_reset}"

    # Offer to show recent log entries
    if confirm_action "Show recent log entries?"; then
        echo -e "\n${color_header}Recent log entries:${color_reset}"
        tail -n 20 "$log_file" | grep -E "(ERROR|WARNING)" || echo "No recent errors/warnings found"
    fi

    if $exit_script; then
        # Clean up before exit
        cleanup
        exit $error_code
    fi
}

# Lazy loading for modules
declare -A LOADED_MODULES=()

# Load module only when needed
load_module() {
    local module_name="$1"
    local module_path="$LIB_DIR/$module_name"

    # Check if already loaded
    if [ "${LOADED_MODULES[$module_name]}" = "1" ]; then
        return 0
    fi

    # Check if module exists
    if [ ! -f "$module_path" ]; then
        log_error "Module not found: $module_path"
        return 1
    fi

    # Load the module
    push_error_context "Loading module: $module_name"
    if source "$module_path"; then
        LOADED_MODULES[$module_name]="1"
        log_info "Loaded module: $module_name"
        pop_error_context
        return 0
    else
        pop_error_context
        log_error "Failed to load module: $module_name"
        return 1
    fi
}

# Cache for expensive operations
declare -A OPERATION_CACHE=()
CACHE_TTL=300  # 5 minutes

# Get cached result or execute operation
get_cached_or_execute() {
    local cache_key="$1"
    local ttl="${2:-$CACHE_TTL}"
    shift 2
    local command=("$@")

    # Check if cached and not expired
    local cached_entry="${OPERATION_CACHE[$cache_key]}"
    if [ -n "$cached_entry" ]; then
        local cached_time="${cached_entry%%:*}"
        local cached_value="${cached_entry#*:}"
        local current_time=$(date +%s)

        if [ $((current_time - cached_time)) -lt $ttl ]; then
            log_info "Using cached result for: $cache_key"
            echo "$cached_value"
            return 0
        fi
    fi

    # Execute command and cache result
    local result
    if result=$("${command[@]}" 2>&1); then
        OPERATION_CACHE[$cache_key]="$(date +%s):$result"
        echo "$result"
        return 0
    else
        log_error "Failed to execute: ${command[*]}"
        return 1
    fi
}

# Improved dependency checking with detailed reporting
check_dependencies() {
    push_error_context "Dependency Check"
    log_info "Checking dependencies"

    local missing_deps=()
    local optional_deps=()

    # Required dependencies
    local required_cmds=(
        "bash:4.0:Bash shell"
        "protontricks::Proton tricks for game management"
        "curl:or:wget:Download tool"
        "jq::JSON processor"
        "mktemp::Temporary file creation"
    )

    # Optional dependencies
    local optional_cmds=(
        "7z:or:7za:or:7zr:or:p7zip:7-Zip for archive extraction"
        "notify-send::Desktop notifications"
        "xdg-mime::MIME type registration"
    )

    # Check required dependencies
    echo -e "${color_header}Checking required dependencies...${color_reset}"
    for dep_spec in "${required_cmds[@]}"; do
        local parts=()
        IFS=':' read -ra parts <<< "$dep_spec"
        local found=false

        for ((i=0; i<${#parts[@]}; i+=2)); do
            local cmd="${parts[i]}"
            if [ "$cmd" = "or" ]; then
                continue
            fi

            if command_exists "$cmd"; then
                found=true
                break
            fi
        done

        if ! $found; then
            local desc="${parts[-1]}"
            missing_deps+=("$desc")
            echo -e "${color_red}✗${color_reset} $desc"
        else
            echo -e "${color_green}✓${color_reset} ${parts[-1]}"
        fi
    done

    # Check optional dependencies
    echo -e "\n${color_header}Checking optional dependencies...${color_reset}"
    for dep_spec in "${optional_cmds[@]}"; do
        local parts=()
        IFS=':' read -ra parts <<< "$dep_spec"
        local found=false

        for ((i=0; i<${#parts[@]}; i+=2)); do
            local cmd="${parts[i]}"
            if [ "$cmd" = "or" ]; then
                continue
            fi

            if command_exists "$cmd"; then
                found=true
                break
            fi
        done

        if ! $found; then
            local desc="${parts[-1]}"
            optional_deps+=("$desc")
            echo -e "${color_yellow}○${color_reset} $desc (optional)"
        else
            echo -e "${color_green}✓${color_reset} ${parts[-1]}"
        fi
    done

    # Handle missing required dependencies
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "\n${color_red}Missing required dependencies:${color_reset}"
        for dep in "${missing_deps[@]}"; do
            echo -e "  - $dep"
        done

        pop_error_context
        error_exit "Required dependencies are missing. Please install them before continuing."
    fi

    # Suggest optional dependencies
    if [ ${#optional_deps[@]} -gt 0 ]; then
        echo -e "\n${color_yellow}Optional dependencies not installed:${color_reset}"
        for dep in "${optional_deps[@]}"; do
            echo -e "  - $dep"
        done
        echo -e "\nThese are not required but may improve functionality."
    fi

    pop_error_context
    return 0
}

# Transaction-like operations with rollback
declare -A TRANSACTION_ACTIONS=()
TRANSACTION_ACTIVE=false

# Start a transaction
start_transaction() {
    local name="$1"

    if $TRANSACTION_ACTIVE; then
        log_error "Transaction already active"
        return 1
    fi

    TRANSACTION_ACTIVE=true
    TRANSACTION_ACTIONS=()

    log_info "Started transaction: $name"
    push_error_context "Transaction: $name"

    return 0
}

# Add rollback action to transaction
add_rollback_action() {
    local action="$1"

    if ! $TRANSACTION_ACTIVE; then
        log_error "No active transaction"
        return 1
    fi

    local index=${#TRANSACTION_ACTIONS[@]}
    TRANSACTION_ACTIONS[$index]="$action"

    return 0
}

# Commit transaction
commit_transaction() {
    if ! $TRANSACTION_ACTIVE; then
        log_error "No active transaction"
        return 1
    fi

    TRANSACTION_ACTIVE=false
    TRANSACTION_ACTIONS=()
    pop_error_context

    log_info "Transaction committed successfully"
    return 0
}

# Rollback transaction
rollback_transaction() {
    if ! $TRANSACTION_ACTIVE; then
        log_error "No active transaction"
        return 1
    fi

    log_info "Rolling back transaction..."

    # Execute rollback actions in reverse order
    for ((i=${#TRANSACTION_ACTIONS[@]}-1; i>=0; i--)); do
        local action="${TRANSACTION_ACTIONS[$i]}"
        log_info "Executing rollback: $action"
        eval "$action" || log_error "Rollback action failed: $action"
    done

    TRANSACTION_ACTIVE=false
    TRANSACTION_ACTIONS=()
    pop_error_context

    log_info "Transaction rolled back"
    return 0
}

# Function to handle errors in a standard way
handle_error() {
    local error_message="$1"
    local exit_script=${2:-true}
    local error_code=${3:-1}

    LAST_ERROR="$error_message"
    log_error "$error_message"

    echo -e "\n${color_red}ERROR: $error_message${color_reset}"

    # Show additional help if available
    if [ -n "$4" ]; then
        echo -e "${color_yellow}HELP: $4${color_reset}"
    fi

    # Allow user to view the log
    echo -e "\nWould you like to view the recent log entries to help diagnose the issue?"
    if confirm_action "View logs?"; then
        view_logs
    fi

    if $exit_script; then
        exit $error_code
    fi
}

# Function to show error message, log it, and exit
error_exit() {
    handle_error "$1" true 1
}

# Function to check disk space before operations
check_disk_space() {
    local required_mb=$1
    local path=${2:-$HOME}

    log_info "Checking for $required_mb MB of free space in $path"

    # Get available space in MB
    local available_kb=$(df -k "$path" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))

    if [ $available_mb -lt $required_mb ]; then
        handle_error "Insufficient disk space. Need ${required_mb}MB but only ${available_mb}MB available in $path" \
            false
        return 1
    fi

    log_info "Sufficient disk space available: $available_mb MB"
    return 0
}
