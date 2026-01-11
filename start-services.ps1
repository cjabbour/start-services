#Requires -Version 5.1

<#
.SYNOPSIS
    Manages local .NET services
.DESCRIPTION
    Starts, stops, and manages multiple .NET Core applications for local development.
    Run without parameters for interactive mode with continuous menu.
.PARAMETER Action
    Action to perform: start, start-one, stop, stop-one, status, restart, or quit
.PARAMETER GitPull
    Optional boolean parameter to control git pull behavior when starting services.
    If specified as -GitPull $true, performs git pull without prompting.
    If specified as -GitPull $false, skips git pull without prompting.
    If omitted, prompts the user whether to perform git pull.
.EXAMPLE
    .\start-services.ps1
    Runs in interactive mode with continuous menu - perform multiple operations
.EXAMPLE
    .\start-services.ps1 start
    .\start-services.ps1 start -GitPull $true
    .\start-services.ps1 start -GitPull $false
.EXAMPLE
    .\start-services.ps1 start-one
    .\start-services.ps1 start-one -GitPull $true
.EXAMPLE
    .\start-services.ps1 stop
    .\start-services.ps1 stop-one
.EXAMPLE
    .\start-services.ps1 status
.EXAMPLE
    .\start-services.ps1 restart
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("start", "start-one", "stop", "status", "restart", "stop-one", "quit")]
    [string]$Action = "",

    [Parameter(Mandatory=$false)]
    [bool]$GitPull
)

# Determine git pull action based on parameter
$gitPullAction = "prompt"  # Default: prompt the user
if ($PSBoundParameters.ContainsKey('GitPull')) {
    if ($GitPull -eq $true) {
        $gitPullAction = "yes"
    }
    else {
        $gitPullAction = "no"
    }
}

# Load configuration from JSON file
$configPath = Join-Path $PSScriptRoot "start-services.json"

if (-not (Test-Path $configPath)) {
    Write-Host "[ERROR] Configuration file not found: $configPath" -ForegroundColor Red
    Write-Host "Please ensure start-services.json exists in the same directory as this script." -ForegroundColor Yellow
    exit 1
}

