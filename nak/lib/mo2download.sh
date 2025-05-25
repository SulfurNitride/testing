#!/bin/bash
# -------------------------------------------------------------------
# mo2download.sh
# Functions for downloading and installing Mod Organizer 2
# -------------------------------------------------------------------

# Function to check if any system 7z tool is available
check_system_7z() {
    log_info "Checking for system 7z tools"
    
    # Check for various system 7zip tool names
    local zip_tools=("7z" "7za" "7zr" "7zip" "p7zip")
    
    for tool in "${zip_tools[@]}"; do
        if command_exists "$tool"; then
            log_info "Found system $tool command"
            return 0
        fi
    done
    
    log_info "No system 7z tools found"
    return 1
}

# Function to install py7zr Python package for 7z extraction
install_py7zr() {
    log_info "Installing py7zr Python package"

    # Get the portable Python binary
    local python_bin=$(get_portable_python)
    if [ $? -ne 0 ]; then
        handle_error "Failed to set up portable Python" false
        return 1
    fi

    # Create the pip directory if it doesn't exist
    local pip_dir="$PORTABLE_PYTHON_EXTRACT_DIR/bin"
    if [ ! -f "$pip_dir/pip" ]; then
        log_warning "Pip not found in expected location, installing pip"
        $python_bin -m ensurepip --upgrade
    fi

    # Install py7zr package
    log_info "Installing py7zr Python package..."
    if ! $python_bin -m pip install py7zr; then
        handle_error "Failed to install py7zr Python package" false
        return 1
    fi

    log_info "py7zr Python package installed successfully"
    return 0
}

# Function to check if py7zr package is installed
check_py7zr_installed() {
    log_info "Checking if py7zr Python package is installed"

    # Get the portable Python binary
    local python_bin=$(get_portable_python)
    if [ $? -ne 0 ]; then
        handle_error "Failed to set up portable Python" false
        return 1
    fi

    # Check if the py7zr package is installed
    if ! $python_bin -c "import py7zr" 2>/dev/null; then
        log_warning "py7zr Python package is not installed"
        return 1
    fi

    log_info "py7zr Python package is already installed"
    return 0
}

