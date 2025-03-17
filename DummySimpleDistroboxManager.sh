#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Source the base manager
source "$SCRIPT_DIR/BaseManager.sh"

# Set manager-specific variables
MANAGER_NAME="Distrobox"
CONFIG_DIR="$HOME/.config/dummysimpledistroboxmanager"
HOTCMDS_FILE="$CONFIG_DIR/distroboxhotcmds.cfg"
SETTINGS_FILE="$CONFIG_DIR/settings.cfg"
IMAGES_FILE="$CONFIG_DIR/distroboximages.cfg"
GLOBAL_STARTUP_CMDS_FILE="$CONFIG_DIR/global_startup_commands.cfg"
CONTAINER_STARTUP_CMDS_FILE="$CONFIG_DIR/container_startup_commands.cfg"

# Create distroboximages.cfg and propagate it
initialize_images_file() {
    if [ ! -s "$IMAGES_FILE" ]; then  # Check if file is empty
        echo "ubuntu:24.04" > "$IMAGES_FILE"
        echo "archlinux:latest" >> "$IMAGES_FILE"
        echo "debian:bookworm" >> "$IMAGES_FILE"
        echo "registry.fedoraproject.org/fedora-toolbox:40" >> "$IMAGES_FILE"
    fi
}

# Ensure the config directory exists
mkdir -p "$CONFIG_DIR"
touch "$HOTCMDS_FILE"
touch "$SETTINGS_FILE"
touch "$IMAGES_FILE"
touch "$GLOBAL_STARTUP_CMDS_FILE"
touch "$CONTAINER_STARTUP_CMDS_FILE"

# Amount of entries in the container's menu
CONTAINER_MENU_ITEMS=6

initialize_images_file

set_distrobox_working_directory() {
    while true; do
        read -p "Enter the working directory for distroboxes (or press Enter to cancel): " distrobox_working_dir
        if [ -z "$distrobox_working_dir" ]; then
            echo "Operation cancelled."
            return 1
        fi
        if [ -d "$distrobox_working_dir" ]; then
            echo "DISTROBOXWORKING_DIR=$distrobox_working_dir" > "$SETTINGS_FILE"
            echo "Distrobox working directory set to: $distrobox_working_dir"
            break
        else
            echo "Directory does not exist. Do you want to create it? (y/n)"
            read -r create_dir
            if [[ $create_dir =~ ^[Yy]$ ]]; then
                if mkdir -p "$distrobox_working_dir"; then
                    echo "DISTROBOXWORKING_DIR=$distrobox_working_dir" > "$SETTINGS_FILE"
                    echo "Directory created and distrobox working directory set to: $distrobox_working_dir"
                    break
                else
                    echo "Failed to create directory"
                    return 1
                fi
            fi
        fi
    done
    return 0
}

get_distrobox_working_directory() {
    if [ -f "$SETTINGS_FILE" ]; then
        local distrobox_working_dir=$(grep "^DISTROBOXWORKING_DIR=" "$SETTINGS_FILE" | cut -d= -f2)
        if [ -n "$distrobox_working_dir" ] && [ -d "$distrobox_working_dir" ]; then
            echo "$distrobox_working_dir"
            return 0
        fi
    fi
    return 1
}

# Check for initial setup
if ! get_distrobox_working_directory > /dev/null; then
    echo -e "Welcome to \033[1;34mDistrobox Manager\033[0m!"
    echo "To start, choose a directory where you'd like to store the user files of all the distroboxes you create - this will serve as your primary workspace for all distrobox containers"
    echo "You can use a pre-existing directory or enter a new one to create it."
    if ! set_distrobox_working_directory; then
        echo "No distrobox working directory set. Exiting..."
        exit 1
    fi

    if ! get_distrobox_working_directory > /dev/null; then
        echo "Error: Failed to properly set up distrobox working directory."
        exit 1
    fi
fi