try {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json

    # Convert JSON services to PowerShell hashtable format
    $services = @()
    foreach ($svc in $config.services) {
        $services += @{
            Name = $svc.name
            Path = $svc.path
            Color = $svc.color
        }
    }

    $logDirectory = $config.logDirectory
    $pidFile = $config.pidFilePath
}
catch {
    Write-Host "[ERROR] Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Ensure log directory exists
if (-not (Test-Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor White
    Write-Host "===============================================================" -ForegroundColor DarkGray
    Write-Host ""
}

function Test-DotNetInstalled {
    try {
        $dotnetVersion = dotnet --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-ColorOutput "[OK] .NET SDK detected: $dotnetVersion" "Green"
            return $true
        }
    }
    catch {
        Write-ColorOutput "[ERROR] .NET SDK not found. Please install .NET SDK." "Red"
        return $false
    }
}

function Show-CheckboxMenu {
    param(
        [string]$Title,
        [array]$Items,
        [array]$PreSelectedItems = @()
    )

    [Console]::CursorVisible = $false
    $selected = @()

    # Initialize selected array based on pre-selected items
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $selected += ($PreSelectedItems -contains $i)
    }

    $currentIndex = 0
    $confirmIndex = $Items.Count
    $cancelIndex = $Items.Count + 1

    # Calculate total lines needed for the menu
    $menuLines = 7 + $Items.Count + 3  # header(4) + instructions(3) + items + blank + confirm + cancel + blank

    function Draw-CheckboxMenu {
        param([int]$current, [array]$checked)

        Write-Host ""
        Write-Host "===============================================================" -ForegroundColor DarkGray
        Write-Host "  $Title" -ForegroundColor White
        Write-Host "===============================================================" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Use " -NoNewline
        Write-Host "UP/DOWN" -ForegroundColor Cyan -NoNewline
        Write-Host " to navigate, " -NoNewline
        Write-Host "SPACE" -ForegroundColor Cyan -NoNewline
        Write-Host " to toggle, " -NoNewline
        Write-Host "ENTER" -ForegroundColor Cyan -NoNewline
        Write-Host " to confirm:"
        Write-Host ""

        for ($i = 0; $i -lt $Items.Count; $i++) {
            $checkbox = if ($checked[$i]) { "[X]" } else { "[ ]" }
            $prefix = if ($i -eq $current) { "  > " } else { "    " }

            if ($i -eq $current) {
                Write-Host $prefix -NoNewline
                Write-Host "$checkbox " -ForegroundColor Cyan -NoNewline
                Write-Host $Items[$i] -ForegroundColor White -BackgroundColor DarkCyan
            }
            else {
                Write-Host "$prefix$checkbox $($Items[$i])" -ForegroundColor White
            }
        }

        Write-Host ""

        # Confirm button
        if ($current -eq $confirmIndex) {
            Write-Host "  > " -NoNewline
            Write-Host "Confirm and proceed" -ForegroundColor White -BackgroundColor DarkGreen
        }
        else {
            Write-Host "    Confirm and proceed" -ForegroundColor Green
        }

        # Cancel button
        if ($current -eq $cancelIndex) {
            Write-Host "  > " -NoNewline
            Write-Host "Cancel" -ForegroundColor White -BackgroundColor DarkRed
        }
        else {
            Write-Host "    Cancel" -ForegroundColor Red
        }

        Write-Host ""
    }

    # Draw initial menu and capture starting position
    $menuStart = [Console]::CursorTop
    Draw-CheckboxMenu -current $currentIndex -checked $selected

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        if ($key.VirtualKeyCode -eq 38) {  # Up arrow
            $currentIndex = ($currentIndex - 1 + $cancelIndex + 1) % ($cancelIndex + 1)
            [Console]::SetCursorPosition(0, $menuStart)
            Draw-CheckboxMenu -current $currentIndex -checked $selected
        }
        elseif ($key.VirtualKeyCode -eq 40) {  # Down arrow
            $currentIndex = ($currentIndex + 1) % ($cancelIndex + 1)
            [Console]::SetCursorPosition(0, $menuStart)
            Draw-CheckboxMenu -current $currentIndex -checked $selected
        }
        elseif ($key.VirtualKeyCode -eq 32) {  # Space bar
            if ($currentIndex -lt $Items.Count) {
                $selected[$currentIndex] = -not $selected[$currentIndex]
                [Console]::SetCursorPosition(0, $menuStart)
                Draw-CheckboxMenu -current $currentIndex -checked $selected
            }
        }
        elseif ($key.VirtualKeyCode -eq 13) {  # Enter
            [Console]::CursorVisible = $true

            # Clear the menu
            [Console]::SetCursorPosition(0, $menuStart)
            for ($i = 0; $i -lt $menuLines; $i++) {
                Write-Host (" " * [Console]::WindowWidth)
            }
            [Console]::SetCursorPosition(0, $menuStart)

            if ($currentIndex -eq $cancelIndex) {
                return @{ Cancelled = $true; SelectedIndices = @() }
            }
            elseif ($currentIndex -eq $confirmIndex) {
                $selectedIndices = @()
                for ($i = 0; $i -lt $selected.Count; $i++) {
                    if ($selected[$i]) {
                        $selectedIndices += $i
                    }
                }
                return @{ Cancelled = $false; SelectedIndices = $selectedIndices }
            }
        }
    }
}

