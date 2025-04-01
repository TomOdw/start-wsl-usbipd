[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$port
)

# Set your WSL distribution ID
$distributionID = "0d13c747-6401-4950-9b93-a460e1ea3f1f"

Write-Output "Using port: $port"

# Step 1 & 2: Get output from usbipd list and extract the BUSID for the given port
$listOutput = usbipd list
$the_busid = $null

foreach ($line in $listOutput) {
    if ($line -match $port) {
        # Assume the first column is the BUSID
        $fields = $line -split "\s+"
        $the_busid = $fields[0]
        break
    }
}

if ($the_busid) {
    Write-Output "Found BUSID: $the_busid for port $port"

    # Step 3: Bind the device (suppressing errors by redirecting stderr)
    Write-Output "Binding device with BUSID: $the_busid"
    & usbipd bind --busid $the_busid 2>$null
}
else {
    Write-Output "Port $port not found. Skipping bind and attach steps."
}

# Step 4a: Start a background WSL process to ensure a WSL 2 distribution is running.
Write-Output "Starting WSL distribution in background to enable attach..."
$bgProcess = Start-Process "C:\WINDOWS\system32\wsl.exe" `
    -ArgumentList "--distribution-id", $distributionID, "-e", "tail", "-f", "/dev/null" `
    -WindowStyle Hidden -PassThru

# Give the distribution a moment to start
# Start-Sleep -Seconds 1

if ($the_busid) {
    # Step 4b: Attach the device (again, suppressing errors)
    Write-Output "Attaching device with BUSID: $the_busid"
    & usbipd attach --wsl --busid $the_busid 2>$null
}

# Step 5: Start the tmux session in WSL (foreground)
Write-Output "Starting tmux session in WSL..."
& "C:\WINDOWS\system32\wsl.exe" --distribution-id $distributionID --cd ~ tmux new-session -A

# Once the foreground session ends, perform cleanup
Write-Output "Foreground WSL session ended. Detaching device..."
if ($the_busid) {
    & usbipd detach --busid $the_busid 2>$null
    & usbipd unbind --busid $the_busid 2>$null
}

# Stop the background WSL process if it is still running.
if ($bgProcess -and -not $bgProcess.HasExited) {
    Write-Output "Stopping background WSL process..."
    Stop-Process -Id $bgProcess.Id -Force
}
