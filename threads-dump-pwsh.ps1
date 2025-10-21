#threads-dump-pwsh.ps1
#
#
#.\threads-dump-secure.ps1 `
#  -BaseUrl "https://comaus-acres-dt1.pega.net" `
#  -WebNode "Pega-web-6d9d95dd7f-ws7c9" `
#  -Iterations 5 `
#  -DelayInSeconds 5
param(
    [Parameter(Mandatory=$true)]
    [string]$BaseUrl,

    [Parameter(Mandatory=$true)]
    [string]$WebNode,

    [Parameter(Mandatory=$true)]
    [int]$Iterations,

    [int]$DelayInSeconds = 5,

    [int]$MaxRetries = 3
)

# Default username and password
$defaultUser = "your basicauth operator pyIdentifier"
$defaultPassword = "your basicauth operator password"

# Prompt for password (username pre-filled)
$cred = Get-Credential -UserName $defaultUser -Message "Enter your Pega password (press Enter to use default)"
if (-not $cred.GetNetworkCredential().Password) {
    # Use default password if user pressed Enter
    $password = $defaultPassword
} else {
    $password = $cred.GetNetworkCredential().Password
}
$user = $cred.UserName

# Encode credentials in Base64 for Basic Auth
$pair = "$user`:$password"
$bytes = [System.Text.Encoding]::UTF8.GetBytes($pair)
$base64 = [Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "Basic $base64" }

# Ensure logs directory exists
$logDir = "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

# Create script log file
$logFile = "${WebNode}_thread_dump_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
Write-Host "Logging script activity to $logFile"

function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp - $message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

for ($count = 1; $count -le $Iterations; $count++) {

    Write-Log "Starting iteration $count of $Iterations"

    # Generate timestamp for filename
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename = "${WebNode}_${timestamp}.zip"
    $filepath = Join-Path $logDir $filename

    Write-Log "Saving thread dump to $filepath"

    $attempt = 1
    do {
        try {
            Invoke-WebRequest -Uri "$BaseUrl/prweb/api/v1/nodes/$WebNode/diagnostics/thread_dump" `
                -Headers $headers -OutFile $filepath -ErrorAction Stop

            if ((Test-Path $filepath) -and ((Get-Item $filepath).Length -gt 0)) {
                Write-Log "Saved successfully: $filepath"
                break
            } else {
                throw "Empty file"
            }
        } catch {
            Write-Log "Attempt $attempt failed: $_"
            if (Test-Path $filepath) { Remove-Item $filepath -Force }
            Start-Sleep -Seconds 2
            $attempt++
        }
    } while ($attempt -le $MaxRetries)

    if ($attempt -gt $MaxRetries) {
        Write-Log "ERROR: Failed to get thread dump after $MaxRetries attempts."
    }

    Start-Sleep -Seconds $DelayInSeconds
}

# Compress all logs into a single archive
$archiveName = "${WebNode}_thread_dumps_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
Compress-Archive -Path "$logDir\*" -DestinationPath $archiveName -Force
Write-Log "Compressed logs into archive: $archiveName"

# Clean up individual logs
Remove-Item "$logDir\*" -Force
Write-Log "Individual log files removed. Only archive remains."

Write-Log "Script completed successfully."