function Start-Services {
    Write-Header "Starting Services"

    if (-not (Test-DotNetInstalled)) {
        exit 1
    }

    # Check if services are already running
    if (Test-Path $pidFile) {
        Write-ColorOutput "[WARNING] Services may already be running. Use 'stop' first or 'restart' to restart them." "Yellow"
        $response = Read-Host "Continue anyway? (y/N)"
        if ($response -ne 'y' -and $response -ne 'Y') {
            exit 0
        }
    }

    # Determine whether to perform git pull based on global $gitPullAction variable
    $performGitPull = $false
    if ($gitPullAction -eq "yes") {
        $performGitPull = $true
    }
    elseif ($gitPullAction -eq "no") {
        $performGitPull = $false
    }
    elseif ($gitPullAction -eq "prompt") {
        # Prompt the user
        Write-Host ""
        $gitPullResponse = Read-Host "Pull latest changes from git for all services? (Y/N)"
        $performGitPull = ($gitPullResponse -eq 'Y' -or $gitPullResponse -eq 'y' -or $gitPullResponse -eq 'Yes' -or $gitPullResponse -eq 'yes')
    }

    $processIds = @()
    $startTime = Get-Date

    foreach ($service in $services) {
        Write-ColorOutput "`n> Starting: $($service.Name)" $service.Color
        Write-ColorOutput "  Path: $($service.Path)" "Gray"

        # Verify project path exists
        if (-not (Test-Path $service.Path)) {
            Write-ColorOutput "  [ERROR] Project path not found!" "Red"
            continue
        }

        # Find the .csproj file
        $csprojFiles = Get-ChildItem -Path $service.Path -Filter "*.csproj"
        if ($csprojFiles.Count -eq 0) {
            Write-ColorOutput "  [ERROR] No .csproj file found!" "Red"
            continue
        }

        Push-Location $service.Path

        try {
            # Perform git pull if requested
            if ($performGitPull) {
                Write-ColorOutput "  -> Pulling latest changes from git..." "Gray"
                git pull 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-ColorOutput "  [WARNING] Git pull failed or not a git repository" "Yellow"
                }
                else {
                    Write-ColorOutput "  [OK] Git pull completed" "Green"
                }
            }

            # Restore dependencies
            Write-ColorOutput "  -> Restoring dependencies..." "Gray"
            dotnet restore --nologo --verbosity quiet
            if ($LASTEXITCODE -ne 0) {
                Write-ColorOutput "  [ERROR] Restore failed!" "Red"
                Pop-Location
                continue
            }

            # Build project
            Write-ColorOutput "  -> Building project..." "Gray"
            dotnet build --no-restore --nologo --verbosity quiet
            if ($LASTEXITCODE -ne 0) {
                Write-ColorOutput "  [ERROR] Build failed!" "Red"
                Pop-Location
                continue
            }

            # Start the service in background
            Write-ColorOutput "  -> Running service..." "Gray"
            $serviceName = $service.Name -replace " ","-"
            $logFile = Join-Path $logDirectory "$serviceName.log"

            $process = Start-Process -FilePath "dotnet" `
                                     -ArgumentList "run --no-build --nologo" `
                                     -WorkingDirectory $service.Path `
                                     -PassThru `
                                     -RedirectStandardOutput $logFile `
                                     -RedirectStandardError "$logFile.err" `
                                     -WindowStyle Hidden

            $processIds += @{
                Name = $service.Name
                PID = $process.Id
                Path = $service.Path
            }

            Write-ColorOutput "  [OK] Started (PID: $($process.Id))" "Green"
            Write-ColorOutput "  Log: $logFile" "Gray"

        }
        catch {
            Write-ColorOutput "  [ERROR] Error: $($_.Exception.Message)" "Red"
        }
        finally {
            Pop-Location
        }

        # Small delay between starting services
        Start-Sleep -Milliseconds 500
    }

    # Save process IDs to file
    $processIds | ConvertTo-Json | Set-Content $pidFile

    $elapsed = (Get-Date) - $startTime
    Write-Host ""
    Write-ColorOutput "===============================================================" "Green"
    $elapsedSeconds = $elapsed.TotalSeconds.ToString("0.0")
    Write-ColorOutput "[OK] Started $($processIds.Count) service(s) in ${elapsedSeconds}s" "Green"
    Write-ColorOutput "===============================================================" "Green"
    Write-Host ""
    Write-ColorOutput "Commands:" "White"
    Write-ColorOutput "  - View status:  .\start-services.ps1 status" "Gray"
    Write-ColorOutput "  - Stop all:     .\start-services.ps1 stop" "Gray"
    Write-ColorOutput "  - View logs:    Get-Content $logDirectory\*.log -Wait" "Gray"
    Write-Host ""
}

function Stop-Services {
    Write-Header "Stopping Services"

    if (-not (Test-Path $pidFile)) {
        Write-ColorOutput "No running services found (PID file not found)." "Yellow"
        return
    }

    try {
        $processIds = Get-Content $pidFile | ConvertFrom-Json
        $stoppedCount = 0

        foreach ($proc in $processIds) {
            Write-ColorOutput "> Stopping: $($proc.Name) (PID: $($proc.PID))" "Yellow"

            try {
                $process = Get-Process -Id $proc.PID -ErrorAction SilentlyContinue
                if ($process) {
                    Stop-Process -Id $proc.PID -Force -ErrorAction Stop
                    Write-ColorOutput "  [OK] Stopped" "Green"
                    $stoppedCount++
                }
                else {
                    Write-ColorOutput "  [INFO] Process not running" "Gray"
                }
            }
            catch {
                Write-ColorOutput "  [ERROR] Error: $($_.Exception.Message)" "Red"
            }
        }

        # Clean up PID file
        Remove-Item $pidFile -Force

        Write-Host ""
        Write-ColorOutput "[OK] Stopped $stoppedCount service(s)" "Green"
    }
    catch {
        Write-ColorOutput "Error reading PID file: $($_.Exception.Message)" "Red"
    }
}