extract_7z_archive() {
    local archive_path="$1"
    local extract_to="$2"

    log_info "Extracting 7z archive: $archive_path to $extract_to"

    # Validate inputs
    if [ ! -f "$archive_path" ]; then
        log_error "Archive file not found: $archive_path"
        return 1
    fi

    # Create extraction directory
    mkdir -p "$extract_to" || {
        log_error "Failed to create extraction directory: $extract_to"
        return 1
    }

    # Try different 7zip tools in order of preference
    local extraction_successful=false

    # Method 1: Try 7z command (most common)
    if command_exists 7z; then
        log_info "Trying extraction with 7z command"
        if 7z x "$archive_path" -o"$extract_to" -y > /dev/null 2>&1; then
            extraction_successful=true
            log_info "Successfully extracted with 7z"
        fi
    fi

    # Method 2: Try 7za command
    if [ "$extraction_successful" = false ] && command_exists 7za; then
        log_info "Trying extraction with 7za command"
        if 7za x "$archive_path" -o"$extract_to" -y > /dev/null 2>&1; then
            extraction_successful=true
            log_info "Successfully extracted with 7za"
        fi
    fi

    # Method 3: Try 7zr command
    if [ "$extraction_successful" = false ] && command_exists 7zr; then
        log_info "Trying extraction with 7zr command"
        if 7zr x "$archive_path" -o"$extract_to" -y > /dev/null 2>&1; then
            extraction_successful=true
            log_info "Successfully extracted with 7zr"
        fi
    fi

    # Method 4: Try p7zip with proper syntax
    if [ "$extraction_successful" = false ] && command_exists p7zip; then
        log_info "Trying extraction with p7zip command"
        # p7zip has different syntax - it extracts to current directory
        local current_dir=$(pwd)
        cd "$extract_to" || {
            log_error "Failed to change to extraction directory"
            return 1
        }

        if p7zip -d "$archive_path" > /dev/null 2>&1; then
            extraction_successful=true
            log_info "Successfully extracted with p7zip"
        fi

        cd "$current_dir" || true
    fi

    # Method 5: Fall back to Python py7zr if no system tools worked
    if [ "$extraction_successful" = false ]; then
        log_info "No system 7z tools worked, falling back to py7zr"

        # Get the portable Python binary
        local python_bin=$(get_portable_python)
        if [ $? -ne 0 ]; then
            handle_error "Failed to set up portable Python" false
            return 1
        fi

        # Check for py7zr, install if needed
        if ! check_py7zr_installed; then
            log_info "py7zr not installed, trying to install"
            if ! install_py7zr; then
                handle_error "Failed to install Python 7z extractor and no system 7z available" false
                return 1
            fi
        fi

        # Create a temporary Python script for extraction
        local temp_script=$(create_temp_file "extract_7z" ".py")
        if [ -z "$temp_script" ]; then
            return 1
        fi

        cat > "$temp_script" << 'EOF'
import sys
import os
import py7zr

def extract_archive(archive_path, extract_to):
    try:
        # Ensure the extract directory exists
        os.makedirs(extract_to, exist_ok=True)

        # Extract the archive with progress callback
        extracted_count = 0

        def progress_callback(stat_info):
            nonlocal extracted_count
            extracted_count += 1
            if extracted_count % 100 == 0:
                print(f"Extracted {extracted_count} files...", end='\r')

        with py7zr.SevenZipFile(archive_path, mode='r') as archive:
            archive.extractall(path=extract_to, callback=progress_callback)

        print(f"\nSuccessfully extracted {extracted_count} files from {archive_path}")
        return True
    except Exception as e:
        print(f"Error extracting archive: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: script.py archive_path extract_to")
        sys.exit(1)

    archive_path = sys.argv[1]
    extract_to = sys.argv[2]

    if not extract_archive(archive_path, extract_to):
        sys.exit(1)
EOF

        # Run the extraction script
        if $python_bin "$temp_script" "$archive_path" "$extract_to"; then
            extraction_successful=true
            log_info "Successfully extracted with py7zr"
        else
            log_error "Failed to extract with py7zr"
        fi
    fi

    # Check if extraction was successful
    if [ "$extraction_successful" = false ]; then
        log_error "All extraction methods failed for: $archive_path"
        echo -e "${color_red}Failed to extract archive. Please install p7zip-full:${color_reset}"
        echo -e "${color_blue}sudo apt install p7zip-full${color_reset}"
        return 1
    fi

    # Verify extraction produced files
    if [ -z "$(ls -A "$extract_to" 2>/dev/null)" ]; then
        log_error "Extraction appeared successful but no files were extracted"
        return 1
    fi

    log_info "Archive extraction completed successfully"
    return 0
}

# Helper function to suggest 7z installation
suggest_7z_installation() {
    echo -e "\n${color_header}7-Zip tools not found${color_reset}"
    echo -e "To improve extraction performance, install 7-Zip tools:"
    echo -e "\nFor Debian/Ubuntu:"
    echo -e "${color_blue}sudo apt install p7zip-full${color_reset}"
    echo -e "\nFor Fedora:"
    echo -e "${color_blue}sudo dnf install p7zip p7zip-plugins${color_reset}"
    echo -e "\nFor Arch:"
    echo -e "${color_blue}sudo pacman -S p7zip${color_reset}"
}

