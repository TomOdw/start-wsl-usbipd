[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$port
)

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
$existingBgWSL = Get-CimInstance Win32_Process -Filter "Name = 'wsl.exe'" | Where-Object { 
   $_.CommandLine -match 'tail -f /dev/null'
   }
if ( !($existingBgWSL) ) {
   $bgProcess = Start-Process "wsl" `
    -ArgumentList  "-e", "tail", "-f", "/dev/null" `
    -WindowStyle Hidden -PassThru
}

# Give the distribution a moment to start
# Start-Sleep -Seconds 1

# Step 4b: Start a background job to repeatedly run the attach command every 2 seconds.
if ($the_busid) {
   $existingJob = Get-Job -Name "usbipdAttachLoop" -ErrorAction SilentlyContinue
   if( !($existingJob) ){
      Write-Output "Starting background attach loop for device $the_busid..."
      $attachJob = Start-Job -Name "usbipd-autoattach-wsl-job" -ScriptBlock {
         param($busid)
         while ($true) {
            # Attempt to attach; suppress any errors.
            usbipd attach --wsl --busid $busid 2>$null
            Start-Sleep -Seconds 2
         }
      } -ArgumentList $the_busid
   }
}

# Step 5: Start the tmux session in WSL (foreground)
Write-Output "Starting tmux session in WSL..."
& "wsl" --cd ~ tmux new-session -A

# When the foreground session exits, clean up:
Write-Output "Foreground WSL session ended. Stopping background attach loop and detaching device..."

if ($the_busid) {
    # Stop the background attach job
    if ($attachJob -and ($attachJob.State -eq 'Running' -or $attachJob.State -eq 'NotStarted')) {
        Stop-Job -Job $attachJob
        Remove-Job -Job $attachJob
    }

    # Detach and unbind the device, suppressing errors.
    & usbipd detach --busid $the_busid 2>$null
    & usbipd unbind --busid $the_busid 2>$null
}

# Stop the background WSL process if it is still running.
if ($bgProcess -and -not $bgProcess.HasExited) {
    Write-Output "Stopping background WSL process..."
    Stop-Process -Id $bgProcess.Id -Force
}