function Show-Status {
    Write-Header "Services Status"

    if (-not (Test-Path $pidFile)) {
        Write-ColorOutput "No services are currently tracked (PID file not found)." "Yellow"
        Write-ColorOutput "Services may not be running, or were started outside this script." "Gray"
        return
    }

    try {
        $processIds = Get-Content $pidFile | ConvertFrom-Json
        $runningCount = 0

        foreach ($proc in $processIds) {
            $process = Get-Process -Id $proc.PID -ErrorAction SilentlyContinue

            if ($process) {
                $cpuTime = $process.CPU.ToString("0.00")
                $memory = ($process.WorkingSet64 / 1MB).ToString("0.0")
                Write-ColorOutput "[OK] $($proc.Name)" "Green"
                Write-ColorOutput "    PID: $($proc.PID) | CPU: ${cpuTime}s | Memory: ${memory} MB" "Gray"
                $runningCount++
            }
            else {
                Write-ColorOutput "[ERROR] $($proc.Name)" "Red"
                Write-ColorOutput "    PID: $($proc.PID) - Process not found" "Gray"
            }
        }

        Write-Host ""
        Write-ColorOutput "Running: $runningCount / $($processIds.Count)" "White"
    }
    catch {
        Write-ColorOutput "Error reading status: $($_.Exception.Message)" "Red"
    }
}

function Restart-Services {
    Write-Header "Restarting Services"
    Stop-Services
    Start-Sleep -Seconds 2
    Start-Services
}

function Stop-OneService {
    if (-not (Test-Path $pidFile)) {
        Write-ColorOutput "No running services found (PID file not found)." "Yellow"
        return
    }

    try {
        $processIds = Get-Content $pidFile | ConvertFrom-Json

        # Build service names array for checkbox menu
        # Filter out services that are no longer running
        $runningServices = @()
        $runningIndices = @()
        $serviceIndex = 0

        foreach ($proc in $processIds) {
            $process = Get-Process -Id $proc.PID -ErrorAction SilentlyContinue
            if ($process) {
                $runningServices += "$($proc.Name) (PID: $($proc.PID))"
                $runningIndices += $serviceIndex
            }
            $serviceIndex++
        }

        if ($runningServices.Count -eq 0) {
            Write-ColorOutput "No running services found." "Yellow"
            return
        }

        # Show checkbox menu
        $result = Show-CheckboxMenu -Title "Select Services to Stop" -Items $runningServices

        if ($result.Cancelled) {
            Write-ColorOutput "Operation cancelled." "Yellow"
            return
        }

        if ($result.SelectedIndices.Count -eq 0) {
            Write-ColorOutput "No services selected." "Yellow"
            return
        }

        # Stop selected services
        $stoppedCount = 0
        $remainingProcesses = @()

        Write-Host ""

        # Map selected checkbox indices to original process indices
        $indicesToStop = @()
        foreach ($selectedIndex in $result.SelectedIndices) {
            $indicesToStop += $runningIndices[$selectedIndex]
        }

        for ($i = 0; $i -lt $processIds.Count; $i++) {
            $proc = $processIds[$i]

            # Check if this service was selected for stopping
            $shouldStop = $indicesToStop -contains $i

            if ($shouldStop) {
                Write-ColorOutput "> Stopping: $($proc.Name) (PID: $($proc.PID))" "Yellow"

                try {
                    $process = Get-Process -Id $proc.PID -ErrorAction SilentlyContinue
                    if ($process) {
                        Stop-Process -Id $proc.PID -Force -ErrorAction Stop
                        Write-ColorOutput "  [OK] Stopped" "Green"
                        $stoppedCount++
                    }
                    else {
                        Write-ColorOutput "  [INFO] Process not running" "Gray"
                    }
                }
                catch {
                    Write-ColorOutput "  [ERROR] Error stopping process: $($_.Exception.Message)" "Red"
                    $remainingProcesses += $proc
                }
            }
            else {
                # Keep this process in the PID file
                $remainingProcesses += $proc
            }
        }

        # Update PID file with remaining processes
        if ($remainingProcesses.Count -gt 0) {
            $remainingProcesses | ConvertTo-Json | Set-Content $pidFile
        }
        else {
            # No services left running, remove PID file
            Remove-Item $pidFile -Force
        }

        Write-Host ""
        Write-ColorOutput "===============================================================" "Green"
        Write-ColorOutput "[OK] Stopped $stoppedCount service(s)" "Green"
        Write-ColorOutput "     Remaining: $($remainingProcesses.Count) service(s)" "White"
        Write-ColorOutput "===============================================================" "Green"
        Write-Host ""
    }
    catch {
        Write-ColorOutput "Error reading PID file: $($_.Exception.Message)" "Red"
    }
}