# Manage the recent images list
add_to_recent_images() {
    local new_image="$1"
    local temp_file=$(mktemp)

    # Add new image at the top
    echo "$new_image" > "$temp_file"

    # Add existing images, skipping duplicates
    if [ -f "$IMAGES_FILE" ]; then
        grep -v "^$new_image\$" "$IMAGES_FILE" >> "$temp_file"
    fi

    # Keep only the most recent 5 entries
    head -n 5 "$temp_file" > "$IMAGES_FILE"
    rm "$temp_file"
}

# Function to manage global startup commands
manage_global_startup_commands() {
    echo -e "\n\033[1;34mManage Global Distrobox Startup Commands\033[0m"
    echo "These commands will run automatically when any distrobox container starts"
    echo -e "\033[90m----------------------------------------\033[0m"

    if [ -s "$GLOBAL_STARTUP_CMDS_FILE" ]; then
        echo "Current global startup commands:"
        local i=1
        while IFS= read -r cmd; do
            cmd_color_code=$(generate_color_code "$cmd")
            printf "%b%d. %s\033[0m\n" "$cmd_color_code" "$i" "$cmd"
            i=$((i+1))
        done < "$GLOBAL_STARTUP_CMDS_FILE"
    else
        echo "No global startup commands configured."
    fi

    echo -e "\n1. Add global startup command"
    echo "2. Remove global startup command"
    echo "0. Return to options"

    read -p "Enter your choice: " cmd_option
    case $cmd_option in
        1)
            add_global_startup_command
            ;;
        2)
            remove_global_startup_command
            ;;
        0)
            return
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
}

add_global_startup_command() {
    read -p "Enter the command to run at distrobox startup (for all containers): " new_cmd

    if [ -z "$new_cmd" ]; then
        echo "Operation cancelled."
        return
    fi

    echo "$new_cmd" >> "$GLOBAL_STARTUP_CMDS_FILE"
    echo -e "\033[1;32mGlobal startup command added successfully.\033[0m"
    echo "Press Enter to continue..."
    read
}

remove_global_startup_command() {
    if [ ! -s "$GLOBAL_STARTUP_CMDS_FILE" ]; then
        echo "No global startup commands to remove."
        echo "Press Enter to continue..."
        read
        return
    fi

    echo "Select a command to remove:"
    mapfile -t cmds < "$GLOBAL_STARTUP_CMDS_FILE"

    for i in "${!cmds[@]}"; do
        cmd_color_code=$(generate_color_code "${cmds[$i]}")
        printf "%b%d. %s\033[0m\n" "$cmd_color_code" "$((i+1))" "${cmds[$i]}"
    done

    read -p "Enter command number to remove (or press Enter to cancel): " remove_num

    if [ -z "$remove_num" ]; then
        echo "Operation cancelled."
        return
    fi

    if [[ "$remove_num" =~ ^[0-9]+$ ]] && [ "$remove_num" -ge 1 ] && [ "$remove_num" -le "${#cmds[@]}" ]; then
        temp_file=$(mktemp)
        sed "$remove_num d" "$GLOBAL_STARTUP_CMDS_FILE" > "$temp_file"
        mv "$temp_file" "$GLOBAL_STARTUP_CMDS_FILE"
        echo -e "\033[1;32mGlobal startup command removed successfully.\033[0m"
    else
        echo "Invalid selection."
    fi

    echo "Press Enter to continue..."
    read
}

