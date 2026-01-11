# Start Services Script

## Overview

`start-services.ps1` is a PowerShell script that manages multiple .NET services for local development. It provides an easy way to start, stop, restart, and monitor the status of all your services from a single command.

## Features

- Start all services at once
- Start individual services selectively with checkbox UI
- Stop all services at once
- Stop individual services selectively with checkbox UI
- Restart all services
- View the status of running services
- **Continuous interactive mode** - perform multiple operations in a single session
- Quick exit with **Esc key** at any time
- Checkbox-based selection for multi-service operations
- Configuration-based service management via JSON file
- Automatic log file generation for each service
- Process ID tracking for reliable service management
- Git pull integration for keeping services up-to-date

## Prerequisites

- PowerShell 5.1 or later
- .NET SDK installed and available in PATH
- All service project paths must exist as defined in `start-services.json`

## Configuration

The script reads its configuration from `start-services.json`, which should be in the same directory as the script. This file defines:

- **logDirectory**: Path where service logs will be stored
- **pidFilePath**: Path to the file that tracks running service process IDs
- **services**: Array of service definitions with:
  - **name**: Display name of the service
  - **path**: Absolute path to the service project directory
  - **color**: Console color for service output (see [available colors](#tips) in the Tips section below)

### Example start-services.json

```json
{
  "logDirectory": "C:\\Projects\\DotNet\\start-services\\logs",
  "pidFilePath": "C:\\Projects\\DotNet\\start-services\\.services.pids",
  "services": [
    {
      "name": "Finance API",
      "path": "C:\\Projects\\DotNet\\Finance\\src\\Finance.Api",
      "color": "Cyan"
    },
    {
      "name": "Finance Background Worker",
      "path": "C:\\Projects\\DotNet\\Finance\\src\\Finance.BackgroundWorker",
      "color": "Green"
    }
  ]
}
```

## Usage

### Interactive Mode

Run the script without parameters to display an interactive menu:

```powershell
.\start-services.ps1
```

You'll see a menu like this:

```
===============================================================
  Services Management
===============================================================

Use UP/DOWN arrow keys to navigate, ENTER to select:

  > Start all services
    Build and start all configured services

    Start individual services
    Interactively choose which services to start

    Stop all services
    Stop all running services and clean up

    Stop individual services
    Interactively choose which services to stop

    Restart all services
    Stop and restart all services

    Show service status
    Display status of all tracked services

    Exit
    Exit without performing any action
```

**How to use:**
- Use **UP** and **DOWN** arrow keys to navigate through the options
- The currently selected option is highlighted with a `>` indicator and colored background
- Press **ENTER** to execute the selected action
- Each option shows a description of what it does
- After an action completes, you'll see: `Press any key to return to menu or [Esc] to exit...`
  - Press **any key** to return to the menu and perform another action
  - Press **Esc** to exit immediately
- Select "Exit" from the menu to quit without performing any action
- **Interactive mode runs continuously** - perform multiple operations without restarting the script

### Direct Command Mode

Run the script with a specific action parameter for one-time operations:

```powershell
.\start-services.ps1 <action> [parameters]
```

**Note:** In direct command mode, the script executes the specified action once and then exits. Use interactive mode (no parameters) for continuous operation.

#### Start All Services

```powershell
# Start with prompt for git pull
.\start-services.ps1 start

# Start and automatically pull latest changes (no prompt)
.\start-services.ps1 start -GitPull $true

# Start without pulling changes (no prompt)
.\start-services.ps1 start -GitPull $false
```

This will:
- Check that .NET SDK is installed
- Handle git pull based on the `-GitPull` parameter (see below)
- Restore dependencies for each service
- Build each service
- Start each service in the background
- Create log files in the configured log directory
- Save process IDs to the PID file

**Git Pull Options:**

The `-GitPull` parameter controls whether to pull latest changes from git:

| Command | Behavior |
|---------|----------|
| `.\start-services.ps1 start` | Prompts you: "Pull latest changes from git for all services? (Y/N)" |
| `.\start-services.ps1 start -GitPull $true` | Automatically pulls latest changes without prompting |
| `.\start-services.ps1 start -GitPull $false` | Skips git pull without prompting |

- Git pull applies to all services (not per-service)
- If a service directory is not a git repository or git pull fails, a warning is displayed but the service will still attempt to build and start
- The `-GitPull` parameter works with both `start` and `restart` actions

**Example output with git pull:**
```
> Starting: Finance API
  Path: C:\Projects\DotNet\Finance\src\Finance.Api
  -> Pulling latest changes from git...
  [OK] Git pull completed
  -> Restoring dependencies...
  -> Building project...
  -> Running service...
  [OK] Started (PID: 12345)
```

#### Start Individual Services

```powershell
# Start with prompt for service selection and git pull
.\start-services.ps1 start-one

# Start and automatically pull latest changes (no prompt)
.\start-services.ps1 start-one -GitPull $true

# Start without pulling changes (no prompt)
.\start-services.ps1 start-one -GitPull $false
```

**Why use start-one?**

The `start-one` parameter is useful when you want to selectively start only specific services without starting the entire service ecosystem. This is particularly helpful when:

- You only need to work on specific services and don't want to consume resources running all services
- You've stopped individual services for debugging and want to restart just those services
- You want to test specific service interactions without running everything
- You're developing on a machine with limited resources and want to run only necessary services

**How it works:**

This will:
- Display a checkbox-based interactive menu with all configured services
- Allow you to select multiple services using arrow keys and spacebar
- Handle git pull based on the `-GitPull` parameter (see below)
- Automatically detect and restart services that are already running
- Restore dependencies, build, and start only the selected services
- Add the started services to the PID file (preserving any other running services)

**Checkbox Interface:**

```
===============================================================
  Select Services to Start
===============================================================

Use UP/DOWN to navigate, SPACE to toggle, ENTER to confirm:

  [X] Finance API
  [ ] Finance Background Worker
  [X] Inventory Data API
  [ ] Customer API
  [ ] Customer Processor
  [ ] Product API

  > Confirm and proceed
    Cancel
```

- Use **UP/DOWN** arrow keys to navigate
- Press **SPACE** to toggle checkboxes [X] / [ ]
- Navigate to "Confirm and proceed" and press **ENTER** to start selected services
- Navigate to "Cancel" and press **ENTER** to exit without changes

**Git Pull Options:**

The `-GitPull` parameter works the same way as with the `start` command:

| Command | Behavior |
|---------|----------|
| `.\start-services.ps1 start-one` | Prompts you: "Pull latest changes from git for selected services? (Y/N)" |
| `.\start-services.ps1 start-one -GitPull $true` | Automatically pulls latest changes without prompting |
| `.\start-services.ps1 start-one -GitPull $false` | Skips git pull without prompting |

**Already Running Services:**

If you select a service that is already running:
- The script automatically stops the existing instance first
- Then restarts it with fresh code
- The PID file is updated with the new process ID

**Example output:**
```
> Service: Finance API (PID: 12345)
  [INFO] Service is already running - stopping it first...
  [OK] Stopped existing instance

> Starting: Finance API
  Path: C:\Projects\DotNet\Finance\src\Finance.Api
  -> Pulling latest changes from git...
  [OK] Git pull completed
  -> Restoring dependencies...
  -> Building project...
  -> Running service...
  [OK] Started (PID: 12789)

===============================================================
[OK] Started 2 service(s) in 15.3s
     Total tracked: 4 service(s)
===============================================================
```

#### Stop All Services

```powershell
.\start-services.ps1 stop
```

This will:
- Read the PID file
- Stop all tracked service processes
- Remove the PID file

#### Stop Individual Services

```powershell
.\start-services.ps1 stop-one
```

**Why use stop-one?**

The `stop-one` parameter is particularly useful during development when you need to debug or troubleshoot specific services without affecting the entire service ecosystem. Instead of stopping all services (which would disrupt your development environment), you can selectively stop only the service(s) you want to debug. This allows you to:

- Keep other services running and maintain their state
- Run the specific service manually with detailed logging or a debugger attached
- Avoid the overhead of restarting all services
- Quickly investigate issues in isolation

Once you've finished debugging, you can use `.\start-services.ps1 start-one` to restart just the services you need, or `.\start-services.ps1 restart` to bring all services back to a consistent state.

**How it works:**

This will:
- Display a checkbox-based interactive menu with all currently running services
- Allow you to select multiple services to stop using arrow keys and spacebar
- Stop only the services you select
- Update the PID file to track only remaining services
- Leave all other services running undisturbed

**Checkbox Interface:**

```
===============================================================
  Select Services to Stop
===============================================================

Use UP/DOWN to navigate, SPACE to toggle, ENTER to confirm:

  [X] Finance API (PID: 12345)
  [ ] Finance Background Worker (PID: 12346)
  [X] Inventory Data API (PID: 12347)
  [ ] Customer API (PID: 12348)

  > Confirm and proceed
    Cancel
```

- Use **UP/DOWN** arrow keys to navigate
- Press **SPACE** to toggle checkboxes [X] / [ ]
- Navigate to "Confirm and proceed" and press **ENTER** to stop selected services
- Navigate to "Cancel" and press **ENTER** to exit without changes

**Example output:**
```
> Stopping: Finance API (PID: 12345)
  [OK] Stopped

> Stopping: Inventory Data API (PID: 12347)
  [OK] Stopped

===============================================================
[OK] Stopped 2 service(s)
     Remaining: 2 service(s)
===============================================================
```

#### Restart All Services

```powershell
.\start-services.ps1 restart
```

This will:
- Stop all running services
- Wait 2 seconds
- Start all services again

#### View Status

```powershell
.\start-services.ps1 status
```

This will display:
- Service name
- Process ID (PID)
- CPU time used
- Memory consumption
- Total running services count

**Example output:**
```
[OK] Finance API
    PID: 12345 | CPU: 5.23s | Memory: 145.2 MB
[OK] Inventory Data API
    PID: 12346 | CPU: 3.87s | Memory: 132.8 MB

Running: 2 / 6
```

## Log Files

Each service generates two log files in the configured log directory:

- `{ServiceName}.log` - Standard output
- `{ServiceName}.log.err` - Standard error output

Service names in log files have spaces replaced with hyphens.

### Viewing Logs

View logs for a specific service:
```powershell
Get-Content C:\Projects\DotNet\start-services\logs\Finance-API.log
```

Watch logs in real-time (tail):
```powershell
Get-Content C:\Projects\DotNet\start-services\logs\Finance-API.log -Wait
```

View all logs at once:
```powershell
Get-Content C:\Projects\DotNet\start-services\logs\*.log -Wait
```

## Troubleshooting

### Configuration File Not Found

**Error:**
```
[ERROR] Configuration file not found: C:\Projects\DotNet\start-services\start-services.json
```

**Solution:** Ensure `start-services.json` exists in the same directory as the script.

### Services Already Running

**Warning:**
```
[WARNING] Services may already be running. Use 'stop' first or 'restart' to restart them.
Continue anyway? (y/N)
```

**Solution:** Run `.\start-services.ps1 stop` first, or use `.\start-services.ps1 restart` to restart them.

### Project Path Not Found

**Error:**
```
[ERROR] Project path not found!
```

**Solution:** Verify that the path specified in `start-services.json` for the service exists and is correct.

### Build Failed

**Error:**
```
[ERROR] Build failed!
```

**Solution:**
1. Navigate to the service directory
2. Run `dotnet build` manually to see detailed error messages
3. Fix any compilation errors
4. Try starting services again

### Process Not Running (in status)

**Output:**
```
[ERROR] Finance API
    PID: 12345 - Process not found
```

**Solution:** The service has stopped unexpectedly. Check the log files for errors, then restart the service.

## Common Workflows

### Interactive Workflow (Recommended)

The interactive mode allows you to perform multiple operations in a single session:

```powershell
# Start in interactive mode
.\start-services.ps1

# The menu appears - select an action (e.g., "Start all services")
# After services start, press any key to return to menu
# Select another action (e.g., "Show service status")
# Check the status, then press any key
# Continue performing actions as needed
# When done, select "Exit" or press [Esc] after any action
```

**Benefits of interactive mode:**
- Perform multiple operations without restarting the script
- Quick feedback loop: start → check status → stop one service → restart it
- Press **Esc** after any action for quick exit
- Clean screen between operations for better readability

### Starting Development Work (Command-Line Mode)

```powershell
# Start all services
.\start-services.ps1 start
# When prompted "Pull latest changes from git for all services? (Y/N):"
# - Answer Y to get the latest code from all repositories
# - Answer N to use your current local code

# Verify they're running
.\start-services.ps1 status
```

### Starting Development Work with Latest Code

```powershell
# Option 1: Start all services and pull latest changes automatically (no prompt)
.\start-services.ps1 start -GitPull $true

# Option 2: Start with prompt, then answer Y to the git pull question
.\start-services.ps1 start
# When prompted, answer Y

# This is useful when:
# - Starting work for the day to get any overnight changes
# - Switching branches or after a team member pushes updates
# - Testing with the latest code from the repository
```

### Starting Development Work WITHOUT Pulling Changes

```powershell
# Option 1: Skip git pull automatically (no prompt)
.\start-services.ps1 start -GitPull $false

# Option 2: Start with prompt, then answer N to the git pull question
.\start-services.ps1 start
# When prompted, answer N

# This is useful when:
# - You have local uncommitted changes you're testing
# - You want to continue working with your current code version
# - You're in the middle of debugging and don't want code changes
```

### Ending Development Work

```powershell
# Stop all services
.\start-services.ps1 stop
```

### Debugging Specific Services

**Using Interactive Mode (Recommended):**
```powershell
# Start in interactive mode
.\start-services.ps1

# Select "Stop individual services" from menu
# Use checkbox UI to select the service(s) to debug
# Press any key after they stop

# Press [Esc] to exit the script
# Debug the service(s) in your favorite IDE (Visual Studio, VS Code, Rider, etc.)
# Attach the debugger, set breakpoints, and investigate the issue

# When done debugging, restart the script in interactive mode
.\start-services.ps1
# Select "Start individual services"
# Use checkbox UI to restart the services you debugged
```

**Using Command-Line Mode:**
```powershell
# Stop just the problematic service(s)
.\start-services.ps1 stop-one
# Use checkbox UI to select which services to stop

# Debug the service(s) in your favorite IDE (Visual Studio, VS Code, Rider, etc.)
# Attach the debugger, set breakpoints, and investigate the issue

# When done debugging, restart just those services
.\start-services.ps1 start-one
# Use checkbox UI to select which services to start
```

### Starting Only Needed Services

```powershell
# Start only the services you need for your current task
.\start-services.ps1 start-one
# Use checkbox UI to select only the services you need

# This is useful when:
# - Working on a specific feature that only requires certain services
# - Running on a development machine with limited resources
# - Testing specific service interactions
```

### Adding a New Service

1. Edit `start-services.json`
2. Add a new service object to the `services` array:
   ```json
   {
     "name": "New Service Name",
     "path": "C:\\Projects\\DotNet\\path\\to\\service",
     "color": "Yellow"
   }
   ```
3. Save the file
4. Run `.\start-services.ps1 start`

## Tips

- **Use interactive mode** for the best experience - perform multiple operations without restarting the script
- Press **Esc** after any action for quick exit instead of navigating back to the menu
- Use the `status` command frequently to ensure all services are healthy
- Check log files if a service fails to start or crashes
- Use `start-one` to start only the services you need for your current task
- Use `stop-one` when you need to stop specific services for debugging
- The checkbox UI lets you select multiple services at once for efficient management
- Keep the PID file - it's needed to stop services later
- Available colors: Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White

## File Structure

```
C:\Projects\DotNet\start-services\
├── start-services.ps1          # Main script
├── start-services.json         # Configuration file
├── ReadMe.md                   # This documentation
├── logs\                       # Log directory
│   ├── Service-Name.log        # Example log file
│   ├── Service-Name.log.err    # Example error log file
│   └── ...
└── .services.pids              # Process ID tracking file (auto-generated)
```