function Start-OneService {
    if (-not (Test-DotNetInstalled)) {
        exit 1
    }

    # Load existing PIDs if they exist
    $existingProcessIds = @()
    if (Test-Path $pidFile) {
        try {
            $existingProcessIds = Get-Content $pidFile | ConvertFrom-Json
        }
        catch {
            Write-ColorOutput "[WARNING] Could not read existing PID file" "Yellow"
        }
    }

    # Build service names array for checkbox menu
    $serviceNames = @()
    foreach ($service in $services) {
        $serviceNames += $service.Name
    }

    # Show checkbox menu
    $result = Show-CheckboxMenu -Title "Select Services to Start" -Items $serviceNames

    if ($result.Cancelled) {
        Write-ColorOutput "Operation cancelled." "Yellow"
        return
    }

    if ($result.SelectedIndices.Count -eq 0) {
        Write-ColorOutput "No services selected." "Yellow"
        return
    }

    # Determine whether to perform git pull
    $performGitPull = $false
    if ($gitPullAction -eq "yes") {
        $performGitPull = $true
    }
    elseif ($gitPullAction -eq "no") {
        $performGitPull = $false
    }
    elseif ($gitPullAction -eq "prompt") {
        Write-Host ""
        $gitPullResponse = Read-Host "Pull latest changes from git for selected services? (Y/N)"
        $performGitPull = ($gitPullResponse -eq 'Y' -or $gitPullResponse -eq 'y' -or $gitPullResponse -eq 'Yes' -or $gitPullResponse -eq 'yes')
    }

    $newProcessIds = @()
    $startedCount = 0
    $startTime = Get-Date

    Write-Host ""

    foreach ($index in $result.SelectedIndices) {
        $service = $services[$index]

        # Check if service is already running
        $existingProc = $existingProcessIds | Where-Object { $_.Name -eq $service.Name }
        if ($existingProc) {
            $process = Get-Process -Id $existingProc.PID -ErrorAction SilentlyContinue
            if ($process) {
                Write-ColorOutput "`n> Service: $($service.Name) (PID: $($existingProc.PID))" "Yellow"
                Write-ColorOutput "  [INFO] Service is already running - stopping it first..." "Yellow"
                try {
                    Stop-Process -Id $existingProc.PID -Force -ErrorAction Stop
                    Start-Sleep -Milliseconds 500
                    Write-ColorOutput "  [OK] Stopped existing instance" "Green"
                }
                catch {
                    Write-ColorOutput "  [ERROR] Failed to stop existing instance: $($_.Exception.Message)" "Red"
                    continue
                }
            }
        }

        Write-ColorOutput "`n> Starting: $($service.Name)" $service.Color
        Write-ColorOutput "  Path: $($service.Path)" "Gray"

        # Verify project path exists
        if (-not (Test-Path $service.Path)) {
            Write-ColorOutput "  [ERROR] Project path not found!" "Red"
            continue
        }

        # Find the .csproj file
        $csprojFiles = Get-ChildItem -Path $service.Path -Filter "*.csproj"
        if ($csprojFiles.Count -eq 0) {
            Write-ColorOutput "  [ERROR] No .csproj file found!" "Red"
            continue
        }

        Push-Location $service.Path

        try {
            # Perform git pull if requested
            if ($performGitPull) {
                Write-ColorOutput "  -> Pulling latest changes from git..." "Gray"
                git pull 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-ColorOutput "  [WARNING] Git pull failed or not a git repository" "Yellow"
                }
                else {
                    Write-ColorOutput "  [OK] Git pull completed" "Green"
                }
            }

            # Restore dependencies
            Write-ColorOutput "  -> Restoring dependencies..." "Gray"
            dotnet restore --nologo --verbosity quiet
            if ($LASTEXITCODE -ne 0) {
                Write-ColorOutput "  [ERROR] Restore failed!" "Red"
                Pop-Location
                continue
            }

            # Build project
            Write-ColorOutput "  -> Building project..." "Gray"
            dotnet build --no-restore --nologo --verbosity quiet
            if ($LASTEXITCODE -ne 0) {
                Write-ColorOutput "  [ERROR] Build failed!" "Red"
                Pop-Location
                continue
            }

            # Start the service in background
            Write-ColorOutput "  -> Running service..." "Gray"
            $serviceName = $service.Name -replace " ","-"
            $logFile = Join-Path $logDirectory "$serviceName.log"

            $process = Start-Process -FilePath "dotnet" `
                                     -ArgumentList "run --no-build --nologo" `
                                     -WorkingDirectory $service.Path `
                                     -PassThru `
                                     -RedirectStandardOutput $logFile `
                                     -RedirectStandardError "$logFile.err" `
                                     -WindowStyle Hidden

            $newProcessIds += @{
                Name = $service.Name
                PID = $process.Id
                Path = $service.Path
            }

            Write-ColorOutput "  [OK] Started (PID: $($process.Id))" "Green"
            Write-ColorOutput "  Log: $logFile" "Gray"
            $startedCount++

        }
        catch {
            Write-ColorOutput "  [ERROR] Error: $($_.Exception.Message)" "Red"
        }
        finally {
            Pop-Location
        }

        # Small delay between starting services
        Start-Sleep -Milliseconds 500
    }

    # Merge new PIDs with existing PIDs (removing duplicates by name)
    $allProcessIds = @()

    # Add existing processes that weren't restarted
    foreach ($existingProc in $existingProcessIds) {
        $wasRestarted = $newProcessIds | Where-Object { $_.Name -eq $existingProc.Name }
        if (-not $wasRestarted) {
            $allProcessIds += $existingProc
        }
    }

    # Add newly started processes
    $allProcessIds += $newProcessIds

    # Save all process IDs to file
    if ($allProcessIds.Count -gt 0) {
        $allProcessIds | ConvertTo-Json | Set-Content $pidFile
    }

    $elapsed = (Get-Date) - $startTime
    Write-Host ""
    Write-ColorOutput "===============================================================" "Green"
    $elapsedSeconds = $elapsed.TotalSeconds.ToString("0.0")
    Write-ColorOutput "[OK] Started $startedCount service(s) in ${elapsedSeconds}s" "Green"
    Write-ColorOutput "     Total tracked: $($allProcessIds.Count) service(s)" "White"
    Write-ColorOutput "===============================================================" "Green"
    Write-Host ""
}

