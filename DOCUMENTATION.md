# Dummy Simple Distrobox Manager Documentation

## Overview
Dummy Simple Distrobox Manager is a dummy simple script for managing Distrobox containers. It provides a simple way to create, manage, and maintain distroboxes with separate "working directories" for each container.

### Key Concepts
- Each distrobox has two components:
  - The container itself (managed by distrobox-create)
  - A dedicated working directory for user files that the distrobox will enter on startup
- The working directory serves as the container's home directory, keeping container-specific files separate from your host system's home directory

## First-Time Setup

1. When you first run the manager, you'll be prompted to choose place for your distrobox's working directories
2. These directories will store all your distrobox user files
3. You can either select an existing directory if you have used this script in the past or create a new one
4. The choice is stored in `settings.cfg`

## Creating a New Distrobox

1. From the main menu, select `0` for Options
2. Choose `1` to create a new distrobox
3. Select an image:
   - Choose from recent images list
   - Enter `0` to specify a custom image
   - The five most recently used images will appear in the list
   - This list is stored in `distroboximages.cfg`
4. Enter a name for your new distrobox
5. Choose whether to enable NVIDIA support
6. Optional: Enter the distrobox immediately after creation
   - When a distrobox is created a working directory of the same name will automatically be made in the directory you specified during initial setup

## Managing Distroboxes

From the main menu, select a distrobox by its number to access these features:

## Basic Operations
1. Enter shell
   - Opens a shell in the selected distrobox
   - Automatically starts in the distrobox's working directory

2. Modify hot commands
   - Add custom commands for quick access
   - Remove existing hot commands 
   - Rename hot commands to give them custom names
   - Edit existing hot commands
   - Show config file paths
   - Hot commands are executed inside of the distrobox's working directory
   
3. Kill distrobox
   - Stops the running distrobox instance

4. Export application
   - Makes applications installed in the distrobox available on the host system using `distrobox-export`

5. Manage container startup commands
   - Add commands that run automatically when entering the distrobox
   - Can be set globally or per-container

## Hot Commands
- Custom commands that can be executed by pressing their associated numbers
- Appear as numbered options (6 and above) in the distrobox management menu
- Executed within their distrobox's working directory
- Each container has its own hot commands file: `hotcommands/{container_name}.cfg`
- Commands can be given custom names for easier identification
- Hot commands automatically load your shell environment (bashrc, bash_profile)

## Exiting a Distrobox
- Type `exit` to leave an active distrobox and return to the main menu

## Deleting a Distrobox

1. From the main menu, select `0` for Options
2. Choose `2` to delete a distrobox
3. Select the distrobox to delete
4. Type the full name of the distrobox to confirm deletion

Deletion process:
- Removes the container
- Deletes the working directory
- Removes associated hot commands file

## Sorting and Organization

### Sorting Options
Available from Options menu (4. Manage sorting preferences):
- **Alphabetical** - Default sorting by container name
- **Most Recently Created** - Newest containers first  
- **Most Recently Used** - Recently accessed containers first

### Favorites System
Available from Options menu (6. Manage favorites):
- Mark containers as favorites for quick access
- Favorites appear at the top of the main menu with ★ symbol
- Favorites respect your chosen sorting method
- Toggle favorite status on/off for any container

## Config Location

- Configuration directory: `~/.config/dummysimpledistroboxmanager/`
- Settings file: `settings.cfg`
- Hot commands directory: `hotcommands/`
- Per-container hot commands: `hotcommands/{container_name}.cfg`
- Image list: `distroboximages.cfg`
- Favorites: `favorites.cfg`
- Creation times: `creation_time.cfg`
- Last access: `last_access.cfg`