# Function to manage container-specific startup commands
manage_container_startup_commands() {
    local distrobox_name="$1"

    echo -e "\n\033[1;34mManage Container-Specific Startup Commands for $distrobox_name\033[0m"
    echo "These commands will run automatically when this specific container starts"
    echo -e "\033[90m----------------------------------------\033[0m"

    # Display current container-specific commands
    local container_cmds=()
    if [ -s "$CONTAINER_STARTUP_CMDS_FILE" ]; then
        while IFS=: read -r box cmd || [ -n "$box" ]; do
            if [ "$box" = "$distrobox_name" ]; then
                container_cmds+=("$cmd")
            fi
        done < "$CONTAINER_STARTUP_CMDS_FILE"
    fi

    if [ ${#container_cmds[@]} -gt 0 ]; then
        echo "Current container-specific startup commands for $distrobox_name:"
        for i in "${!container_cmds[@]}"; do
            cmd_color_code=$(generate_color_code "${container_cmds[$i]}")
            printf "%b%d. %s\033[0m\n" "$cmd_color_code" "$((i+1))" "${container_cmds[$i]}"
        done
    else
        echo "No container-specific startup commands configured for $distrobox_name."
    fi

    echo -e "\n1. Add container-specific startup command"
    echo "2. Remove container-specific startup command"
    echo "0. Return to container menu"

    read -p "Enter your choice: " cmd_option
    case $cmd_option in
        1)
            add_container_startup_command "$distrobox_name"
            ;;
        2)
            remove_container_startup_command "$distrobox_name"
            ;;
        0)
            return
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
}

add_container_startup_command() {
    local distrobox_name="$1"
    read -p "Enter the command to run at startup for $distrobox_name: " new_cmd

    if [ -z "$new_cmd" ]; then
        echo "Operation cancelled."
        return
    fi

    echo "$distrobox_name:$new_cmd" >> "$CONTAINER_STARTUP_CMDS_FILE"
    echo -e "\033[1;32mContainer-specific startup command added successfully.\033[0m"
    echo "Press Enter to continue..."
    read
}

remove_container_startup_command() {
    local distrobox_name="$1"
    local container_cmds=()
    local container_cmd_lines=()
    local line_num=1

    # Collect commands and their line numbers
    while IFS=: read -r box cmd || [ -n "$box" ]; do
        if [ "$box" = "$distrobox_name" ]; then
            container_cmds+=("$cmd")
            container_cmd_lines+=("$line_num")
        fi
        line_num=$((line_num+1))
    done < "$CONTAINER_STARTUP_CMDS_FILE"

    if [ ${#container_cmds[@]} -eq 0 ]; then
        echo "No container-specific startup commands to remove for $distrobox_name."
        echo "Press Enter to continue..."
        read
        return
    fi

    echo "Select a command to remove:"
    for i in "${!container_cmds[@]}"; do
        cmd_color_code=$(generate_color_code "${container_cmds[$i]}")
        printf "%b%d. %s\033[0m\n" "$cmd_color_code" "$((i+1))" "${container_cmds[$i]}"
    done

    read -p "Enter command number to remove (or press Enter to cancel): " remove_num

    if [ -z "$remove_num" ]; then
        echo "Operation cancelled."
        return
    fi

    if [[ "$remove_num" =~ ^[0-9]+$ ]] && [ "$remove_num" -ge 1 ] && [ "$remove_num" -le "${#container_cmds[@]}" ]; then
        line_to_remove=${container_cmd_lines[$((remove_num-1))]}
        temp_file=$(mktemp)
        sed "${line_to_remove}d" "$CONTAINER_STARTUP_CMDS_FILE" > "$temp_file"
        mv "$temp_file" "$CONTAINER_STARTUP_CMDS_FILE"
        echo -e "\033[1;32mContainer-specific startup command removed successfully.\033[0m"
    else
        echo "Invalid selection."
    fi

    echo "Press Enter to continue..."
    read
}

# Override: Display options menu
display_options_menu() {
    echo "Options:"
    echo "1. Create a new distrobox"
    echo "2. Delete a distrobox"
    echo "3. Manage global startup commands"
    echo "0. Back to main menu"
}

# Override: Display distrobox options and commands
display_options_and_commands() {
    local distrobox_name="$1"
    local color_code=$(generate_color_code "$distrobox_name")
    echo -e "\n${color_code}Managing distrobox: $distrobox_name\033[0m"
    echo "Options:"
    echo "1. Enter shell"
    echo "2. Modify hot commands"
    echo "3. Manage container startup commands"
    echo "4. Kill distrobox"
    echo "5. Export application"
    echo "0. Back to main menu"
    echo "------------------------------"
    echo "Hot commands:"
    if [ -f "$HOTCMDS_FILE" ]; then
        local i=5
        while IFS=: read -r box cmd || [ -n "$box" ]; do
            if [ "$box" = "$distrobox_name" ]; then
                i=$((i+1))
                cmd_color_code=$(generate_color_code "$distrobox_name:$cmd")
                printf "%b%d. %s\033[0m\n" "$cmd_color_code" "$i" "$cmd"
            fi
        done < "$HOTCMDS_FILE"
    else
        echo "No hot commands found."
    fi
}

handle_custom_options() {
    local option_choice="$1"
    case $option_choice in
        1)
            create_new_distrobox
            return 2
            ;;
        2)
            delete_distrobox
            return 2
            ;;
        3)
            manage_global_startup_commands
            return 2
            ;;
        *)
            echo "Invalid choice"
            return 0
            ;;
    esac
}

