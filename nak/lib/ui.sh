# Enhanced UI functions with breadcrumb navigation and better UX

# Navigation stack for breadcrumbs
declare -a NAVIGATION_STACK=("Main Menu")

# Push to navigation stack
push_navigation() {
    local menu_name="$1"
    NAVIGATION_STACK+=("$menu_name")
}

# Pop from navigation stack
pop_navigation() {
    if [ ${#NAVIGATION_STACK[@]} -gt 1 ]; then
        unset 'NAVIGATION_STACK[-1]'
    fi
}

# Get navigation breadcrumb
get_breadcrumb() {
    local breadcrumb=""
    for ((i=0; i<${#NAVIGATION_STACK[@]}; i++)); do
        if [ $i -gt 0 ]; then
            breadcrumb+=" > "
        fi
        breadcrumb+="${NAVIGATION_STACK[$i]}"
    done
    echo "$breadcrumb"
}

# Enhanced header with breadcrumb
print_header() {
    clear

    # Get terminal width for centering
    local term_width=$(tput cols 2>/dev/null || echo 80)

    # Title
    local title="NaK - Linux Modding Helper"
    local title_len=${#title}
    local padding=$(( (term_width - title_len) / 2 ))

    echo -e "${color_title}$(printf '%*s' $padding '')$title${color_reset}"
    echo -e "${color_title}$(printf '═%.0s' $(seq 1 $term_width))${color_reset}"

    # Version and date
    echo -e "${color_desc}Version $SCRIPT_VERSION | $SCRIPT_DATE${color_reset}"

    # Breadcrumb navigation
    local breadcrumb=$(get_breadcrumb)
    echo -e "${color_blue}📍 $breadcrumb${color_reset}"
    echo -e "${color_title}$(printf '─%.0s' $(seq 1 $term_width))${color_reset}\n"
}

# Enhanced menu with better formatting and validation
display_menu() {
    local title=$1
    shift
    local options=("$@")
    local choice
    local max_option=$(( ${#options[@]} / 2 ))

    print_section "$title"

    # Display menu options with better formatting
    for ((i=0; i<${#options[@]}; i+=2)); do
        local option_num=$((i/2+1))
        local option_title="${options[i]}"
        local option_desc="${options[i+1]}"

        # Add visual indicators for special options
        local indicator=""
        if [[ "$option_title" == *"Back"* ]] || [[ "$option_title" == *"Exit"* ]]; then
            indicator="↩ "
        elif [[ "$option_title" == *"Download"* ]]; then
            indicator="⬇ "
        elif [[ "$option_title" == *"Install"* ]]; then
            indicator="📦 "
        elif [[ "$option_title" == *"Configure"* ]] || [[ "$option_title" == *"Setup"* ]]; then
            indicator="⚙ "
        fi

        echo -e "${color_option}$indicator$option_num. $option_title${color_reset}"
        echo -e "   ${color_desc}$option_desc${color_reset}"
    done

    # Input validation with better error messages
    while true; do
        # Show input prompt with range
        echo
        read -rp "$(echo -e "${color_yellow}Select an option [1-$max_option]: ${color_reset}")" choice

        # Validate input
        if [[ -z "$choice" ]]; then
            echo -e "${color_red}Please enter a number${color_reset}"
            continue
        fi

        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${color_red}Invalid input: '$choice' is not a number${color_reset}"
            continue
        fi

        if (( choice < 1 || choice > max_option )); then
            echo -e "${color_red}Invalid choice: $choice. Please select between 1 and $max_option${color_reset}"
            continue
        fi

        # Valid choice
        return $choice
    done
}

# Progress bar with ETA
show_progress_with_eta() {
    local current=$1
    local total=$2
    local start_time=$3
    local task_name="${4:-Processing}"

    local width=40
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))

    # Calculate ETA
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    local eta_seconds=0

    if [ $current -gt 0 ]; then
        eta_seconds=$(( (elapsed * total / current) - elapsed ))
    fi

    # Format time
    local eta_formatted="--:--"
    if [ $eta_seconds -gt 0 ]; then
        local eta_mins=$((eta_seconds / 60))
        local eta_secs=$((eta_seconds % 60))
        eta_formatted=$(printf "%02d:%02d" $eta_mins $eta_secs)
    fi

    # Build progress bar
    local bar="["
    for ((i=0; i<completed; i++)); do
        bar+="█"
    done
    for ((i=0; i<remaining; i++)); do
        bar+="░"
    done
    bar+="]"

    # Print progress bar with task name and ETA
    printf "\r%-20s %s %3d%% ETA: %s" "$task_name" "$bar" "$percentage" "$eta_formatted"

    # Print newline if complete
    if [ $current -eq $total ]; then
        echo
    fi
}

# Interactive file/directory selector
select_file_or_directory() {
    local prompt="$1"
    local start_path="${2:-$HOME}"
    local type="${3:-all}"  # all, file, directory

    echo -e "${color_header}$prompt${color_reset}"
    echo -e "${color_desc}Navigate with numbers, '..' to go up, or enter full path${color_reset}\n"

    local current_path="$start_path"

    while true; do
        # Show current path
        echo -e "${color_blue}📁 Current: $current_path${color_reset}"

        # List contents
        local items=()
        local item_types=()
        local index=1

        # Add parent directory option if not at root
        if [ "$current_path" != "/" ]; then
            echo -e "${color_option}0. .. (Parent Directory)${color_reset}"
        fi

        # List directories first
        while IFS= read -r -d '' item; do
            local basename=$(basename "$item")
            if [ -d "$item" ]; then
                echo -e "${color_option}$index. 📁 $basename/${color_reset}"
                items+=("$item")
                item_types+=("directory")
                ((index++))
            fi
        done < <(find "$current_path" -maxdepth 1 -type d -not -path "$current_path" -print0 | sort -z)

        # List files if not directory-only mode
        if [ "$type" != "directory" ]; then
            while IFS= read -r -d '' item; do
                local basename=$(basename "$item")
                local size=$(du -h "$item" 2>/dev/null | cut -f1)
                echo -e "${color_option}$index. 📄 $basename ${color_desc}($size)${color_reset}"
                items+=("$item")
                item_types+=("file")
                ((index++))
            done < <(find "$current_path" -maxdepth 1 -type f -print0 | sort -z)
        fi

        # Get user input
        echo
        read -rp "Selection (number/path/'done' to confirm): " choice

        # Handle different input types
        if [ "$choice" = "done" ]; then
            if [ "$type" = "file" ] && [ ! -f "$current_path" ]; then
                echo -e "${color_red}Please select a file${color_reset}"
                continue
            elif [ "$type" = "directory" ] && [ ! -d "$current_path" ]; then
                echo -e "${color_red}Please select a directory${color_reset}"
                continue
            fi
            echo "$current_path"
            return 0

        elif [ "$choice" = "0" ] && [ "$current_path" != "/" ]; then
            # Go to parent directory
            current_path=$(dirname "$current_path")

        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#items[@]} ]; then
            # Select numbered item
            local selected_item="${items[$((choice-1))]}"
            local selected_type="${item_types[$((choice-1))]}"

            if [ "$selected_type" = "directory" ]; then
                current_path="$selected_item"
            else
                # File selected
                if [ "$type" = "directory" ]; then
                    echo -e "${color_red}Please select a directory${color_reset}"
                else
                    current_path="$selected_item"
                    echo "$current_path"
                    return 0
                fi
            fi

        elif [ -e "$choice" ]; then
            # Full path entered
            if [ "$type" = "file" ] && [ ! -f "$choice" ]; then
                echo -e "${color_red}Not a file: $choice${color_reset}"
            elif [ "$type" = "directory" ] && [ ! -d "$choice" ]; then
                echo -e "${color_red}Not a directory: $choice${color_reset}"
            else
                current_path=$(realpath "$choice")
            fi

        else
            echo -e "${color_red}Invalid selection: $choice${color_reset}"
        fi

        echo  # Empty line for readability
    done
}

# Confirmation dialog with default option
confirm_action() {
    local prompt="${1:-Continue?}"
    local default="${2:-y}"  # y or n

    local options="[y/n]"
    if [ "$default" = "y" ]; then
        options="[Y/n]"
    elif [ "$default" = "n" ]; then
        options="[y/N]"
    fi

    while true; do
        read -rp "$(echo -e "${color_yellow}$prompt $options: ${color_reset}")" yn

        # Handle default on empty input
        if [ -z "$yn" ]; then
            yn="$default"
        fi

        case ${yn,,} in  # Convert to lowercase
            y|yes) return 0;;
            n|no) return 1;;
            *) echo -e "${color_red}Please answer yes (y) or no (n)${color_reset}";;
        esac
    done
}

# Print section header
print_section() {
    echo -e "\n${color_header}=== $1 ===${color_reset}"
}

# Format menu option
format_option() {
    local number=$1
    local title=$2
    local description=$3
    echo -e "${color_option}$number. $title${color_reset}"
    echo -e "   ${color_desc}$description${color_reset}"
}

# Confirmation prompt
confirm_action() {
    local prompt=${1:-"Continue?"}
    while true; do
        read -rp "$prompt [y/n]: " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

# Function to pause and wait for user to press a key
pause() {
    local message=${1:-"Press any key to continue..."}
    echo -e "\n${color_desc}$message${color_reset}"
    read -n 1 -s
}

# Improved menu function with back option and descriptions
display_menu() {
    local title=$1
    shift
    local options=("$@")
    local choice

    print_section "$title"

    # Display menu options with descriptions
    for ((i=0; i<${#options[@]}; i+=2)); do
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            # Last option is "back" or "exit"
            echo ""
        fi
        format_option "$((i/2+1))" "${options[i]}" "${options[i+1]}"
    done

    # Calculate the maximum valid option number
    local max_option=$(( ${#options[@]} / 2 ))

    # Get user choice
    while true; do
        read -rp $'\nSelect an option (1-'$max_option'): ' choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max_option )); then
            return $choice
        else
            echo "Invalid choice. Please try again."
        fi
    done
}

# Display a notification with optional timeout
notify() {
    local message="$1"
    local wait_for_key=true

    if [ -n "$2" ]; then
        wait_for_key="$2"
    fi

    echo -e "\n${color_yellow}$message${color_reset}"

    if [ "$wait_for_key" = true ]; then
        echo -e "\nPress any key to continue..."
        read -n 1 -s
    fi
}

# Select from a list with pagination
select_from_list() {
    local title=$1
    shift
    local items=("$@")
    local page_size=10
    # Global variable to store selection
    SELECTION_RESULT=0

    if [ ${#items[@]} -eq 0 ]; then
        echo "No items to display."
        SELECTION_RESULT=0
        return 0
    fi

    local total_items=${#items[@]}
    local total_pages=$(( (total_items + page_size - 1) / page_size ))
    local current_page=1
    local choice

    while true; do
        print_section "$title (Page $current_page of $total_pages)"

        # Calculate start and end for current page
        local start=$(( (current_page - 1) * page_size + 1 ))
        local end=$(( current_page * page_size ))
        if (( end > ${#items[@]} )); then
            end=${#items[@]}
        fi

        # Display items for current page
        for ((i=start-1; i<end; i++)); do
            echo -e "${color_option}$((i+1)).${color_reset} ${items[i]}"
        done

        echo -e "\n${color_desc}[n] Next page | [p] Previous page | [b] Back${color_reset}"

        read -rp "Selection: " choice

        case "$choice" in
            [0-9]*)
                if (( choice >= start && choice <= end )); then
                    SELECTION_RESULT=$choice
                    return 0
                else
                    echo "Invalid selection. Please choose a number from the current page."
                fi
                ;;
            [nN])
                if (( current_page < total_pages )); then
                    ((current_page++))
                else
                    echo "Already on the last page."
                fi
                ;;
            [pP])
                if (( current_page > 1 )); then
                    ((current_page--))
                else
                    echo "Already on the first page."
                fi
                ;;
            [bB])
                SELECTION_RESULT=0
                return 0
                ;;
            *)
                echo "Invalid input. Try again."
                ;;
        esac
    done
}

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((current * width / total))
    local remaining=$((width - completed))

    # Build progress bar
    local bar="["
    for ((i=0; i<completed; i++)); do
        bar+="#"
    done

    for ((i=0; i<remaining; i++)); do
        bar+="."
    done
    bar+="] $percentage%"

    # Print progress bar (with carriage return to overwrite)
    echo -ne "\r$bar"

    # Print newline if operation is complete
    if [ $current -eq $total ]; then
        echo ""
    fi
}

# Get terminal width
get_terminal_width() {
    # Try tput first, fallback to COLUMNS, then default to 80
    local width
    if command -v tput >/dev/null 2>&1; then
        width=$(tput cols 2>/dev/null)
    fi

    if [ -z "$width" ] || [ "$width" -eq 0 ]; then
        width=${COLUMNS:-80}
    fi

    echo "$width"
}

# Center text
center_text() {
    local text="$1"
    local width="${2:-$(get_terminal_width)}"

    # Remove color codes for length calculation
    local clean_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local text_len=${#clean_text}

    if [ $text_len -ge $width ]; then
        echo "$text"
        return
    fi

    local padding=$(( (width - text_len) / 2 ))
    printf "%*s%s\n" $padding "" "$text"
}

# Create a line spanning terminal width
create_line() {
    local char="${1:-─}"
    local width="${2:-$(get_terminal_width)}"
    printf "%${width}s\n" | tr ' ' "$char"
}

# Create a box around text
create_box() {
    local text="$1"
    local width="${2:-$(get_terminal_width)}"

    # Box drawing characters
    local top_left="╭"
    local top_right="╮"
    local bottom_left="╰"
    local bottom_right="╯"
    local horizontal="─"
    local vertical="│"

    # Remove color codes for length calculation
    local clean_text=$(echo -e "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local text_len=${#clean_text}
    local box_width=$((text_len + 4))  # 2 spaces padding + 2 borders

    if [ $box_width -gt $width ]; then
        box_width=$width
    fi

    # Center the box
    local box_padding=$(( (width - box_width) / 2 ))
    local prefix=$(printf "%*s" $box_padding "")

    # Top border
    echo -n "$prefix$top_left"
    printf "%$((box_width - 2))s" | tr ' ' "$horizontal"
    echo "$top_right"

    # Text line
    echo -n "$prefix$vertical "
    echo -n "$text"
    local text_padding=$((box_width - text_len - 4))
    printf "%*s" $text_padding ""
    echo " $vertical"

    # Bottom border
    echo -n "$prefix$bottom_left"
    printf "%$((box_width - 2))s" | tr ' ' "$horizontal"
    echo "$bottom_right"
}

# Enhanced header with centered text and full-width lines
print_header() {
    clear

    local term_width=$(get_terminal_width)

    # Create full-width header
    echo -e "${color_title}$(create_line '═' $term_width)${color_reset}"

    # Center the title
    center_text "${color_title}NaK - Linux Modding Helper${color_reset}" $term_width

    # Another full-width line
    echo -e "${color_title}$(create_line '═' $term_width)${color_reset}"

    # Center version info
    center_text "${color_desc}Version $SCRIPT_VERSION | $SCRIPT_DATE${color_reset}" $term_width

    # Breadcrumb navigation (if available)
    if declare -F get_breadcrumb >/dev/null 2>&1; then
        local breadcrumb=$(get_breadcrumb)
        center_text "${color_blue}📍 $breadcrumb${color_reset}" $term_width
    fi

    # Bottom separator
    echo -e "${color_title}$(create_line '─' $term_width)${color_reset}"
    echo
}

# Enhanced section header spanning terminal width
print_section() {
    local title="$1"
    local term_width=$(get_terminal_width)

    echo
    echo -e "${color_header}$(create_line '─' $term_width)${color_reset}"
    center_text "${color_header}$title${color_reset}" $term_width
    echo -e "${color_header}$(create_line '─' $term_width)${color_reset}"
    echo
}

# Fancy title with box
print_fancy_title() {
    local title="$1"
    local subtitle="${2:-}"
    local term_width=$(get_terminal_width)

    clear
    echo
    echo

    # Main title in a box
    create_box "${color_title}$title${color_reset}" $term_width

    if [ -n "$subtitle" ]; then
        echo
        center_text "${color_desc}$subtitle${color_reset}" $term_width
    fi

    echo
    echo
}

# Progress bar spanning terminal width
show_full_width_progress() {
    local current=$1
    local total=$2
    local task_name="${3:-Processing}"

    local term_width=$(get_terminal_width)
    local bar_width=$((term_width - 30))  # Leave space for percentage and task name

    local percentage=$((current * 100 / total))
    local completed=$((current * bar_width / total))
    local remaining=$((bar_width - completed))

    # Build progress bar
    local bar="["
    for ((i=0; i<completed; i++)); do
        bar+="█"
    done
    for ((i=0; i<remaining; i++)); do
        bar+="░"
    done
    bar+="]"

    # Clear line and print progress
    printf "\r%-15s %s %3d%%" "$task_name" "$bar" "$percentage"

    if [ $current -eq $total ]; then
        echo
    fi
}

# Menu with centered options
display_centered_menu() {
    local title=$1
    shift
    local options=("$@")
    local term_width=$(get_terminal_width)

    print_section "$title"

    # Display menu options centered
    for ((i=0; i<${#options[@]}; i+=2)); do
        local option_num=$((i/2+1))
        local option_title="${options[i]}"
        local option_desc="${options[i+1]}"

        # Center the option
        local option_text="${color_option}$option_num. $option_title${color_reset}"
        center_text "$option_text" $term_width

        # Center the description
        local desc_text="${color_desc}$option_desc${color_reset}"
        center_text "$desc_text" $term_width
        echo
    done

    # Get user choice
    local max_option=$(( ${#options[@]} / 2 ))
    while true; do
        local prompt="${color_yellow}Select an option [1-$max_option]: ${color_reset}"
        read -rp "$(center_text "$prompt" $term_width)" choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= max_option )); then
            return $choice
        else
            center_text "${color_red}Invalid choice. Please try again.${color_reset}" $term_width
        fi
    done
}

# ASCII art banner (optional fun addition)
print_ascii_banner() {
    local term_width=$(get_terminal_width)

    # Simple ASCII art that scales
    if [ $term_width -ge 80 ]; then
        cat << 'EOF'
    _   _       _  __
   | \ | |     | |/ /
   |  \| | __ _| ' /
   | . ` |/ _` |  <
   | |\  | (_| | . \
   |_| \_|\__,_|_|\_\

   Linux Modding Helper
EOF
    else
        # Smaller version for narrow terminals
        echo "NaK"
        echo "Linux Modding Helper"
    fi
}

# Spinner animation for long-running tasks
spinner() {
    local pid=$1
    local message=${2:-"Processing..."}
    local delay=0.1
    local spinstr='-\|/'  # Simple ASCII spinner instead of Unicode characters

    while [ "$(ps a | awk '{print $1}' | grep -w $pid)" ]; do
        local temp=${spinstr#?}
        printf "\r[%c] %s" "$spinstr" "$message"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r    \r"
}

# Function to track and report progress of a time-consuming operation
start_progress_tracking() {
    local operation_name="$1"
    local expected_duration=${2:-60}  # Default 60 seconds

    CURRENT_OPERATION="$operation_name"
    local start_time=$(date +%s)
    local tracker_file="/tmp/mo2helper_progress_$$"

    # Add to temp files for cleanup
    TEMP_FILES+=("$tracker_file")

    # Write start time to tracker file
    echo "$start_time" > "$tracker_file"
    echo "$expected_duration" >> "$tracker_file"
    echo "$operation_name" >> "$tracker_file"

    log_info "Started operation: $operation_name (expected duration: ${expected_duration}s)"

    # Return the tracker file path for later use
    echo "$tracker_file"
}

# Update progress
update_progress() {
    local tracker_file="$1"
    local current_step="$2"
    local total_steps="$3"

    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        return 0
    fi

    if [ ! -f "$tracker_file" ]; then
        return 1
    fi

    # Update tracker file with progress info
    echo "$current_step" >> "$tracker_file"
    echo "$total_steps" >> "$tracker_file"

    # Calculate and show progress
    local percentage=$((current_step * 100 / total_steps))
    local start_time=$(head -n 1 "$tracker_file")
    local expected_duration=$(sed -n '2p' "$tracker_file")
    local operation_name=$(sed -n '3p' "$tracker_file")
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    # Estimate remaining time
    local remaining=0
    if [ $current_step -gt 0 ]; then
        remaining=$(( (elapsed * total_steps / current_step) - elapsed ))
    else
        remaining=$expected_duration
    fi

    # Format times
    local elapsed_fmt=$(printf "%02d:%02d" $((elapsed/60)) $((elapsed%60)))
    local remaining_fmt=$(printf "%02d:%02d" $((remaining/60)) $((remaining%60)))

    # Show progress
    echo -ne "\r[$percentage%] $operation_name - Elapsed: $elapsed_fmt, Remaining: $remaining_fmt"

    if [ $current_step -eq $total_steps ]; then
        echo -e "\n${color_green}Completed: $operation_name${color_reset}"
        log_info "Completed operation: $operation_name (took ${elapsed}s)"
    fi
}

# Function to end progress tracking
end_progress_tracking() {
    local tracker_file="$1"
    local success=${2:-true}

    if [ ! -f "$tracker_file" ]; then
        return 1
    fi

    local start_time=$(head -n 1 "$tracker_file")
    local operation_name=$(sed -n '3p' "$tracker_file")
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))

    # Format elapsed time
    local elapsed_fmt=$(printf "%02d:%02d" $((elapsed/60)) $((elapsed%60)))

    if $success; then
        echo -e "\n${color_green}Completed: $operation_name in $elapsed_fmt${color_reset}"
        log_info "Successfully completed operation: $operation_name (took ${elapsed}s)"
    else
        echo -e "\n${color_red}Failed: $operation_name after $elapsed_fmt${color_reset}"
        log_error "Failed operation: $operation_name (took ${elapsed}s)"
    fi

    CURRENT_OPERATION=""
    rm -f "$tracker_file"
}