# Determine if we're in interactive mode (no Action parameter provided)
$interactiveMode = [string]::IsNullOrEmpty($Action)

# Define menu options (used in interactive mode)
$script:menuItems = @(
    @{ Name = "start"; Title = "Start all services"; Description = "Build and start all configured services" }
    @{ Name = "start-one"; Title = "Start individual services"; Description = "Interactively choose which services to start" }
    @{ Name = "stop"; Title = "Stop all services"; Description = "Stop all running services and clean up" }
    @{ Name = "stop-one"; Title = "Stop individual services"; Description = "Interactively choose which services to stop" }
    @{ Name = "restart"; Title = "Restart all services"; Description = "Stop and restart all services" }
    @{ Name = "status"; Title = "Show service status"; Description = "Display status of all tracked services" }
    @{ Name = "quit"; Title = "Exit"; Description = "Exit without performing any action" }
)

# Function to draw the menu
function Show-Menu {
    param([int]$selected, [array]$items)

    [Console]::CursorVisible = $false
    $startLine = [Console]::CursorTop

    Write-Host "Use " -NoNewline
    Write-Host "UP/DOWN" -ForegroundColor Cyan -NoNewline
    Write-Host " arrow keys to navigate, " -NoNewline
    Write-Host "ENTER" -ForegroundColor Cyan -NoNewline
    Write-Host " to select:"
    Write-Host ""

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]

        if ($i -eq $selected) {
            Write-Host "  > " -ForegroundColor Cyan -NoNewline
            Write-Host $item.Title -ForegroundColor White -BackgroundColor DarkCyan
            Write-Host "    $($item.Description)" -ForegroundColor Gray
        }
        else {
            Write-Host "    $($item.Title)" -ForegroundColor White
            Write-Host "    $($item.Description)" -ForegroundColor DarkGray
        }
        Write-Host ""
    }

    return $startLine
}