handle_option() {
    local distrobox_name="$1"
    local option="$2"

    case $option in
        1)
            enter_distrobox "$distrobox_name"
            return 2
            ;;
        2)
            echo "1. Add hot command"
            echo "2. Remove hot command"
            read -p "Enter your choice: " modify_option
            if [ -z "$modify_option" ]; then
                return 0
            fi
            case $modify_option in
                1) add_hot_command "$distrobox_name" ;;
                2) remove_hot_command "$distrobox_name" ;;
                *) echo "Invalid choice" ;;
            esac
            ;;
        3)
            manage_container_startup_commands "$distrobox_name"
            ;;
        4)
            kill_distrobox "$distrobox_name"
            ;;
        5)
            export_application "$distrobox_name"
            ;;
        0)
            return 2
            ;;
        *)
            if [ "$option" -gt 5 ]; then
                execute_hot_command "$distrobox_name" "$option"
            else
                echo "Invalid choice"
                echo "Press Enter to continue..."
                read
            fi
            ;;
    esac
}

remove_hot_command() {
    local distrobox_name="$1"
    local hot_cmds=()
    local hot_cmd_lines=()
    local line_num=1

    # Collect commands and their line numbers
    while IFS=: read -r box cmd || [ -n "$box" ]; do
        if [ "$box" = "$distrobox_name" ]; then
            hot_cmds+=("$cmd")
            hot_cmd_lines+=("$line_num")
        fi
        line_num=$((line_num+1))
    done < "$HOTCMDS_FILE"

    if [ ${#hot_cmds[@]} -eq 0 ]; then
        echo "No hot commands to remove for $distrobox_name."
        echo "Press Enter to continue..."
        read
        return
    fi

    echo "Select a hot command to remove:"

    # Display commands with their menu numbers (starting from CONTAINER_MENU_ITEMS)
    local menu_number=$CONTAINER_MENU_ITEMS
    for i in "${!hot_cmds[@]}"; do
        cmd_color_code=$(generate_color_code "$distrobox_name:${hot_cmds[$i]}")
        printf "%b%d. %s\033[0m\n" "$cmd_color_code" "$menu_number" "${hot_cmds[$i]}"
        menu_number=$((menu_number+1))
    done

    read -p "Enter command number to remove (or press Enter to cancel): " remove_num

    if [ -z "$remove_num" ]; then
        echo "Operation cancelled."
        return
    fi

    # Convert menu number to array index
    if [[ "$remove_num" =~ ^[0-9]+$ ]] && [ "$remove_num" -ge $CONTAINER_MENU_ITEMS ] && [ "$remove_num" -le $(($CONTAINER_MENU_ITEMS - 1 + ${#hot_cmds[@]})) ]; then
        local array_index=$((remove_num - $CONTAINER_MENU_ITEMS))
        local line_to_remove=${hot_cmd_lines[$array_index]}

        # Create a temp file and remove the line
        temp_file=$(mktemp)
        sed "${line_to_remove}d" "$HOTCMDS_FILE" > "$temp_file"
        mv "$temp_file" "$HOTCMDS_FILE"
        echo -e "\033[1;32mHot command removed successfully.\033[0m"
    else
        echo "Invalid selection."
    fi

    echo "Press Enter to continue..."
    read
}

execute_hot_command() {
    local distrobox_name="$1"
    local command_num="$2"

    # Get all hot commands for this distrobox
    local hot_cmds=()
    while IFS=: read -r box cmd || [ -n "$box" ]; do
        if [ "$box" = "$distrobox_name" ]; then
            hot_cmds+=("$cmd")
        fi
    done < "$HOTCMDS_FILE"

    # Convert the menu number to array index
    local array_index=$((command_num - $CONTAINER_MENU_ITEMS))

    # Check if index is valid
    if [ "$array_index" -ge 0 ] && [ "$array_index" -lt "${#hot_cmds[@]}" ]; then
        local command="${hot_cmds[$array_index]}"
        distrobox enter "$distrobox_name" -- bash -c "$command"
        echo "Command executed. Press Enter to continue..."
        read
    else
        echo "Invalid hot command number."
        echo "Press Enter to continue..."
        read
    fi
}

create_new_distrobox() {
    local distrobox_working_dir=$(get_distrobox_working_directory)
    if [ $? -ne 0 ]; then
        echo "Error: Could not determine distrobox working directory."
        return 1
    fi

    echo "Choose an image for the new Distrobox:"
    echo "Recent images:"

    # Display recent images
    local i=1
    while IFS= read -r image || [ -n "$image" ]; do
        echo "$i. $image"
        i=$((i+1))
    done < "$IMAGES_FILE"

    echo "0. Enter custom image"

    while true; do
        read -p "Enter your choice (0-$((i-1))): " image_choice

        # Check if input is empty
        if [ -z "$image_choice" ]; then
            echo "Operation cancelled."
            return 1
        fi

        # Check if input is a number
        if ! [[ "$image_choice" =~ ^[0-9]+$ ]]; then
            echo "Please enter a valid number."
            continue
        fi

        if [ "$image_choice" = "0" ]; then
            read -p "Enter the custom image (format: repository:tag): " custom_image
            if [ -z "$custom_image" ]; then
                echo "Operation cancelled."
                return 1
            fi
            distrobox_image="$custom_image"
            break
        elif [ "$image_choice" -ge 1 ] && [ "$image_choice" -lt "$i" ]; then
            distrobox_image=$(sed -n "${image_choice}p" "$IMAGES_FILE")
            break
        else
            echo "Please enter a number between 0 and $((i-1))."
        fi
    done

    # Add the selected/entered image to recent images
    add_to_recent_images "$distrobox_image"

    while true; do
        read -p "Enter the name for the new Distrobox: " distrobox_name
        if [ -z "$distrobox_name" ]; then
            echo "Operation cancelled."
            return 1
        fi

        # Make sure distrobox name is alphanumeric, dash, and underscore only
        if ! [[ "$distrobox_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            echo "Error: Distrobox name can only contain letters, numbers, dashes, and underscores."
            continue
        fi

        # Check for duplicates
        if distrobox list | grep -q "^$distrobox_name "; then
            echo "Error: A distrobox with name '$distrobox_name' already exists."
            continue
        fi

        # Check if directory already exists
        if [ -d "$distrobox_working_dir/$distrobox_name" ]; then
            echo "Error: Directory already exists for this distrobox name."
            continue
        fi
        break
    done

    # Create the working directory for the distrobox
    local distrobox_home="$distrobox_working_dir/$distrobox_name"
    if ! mkdir -p "$distrobox_home" 2>/dev/null; then
        echo "Failed to create working directory for distrobox: $distrobox_home"
        echo "Please check permissions and try again."
        return 1
    fi

    while true; do
        read -p "Do you want to use NVIDIA support? (y/n): " nvidia_choice
        case "$nvidia_choice" in
            [Yy]|[Nn]) break ;;
            *) echo "Please enter 'y' or 'n'." ;;
        esac
    done

    create_command="distrobox create"
    create_command+=" --image $distrobox_image"
    create_command+=" --name $distrobox_name"
    create_command+=" --home $distrobox_home"

    if [ "$nvidia_choice" = "y" ] || [ "$nvidia_choice" = "Y" ]; then
        create_command+=" --nvidia"
    fi

    echo "Creating distrobox with command:"
    echo "$create_command"
    echo

    if eval "$create_command"; then
        echo -e "\nNew Distrobox created successfully!"
        echo "Working directory: $distrobox_home"
        echo "Completing initial setup..."


        distrobox enter "$distrobox_name" -- true

        echo -e "\nSetup complete. Returning to manager..."
        sleep 1
        return 0
    else
        echo "Failed to create distrobox. Check the error message above."
        if [ -d "$distrobox_home" ]; then
            rmdir "$distrobox_home" 2>/dev/null
        fi
        return 1
    fi
}

enter_distrobox() {
    local distrobox_name="$1"

    # Create a temporary script to run startup commands
    local temp_script=$(mktemp)
    echo "#!/bin/bash" > "$temp_script"
    echo "# Auto-generated startup script" >> "$temp_script"
    echo "cd ~" >> "$temp_script"
    echo "" >> "$temp_script"

    # Add global startup commands if they exist
    if [ -s "$GLOBAL_STARTUP_CMDS_FILE" ]; then
        echo "# Run global startup commands" >> "$temp_script"
        cat "$GLOBAL_STARTUP_CMDS_FILE" >> "$temp_script"
        echo "" >> "$temp_script"
    fi

    # Add container-specific startup commands if they exist
    if [ -s "$CONTAINER_STARTUP_CMDS_FILE" ]; then
        echo "# Run container-specific startup commands" >> "$temp_script"
        while IFS=: read -r box cmd || [ -n "$box" ]; do
            if [ "$box" = "$distrobox_name" ]; then
                echo "$cmd" >> "$temp_script"
            fi
        done < "$CONTAINER_STARTUP_CMDS_FILE"
        echo "" >> "$temp_script"
    fi

    # Start interactive shell
    echo "# Start interactive shell" >> "$temp_script"
    echo "exec bash" >> "$temp_script"
    chmod +x "$temp_script"

    # Enter distrobox with the startup script
    distrobox enter "$distrobox_name" -- bash -c "$(cat $temp_script)"
    rm "$temp_script"
}

export_application() {
    local distrobox_name="$1"
    read -p "Enter the name of the application to export (or press Enter to cancel): " app_name
    if [ -z "$app_name" ]; then
        echo "Operation cancelled."
        return
    fi
    distrobox enter "$distrobox_name" -- bash -c "distrobox-export --app $app_name"
    echo "Application export attempted. Press Enter to continue..."
    read
}

kill_distrobox() {
    local distrobox_name="$1"
    read -p "Are you sure you want to kill the running $distrobox_name instance? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        distrobox stop "$distrobox_name"
        echo "Distrobox $distrobox_name has been killed."
    else
        echo "Operation cancelled."
    fi
    echo "Press Enter to continue..."
    read
}

delete_distrobox() {
    display_items distroboxes
    read -p "Enter the number of the Distrobox to delete: " delete_choice
    if [ "$delete_choice" -ge 1 ] && [ "$delete_choice" -le "${#distroboxes[@]}" ]; then
        selected_distrobox="${distroboxes[$((delete_choice-1))]}"

        # Safety check 1: Ensure the name doesn't contain dangerous characters
        if echo "$selected_distrobox" | grep -q '[/;:|]'; then
            echo "Error: Distrobox name contains invalid characters"
            return 1
        fi

        local distrobox_working_dir=$(get_distrobox_working_directory)
        if [ $? -ne 0 ]; then
            echo "Error: Could not determine distrobox working directory"
            return 1
        fi

        # Safety check 2: Construct and verify the full path
        local distrobox_path="$distrobox_working_dir/$selected_distrobox"

        # Safety check 3: Ensure the path is actually under the working directory
        if [[ ! "$(realpath "$distrobox_path")" =~ ^"$(realpath "$distrobox_working_dir")"/ ]]; then
            echo "Error: Security check failed - path is outside of working directory"
            return 1
        fi

        # Safety check 4: Verify the directory exists and is a directory
        if [ ! -d "$distrobox_path" ]; then
            echo "Error: Distrobox directory not found or is not a directory"
            return 1
        fi

        echo "This will:"
        echo "1. Delete the Distrobox container '$selected_distrobox'"
        echo "2. Delete the working directory '$distrobox_path'"
        echo "3. Delete all associated hot commands"
        echo "4. Delete all associated container startup commands"
        read -p "To confirm deletion, Type the name of the distrobox ($selected_distrobox): " confirm

        if [ "$confirm" = "$selected_distrobox" ]; then
            # Remove the container first
            if ! distrobox-rm -f "$selected_distrobox"; then
                echo "Error: Failed to remove distrobox container"
                return 1
            fi

            # Safely remove the directory
            if [ -d "$distrobox_path" ]; then
                # Final safety check before removal
                if [[ "$(realpath "$distrobox_path")" =~ ^"$(realpath "$distrobox_working_dir")"/ ]]; then
                    rm -rf "$distrobox_path"
                    if [ $? -ne 0 ]; then
                        echo "Error: Failed to remove distrobox working directory"
                        return 1
                    fi
                else
                    echo "Error: Final security check failed"
                    return 1
                fi
            fi

            # Remove hot commands and container startup commands
            local temp_file=$(mktemp)
            grep -v "^$selected_distrobox:" "$HOTCMDS_FILE" > "$temp_file"
            mv "$temp_file" "$HOTCMDS_FILE"

            temp_file=$(mktemp)
            grep -v "^$selected_distrobox:" "$CONTAINER_STARTUP_CMDS_FILE" > "$temp_file"
            mv "$temp_file" "$CONTAINER_STARTUP_CMDS_FILE"

            echo "Distrobox $selected_distrobox and its associated files have been deleted."
        else
            echo "Deletion aborted: name did not match."
        fi
    else
        echo "Invalid choice"
    fi
}

# Main loop
while true; do
    distrobox_working_dir=$(get_distrobox_working_directory)
    if [ $? -ne 0 ]; then
        echo "Error: Could not determine distrobox working directory."
        exit 1
    fi

    distroboxes=($(find "$distrobox_working_dir" -maxdepth 1 -type d -printf "%f\n" | sort))
    distroboxes=(${distroboxes[@]/"$(basename "$distrobox_working_dir")"/})

    display_items distroboxes
    read -p "Enter the number of the distrobox you want to manage, 0 for Options, or type 'help': " choice

    if [ -z "$choice" ]; then
        continue
    elif [ "$choice" = "help" ]; then
        clear
        if [ -f "$SCRIPT_DIR/DOCUMENTATION.md" ]; then
            cat "$SCRIPT_DIR/DOCUMENTATION.md"
            echo -e "\n\033[1;36mPress Enter to return to the previous menu...\033[0m"
            read
        else
            echo -e "\033[1;31mError: Documentation file not found.\033[0m"
            echo -e "Ensure DOCUMENTATION.md exists in: $SCRIPT_DIR"
            echo -e "\nPress Enter to continue..."
            read
        fi
        continue
    elif [ "$choice" -eq 0 ]; then
        handle_options_menu
        if [ $? -eq 2 ]; then
            continue
        fi
    elif [ "$choice" -ge 1 ] && [ "$choice" -le "${#distroboxes[@]}" ]; then
        selected_distrobox="${distroboxes[$((choice-1))]}"
        manage_item "$selected_distrobox"
    else
        echo "Invalid choice"
    fi
done