# Function to download and install the latest Mod Organizer 2 release
download_mo2() {
    log_info "Starting Mod Organizer 2 download process"

    print_section "Download Mod Organizer 2"

    # Check for required dependencies
    if ! check_download_dependencies; then
        handle_error "Required dependencies missing for download" false
        return 1
    fi

    # First check if a system 7z tool exists
    local system_7z_available=false
    if check_system_7z; then
        system_7z_available=true
        echo -e "${color_green}Found system 7z tool, will use it for extraction${color_reset}"
        log_info "System 7z tool found, skipping py7zr installation"
    else
        # Check for py7zr, install if needed
        if ! check_py7zr_installed; then
            echo -e "${color_yellow}Installing Python 7z extractor...${color_reset}"
            if ! install_py7zr; then
                handle_error "Failed to install Python 7z extractor" false
                return 1
            fi
        fi
    fi

    local tracker=$(start_progress_tracking "Downloading Mod Organizer 2" 120)

    # Fetch the latest release info from GitHub
    echo -e "Fetching latest release information from GitHub..."
    local release_info
    if ! release_info=$(curl -s https://api.github.com/repos/ModOrganizer2/modorganizer/releases/latest); then
        end_progress_tracking "$tracker" false
        handle_error "Failed to fetch release information from GitHub. Check your internet connection." false
        return 1
    fi

    update_progress "$tracker" 10 100

    # Extract release version
    local version=$(echo "$release_info" | jq -r '.tag_name')
    version=${version#v}  # Remove 'v' prefix if present

    echo -e "Latest version: ${color_green}$version${color_reset}"

    # Find the correct asset (Mod.Organizer-*.7z)
    local download_url
    download_url=$(echo "$release_info" | jq -r '.assets[] | select(.name | test("^Mod\\.Organizer-[0-9.]+\\.7z$")) | .browser_download_url')

    if [ -z "$download_url" ]; then
        end_progress_tracking "$tracker" false
        handle_error "Could not find appropriate Mod.Organizer-*.7z asset in the latest release" false
        return 1
    fi

    local filename=$(basename "$download_url")
    echo -e "Found asset: ${color_blue}$filename${color_reset}"

    update_progress "$tracker" 20 100

    # Ask user where to download and extract
    echo -e "\nWhere would you like to download and extract Mod Organizer 2?"
    read_with_tab_completion "Extract to directory" "$HOME/ModOrganizer2" "extract_dir"

    # Create the directory if it doesn't exist
    if [ ! -d "$extract_dir" ]; then
        echo -e "Directory doesn't exist. Creating it..."
        mkdir -p "$extract_dir"
        if [ $? -ne 0 ]; then
            end_progress_tracking "$tracker" false
            handle_error "Failed to create directory: $extract_dir" false
            return 1
        fi
    fi

    # Create a temporary directory for the download
    local temp_dir=$(mktemp -d)
    TEMP_FILES+=("$temp_dir")
    local temp_file="$temp_dir/$filename"

    # Download the file
    echo -e "\nDownloading Mod Organizer 2 v$version..."
    echo -e "From: ${color_blue}$download_url${color_reset}"
    echo -e "To: ${color_blue}$temp_file${color_reset}"

    if ! secure_download "$download_url" "$temp_file"; then
        end_progress_tracking "$tracker" false
        handle_error "Failed to download Mod Organizer 2. Check your internet connection." false
        return 1
    fi

    update_progress "$tracker" 60 100

    # Extract the archive
    echo -e "\nExtracting to $extract_dir..."

    if ! extract_7z_archive "$temp_file" "$extract_dir"; then
        end_progress_tracking "$tracker" false
        handle_error "Failed to extract Mod Organizer 2 archive." false
        return 1
    fi

    update_progress "$tracker" 90 100

    # Check if the extraction was successful
    if [ ! -f "$extract_dir/ModOrganizer.exe" ]; then
        # Try to locate ModOrganizer.exe in subdirectories
        local mo2_exe=$(find "$extract_dir" -name "ModOrganizer.exe" | head -n 1)

        if [ -z "$mo2_exe" ]; then
            end_progress_tracking "$tracker" false
            handle_error "Could not find ModOrganizer.exe in the extracted files. The archive structure might have changed." false
            return 1
        fi

        # We found the executable in a subdirectory
        extract_dir=$(dirname "$mo2_exe")
        echo -e "Found ModOrganizer.exe in: ${color_blue}$extract_dir${color_reset}"
    fi

    end_progress_tracking "$tracker" true

    echo -e "\n${color_green}Mod Organizer 2 v$version has been successfully downloaded and extracted to:${color_reset}"
    echo -e "${color_blue}$extract_dir${color_reset}"

    # Ask if user wants to add to Steam
    echo -e "\nWould you like to add Mod Organizer 2 to Steam as a non-Steam game?"
    if confirm_action "Add to Steam?"; then
        add_mo2_to_steam "$extract_dir"
    fi

    return 0
}

# Function to add MO2 to Steam
add_mo2_to_steam() {
    local mo2_dir="$1"

    if [ -z "$mo2_dir" ] || [ ! -d "$mo2_dir" ]; then
        handle_error "Invalid Mod Organizer 2 directory" false
        return 1
    fi

    local mo2_exe="$mo2_dir/ModOrganizer.exe"

    if [ ! -f "$mo2_exe" ]; then
        handle_error "ModOrganizer.exe not found in $mo2_dir" false
        return 1
    fi

    print_section "Add Mod Organizer 2 to Steam"

    # Ask for custom name
    echo -e "What name would you like to use for Mod Organizer 2 in Steam?"
    read -rp "Name [Mod Organizer 2]: " mo2_name

    # Use default name if none provided
    if [ -z "$mo2_name" ]; then
        mo2_name="Mod Organizer 2"
    fi

    # Add to Steam using our vdf.sh function
    echo -e "\nAdding ${color_blue}$mo2_name${color_reset} to Steam..."
    local appid=$(add_game_to_steam "$mo2_name" "$mo2_exe" "$mo2_dir")

    if [ $? -eq 0 ] && [ -n "$appid" ]; then
        echo -e "\n${color_green}Successfully added Mod Organizer 2 to Steam!${color_reset}"
        echo -e "AppID: ${color_blue}$appid${color_reset}"
        echo -e "\nImportant: You should now:"
        echo -e "1. Restart Steam to see the newly added game"
        echo -e "2. Right-click on Mod Organizer 2 in Steam → Properties"
        echo -e "3. Check 'Force the use of a specific Steam Play compatibility tool'"
        echo -e "4. Select 'Proton Experimental' from the dropdown menu"
        echo -e "5. Set up NXM handler and DPI scaling as needed from the MO2 Setup menu"

        return 0
    else
        handle_error "Failed to add Mod Organizer 2 to Steam" false
        return 1
    fi
}

# Function to set up Mod Organizer 2 from an existing installation
setup_existing_mo2() {
    print_section "Set Up Existing Mod Organizer 2"

    echo -e "Please specify the location of your existing Mod Organizer 2 installation."
    read_with_tab_completion "Mod Organizer 2 directory" "" "mo2_dir"

    if [ -z "$mo2_dir" ]; then
        handle_error "No directory specified" false
        return 1
    fi

    if [ ! -d "$mo2_dir" ]; then
        handle_error "Directory does not exist: $mo2_dir" false
        return 1
    fi

    local mo2_exe="$mo2_dir/ModOrganizer.exe"

    if [ ! -f "$mo2_exe" ]; then
        handle_error "ModOrganizer.exe not found in $mo2_dir" false
        return 1
    fi

    echo -e "\n${color_green}Found ModOrganizer.exe in: ${color_reset}${color_blue}$mo2_dir${color_reset}"

    # Ask if user wants to add to Steam
    echo -e "\nWould you like to add this Mod Organizer 2 installation to Steam as a non-Steam game?"
    if confirm_action "Add to Steam?"; then
        add_mo2_to_steam "$mo2_dir"
    fi

    return 0
}