# Function to display and handle the interactive menu
function Show-InteractiveMenu {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor DarkGray
    Write-Host "  Services Management" -ForegroundColor White
    Write-Host "===============================================================" -ForegroundColor DarkGray
    Write-Host ""

    $selectedIndex = 0

    # Initial menu draw
    $menuStartLine = Show-Menu -selected $selectedIndex -items $script:menuItems

    # Menu navigation loop
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        if ($key.VirtualKeyCode -eq 38) {  # Up arrow
            $selectedIndex = ($selectedIndex - 1 + $script:menuItems.Count) % $script:menuItems.Count

            # Clear entire screen and redraw everything
            Clear-Host
            Write-Host ""
            Write-Host "===============================================================" -ForegroundColor DarkGray
            Write-Host "  Services Management" -ForegroundColor White
            Write-Host "===============================================================" -ForegroundColor DarkGray
            Write-Host ""
            $menuStartLine = Show-Menu -selected $selectedIndex -items $script:menuItems
        }
        elseif ($key.VirtualKeyCode -eq 40) {  # Down arrow
            $selectedIndex = ($selectedIndex + 1) % $script:menuItems.Count

            # Clear entire screen and redraw everything
            Clear-Host
            Write-Host ""
            Write-Host "===============================================================" -ForegroundColor DarkGray
            Write-Host "  Services Management" -ForegroundColor White
            Write-Host "===============================================================" -ForegroundColor DarkGray
            Write-Host ""
            $menuStartLine = Show-Menu -selected $selectedIndex -items $script:menuItems
        }
        elseif ($key.VirtualKeyCode -eq 13) {  # Enter
            [Console]::CursorVisible = $true
            $selectedAction = $script:menuItems[$selectedIndex].Name
            break
        }
    }

    # Clear menu and show selection
    [Console]::SetCursorPosition(0, $menuStartLine)
    $linesToClear = ($script:menuItems.Count * 3) + 2
    for ($i = 0; $i -lt $linesToClear; $i++) {
        Write-Host (" " * [Console]::WindowWidth)
    }
    [Console]::SetCursorPosition(0, $menuStartLine)

    if ($selectedAction -eq "quit") {
        Write-Host ""
        Write-ColorOutput "Exiting without performing any action." "Yellow"
        Write-Host ""
        exit 0
    }

    Write-ColorOutput "Selected: $($script:menuItems[$selectedIndex].Title)" "Green"
    Write-Host ""

    return $selectedAction
}

# Main execution loop
$firstRun = $true
do {
    # Get action from menu if in interactive mode
    if ($interactiveMode) {
        # Clear screen before showing menu (except on first run)
        if (-not $firstRun) {
            Clear-Host
        }
        $firstRun = $false
        $Action = Show-InteractiveMenu
    }

    # Execute the selected action
    switch ($Action) {
        "start" { Start-Services }
        "start-one" { Start-OneService }
        "stop" { Stop-Services }
        "status" { Show-Status }
        "restart" { Restart-Services }
        "stop-one" { Stop-OneService }
    }

    # In interactive mode, prompt user before showing menu again
    if ($interactiveMode) {
        Write-Host ""
        Write-ColorOutput "Press any key to return to menu or [Esc] to exit..." "DarkGray"
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        # Check if user pressed Escape
        if ($key.VirtualKeyCode -eq 27) {
            Write-Host ""
            Write-ColorOutput "Exiting..." "Yellow"
            Write-Host ""
            exit 0
        }
    }

    # In command-line mode, exit after executing once
    # In interactive mode, continue looping (menu will be shown again)
} while ($interactiveMode)
