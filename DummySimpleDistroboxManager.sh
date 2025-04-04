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
LAST_ACCESS_FILE="$CONFIG_DIR/last_access.cfg"
CREATION_TIME_FILE="$CONFIG_DIR/creation_time.cfg"
FAVORITES_FILE="$CONFIG_DIR/favorites.cfg"

# Initialize config files
ensure_config_files
touch "$IMAGES_FILE"

# Create distroboximages.cfg and propagate it
initialize_images_file() {
    if [ ! -s "$IMAGES_FILE" ]; then  # Check if file is empty
        echo "ubuntu:24.04" > "$IMAGES_FILE"
        echo "archlinux:latest" >> "$IMAGES_FILE"
        echo "debian:bookworm" >> "$IMAGES_FILE"
        echo "registry.fedoraproject.org/fedora-toolbox:40" >> "$IMAGES_FILE"
    fi
}

initialize_images_file

# Override get_creation_time for distrobox-specific behavior
get_creation_time() {
    local distrobox_name="$1"

    if [ -f "$CREATION_TIME_FILE" ]; then
        local timestamp=$(grep "^$distrobox_name:" "$CREATION_TIME_FILE" | cut -d: -f2)
        if [ -z "$timestamp" ]; then
            # Fallback to directory creation time
            local distrobox_dir=$(get_distrobox_working_directory)
            if [ $? -eq 0 ] && [ -d "$distrobox_dir/$distrobox_name" ]; then
                echo $(stat -c %Y "$distrobox_dir/$distrobox_name")
            else
                echo "0"  # Default to 0 if directory not found
            fi
        else
            echo "$timestamp"
        fi
    else
        # Fallback to directory creation time
        local distrobox_dir=$(get_distrobox_working_directory)
        if [ $? -eq 0 ] && [ -d "$distrobox_dir/$distrobox_name" ]; then
            echo $(stat -c %Y "$distrobox_dir/$distrobox_name")
        else
            echo "0"  # Default to 0 if directory not found
        fi
    fi
}

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

execute_hot_command() {
    local distrobox_name="$1"
    local command_num="$2"

    # Update last access time
    update_last_access "$distrobox_name"

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
    clear
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
        # Record creation time
        set_creation_time "$distrobox_name"

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

    # Update last access time
    update_last_access "$distrobox_name"

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
    clear
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
    clear
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
    clear
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

            # Remove hot commands
            local temp_file=$(mktemp)
            grep -v "^$selected_distrobox:" "$HOTCMDS_FILE" > "$temp_file"
            mv "$temp_file" "$HOTCMDS_FILE"

            # Remove container-specific startup commands
            temp_file=$(mktemp)
            grep -v "^$selected_distrobox:" "$CONTAINER_STARTUP_CMDS_FILE" > "$temp_file"
            mv "$temp_file" "$CONTAINER_STARTUP_CMDS_FILE"

            # Remove entries from tracking files
            temp_file=$(mktemp)
            grep -v "^$selected_distrobox:" "$CREATION_TIME_FILE" > "$temp_file" 2>/dev/null
            mv "$temp_file" "$CREATION_TIME_FILE"

            temp_file=$(mktemp)
            grep -v "^$selected_distrobox:" "$LAST_ACCESS_FILE" > "$temp_file" 2>/dev/null
            mv "$temp_file" "$LAST_ACCESS_FILE"

            # Remove from favorites if present
            if [ -f "$FAVORITES_FILE" ]; then
                temp_file=$(mktemp)
                grep -v "^$selected_distrobox$" "$FAVORITES_FILE" > "$temp_file"
                mv "$temp_file" "$FAVORITES_FILE"
            fi

            echo "Distrobox $selected_distrobox and its associated files have been deleted."
        else
            echo "Deletion aborted: name did not match."
        fi
    else
        echo "Invalid choice"
    fi
}

# Implementing required functions from BaseManager

display_options_menu() {
    clear
    echo "Options:"
    echo "1. Create a new distrobox"
    echo "2. Delete a distrobox"
    echo "3. Manage global startup commands"
    echo "4. Manage sorting preferences"
    echo "5. Manage color mode"
    echo "6. Manage favorites"  # New option
    echo "0. Back to main menu"
}

display_options_and_commands() {
    local distrobox_name="$1"
    clear
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
        4)
            manage_sorting_preferences
            return 2
            ;;
        5)
            manage_color_mode
            return 2
            ;;
        6)
            # Modified to show distrobox names in the favorites menu
            clear
            echo -e "\n\033[1;36mManage Favorites\033[0m"
            echo -e "\033[90m----------------------------------------\033[0m"

            # Display all items with favorite status
            echo "Current items (★ = favorite):"
            for i in "${!distroboxes[@]}"; do
                item="${distroboxes[i]}"
                color_code=$(generate_color_code "$item")
                star="  "
                if is_favorite "$item"; then
                    star="★ "
                fi
                printf "%d. %s%b%s\033[0m\n" "$((i+1))" "$star" "$color_code" "$item"
            done

            echo -e "\nEnter the number of an item to toggle its favorite status"
            echo "0. Return to options"

            read -p "Enter your choice: " fav_choice

            if [ "$fav_choice" = "0" ]; then
                return 2
            fi

            # Check if selection is valid
            if [ "$fav_choice" -ge 1 ] && [ "$fav_choice" -le "${#distroboxes[@]}" ]; then
                local selected_item="${distroboxes[$((fav_choice-1))]}"
                toggle_favorite "$selected_item"
                echo "Press Enter to continue..."
                read
                return 2
            else
                echo "Invalid choice"
                echo "Press Enter to continue..."
                read
                return 2
            fi
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

    # Ask for color mode preference during first-time setup
    prompt_for_color_mode
fi

# Main loop
while true; do
    clear
    distrobox_working_dir=$(get_distrobox_working_directory)
    if [ $? -ne 0 ]; then
        echo "Error: Could not determine distrobox working directory."
        exit 1
    fi

    distroboxes=($(find "$distrobox_working_dir" -maxdepth 1 -type d -printf "%f\n" | sort))
    distroboxes=(${distroboxes[@]/"$(basename "$distrobox_working_dir")"/})

    # Apply sorting based on the sort method
    sort_method=$(get_sort_method)
    case $sort_method in
        alphabetical)
            # Sort alphabetically
            IFS=$'\n' distroboxes=($(sort <<<"${distroboxes[*]}"))
            ;;
        creation_time)
            # Sort by creation time (newest first)
            sort_items_by_creation_time distroboxes
            ;;
        last_used)
            # Sort by last access time (most recent first)
            sort_items_by_last_access distroboxes
            ;;
    esac

    # Get favorites
    favorites=()
    get_favorites distroboxes favorites

    if [ ${#favorites[@]} -gt 0 ]; then
        # Display favorites section
        echo "Favorites:"
        for i in "${!favorites[@]}"; do
            item_name="${favorites[i]}"
            color_code=$(generate_color_code "$item_name")
            printf "%d. %b%s\033[0m\n" "$((i+1))" "$color_code" "$item_name"
        done
        echo ""
    fi

    # Display regular items
    echo "Available ${MANAGER_NAME}s:"
    # Start numbering after favorites
    start_num=$((${#favorites[@]} + 1))
    non_favorites=()

    # Get non-favorites
    for i in "${!distroboxes[@]}"; do
        box="${distroboxes[i]}"
        is_fav=0
        for fav in "${favorites[@]}"; do
            if [ "$box" = "$fav" ]; then
                is_fav=1
                break
            fi
        done
        if [ $is_fav -eq 0 ]; then
            non_favorites+=("$box")
        fi
    done

    # Display non-favorites
    for i in "${!non_favorites[@]}"; do
        item_name="${non_favorites[i]}"
        color_code=$(generate_color_code "$item_name")
        printf "%d. %b%s\033[0m\n" "$((start_num + i))" "$color_code" "$item_name"
    done
    echo -e "\n0. Options"

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
    elif [ "$choice" -ge 1 ]; then
        # Check if selection is in favorites range
        if [ "$choice" -le "${#favorites[@]}" ]; then
            selected_distrobox="${favorites[$(($choice-1))]}"
            manage_item "$selected_distrobox"
        # Check if selection is in non-favorites range
        elif [ "$choice" -gt "${#favorites[@]}" ] && [ "$choice" -le "$((${#favorites[@]} + ${#non_favorites[@]}))" ]; then
            non_fav_index=$(($choice - ${#favorites[@]} - 1))
            selected_distrobox="${non_favorites[$non_fav_index]}"
            manage_item "$selected_distrobox"
        else
            echo "Invalid choice"
            sleep 1
        fi
    else
        echo "Invalid choice"
    fi
done
