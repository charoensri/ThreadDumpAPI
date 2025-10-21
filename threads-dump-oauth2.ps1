#threads-dump-oauth2.ps1
#
# OAuth2 Bearer token version
#
#.\threads-dump-oauth2.ps1 `
#  -BaseUrl "https://comaus-acres-dt1.pega.net" `
#  -WebNode "Pega-web-6d9d95dd7f-ws7c9" `
#  -Iterations 5 `
#  -DelayInSeconds 5 `
#  -BearerToken "your-oauth2-token-here"
#.\threads-dump-oauth2.ps1 -BaseUrl "..." -WebNode "..." -Iterations 5 -BearerToken "your-token-here"

#powershell.\threads-dump-oauth2.ps1 `
#  -BaseUrl "https://comaus-acres-dt1.pega.net" `
#  -WebNode "Pega-web-6d9d95dd7f-ws7c9" `
#  -Iterations 5 `
#  -DelayInSeconds 5 `
#  -ClientId "your-client-id" `
#  -ClientSecret "your-client-secret" `
#  -TokenEndpoint "https://your-oauth-server/oauth/token"
#.\threads-dump-oauth2.ps1 -BaseUrl "https://comaus-acres-STG2.pega.net" -WebNode "pega-web-5dd6b6754f-7zspb"" -Iterations 5 -ClientId "OAuth 2.0 Client Registration in Pega ClientID" -ClientSecret "OAuth 2.0 Client Registration in Pega Secret" -TokenEndpoint "https://comaus-acres-stg2.pega.net/prweb/PRRestService/oauth2/v1/token"

param(
    [Parameter(Mandatory=$true)]
    [string]$BaseUrl,
    [Parameter(Mandatory=$true)]
    [string]$WebNode,
    [Parameter(Mandatory=$true)]
    [int]$Iterations,
    [int]$DelayInSeconds = 5,
    [int]$MaxRetries = 3,
    [Parameter(Mandatory=$false)]
    [string]$BearerToken,
    [Parameter(Mandatory=$false)]
    [string]$ClientId,
    [Parameter(Mandatory=$false)]
    [string]$ClientSecret,
    [Parameter(Mandatory=$false)]
    [string]$TokenEndpoint,
    [Parameter(Mandatory=$false)]
    [string]$Scope = ""
)

# Function to obtain OAuth2 token using client credentials flow
function Get-OAuth2Token {
    param(
        [string]$TokenEndpoint,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$Scope
    )
    
    try {
        $body = @{
            grant_type = "client_credentials"
            client_id = $ClientId
            client_secret = $ClientSecret
            scope = $Scope
        }
        
        $response = Invoke-RestMethod -Uri $TokenEndpoint -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        return $response.access_token
    }
    catch {
        Write-Error "Failed to obtain OAuth2 token: $_"
        return $null
    }
}

# Determine authentication method and get token
if ([string]::IsNullOrEmpty($BearerToken)) {
    if ([string]::IsNullOrEmpty($ClientId) -or [string]::IsNullOrEmpty($ClientSecret) -or [string]::IsNullOrEmpty($TokenEndpoint)) {
        Write-Error "Either provide a BearerToken directly, or provide ClientId, ClientSecret, and TokenEndpoint for OAuth2 client credentials flow"
        exit 1
    }
    
    Write-Host "Obtaining OAuth2 token using client credentials flow..."
    $BearerToken = Get-OAuth2Token -TokenEndpoint $TokenEndpoint -ClientId $ClientId -ClientSecret $ClientSecret -Scope $Scope
    
    if ([string]::IsNullOrEmpty($BearerToken)) {
        Write-Error "Failed to obtain OAuth2 token. Exiting."
        exit 1
    }
    
    Write-Host "Successfully obtained OAuth2 token"
} else {
    Write-Host "Using provided Bearer token"
}

# Set up headers with Bearer token
$headers = @{ 
    Authorization = "Bearer $BearerToken"
    Accept = "application/json"
}

# Ensure logs directory exists
$logDir = "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

# Create script log file
$logFile = Join-Path $logDir "${WebNode}_thread_dump_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
Write-Host "Logging script activity to $logFile"

function Write-Log {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp - $message"
    Write-Host $line
    Add-Content -Path $logFile -Value $line
}

Write-Log "Script started with OAuth2 Bearer token authentication"
Write-Log "Base URL: $BaseUrl"
Write-Log "Web Node: $WebNode"
Write-Log "Iterations: $Iterations"

for ($count = 1; $count -le $Iterations; $count++) {
    Write-Log "Starting iteration $count of $Iterations"
    
    # Generate timestamp for filename
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $filename = "${WebNode}_${timestamp}.zip"
    $filepath = Join-Path $logDir $filename
    
    Write-Log "Saving thread dump to $filepath"
    
    $attempt = 1
    $success = $false
    
    do {
        try {
            Write-Log "Attempt $attempt - Making API request..."
            
            Invoke-WebRequest -Uri "$BaseUrl/prweb/api/v1/nodes/$WebNode/diagnostics/thread_dump" `
                -Headers $headers -OutFile $filepath -ErrorAction Stop
            
            if ((Test-Path $filepath) -and ((Get-Item $filepath).Length -gt 0)) {
                $fileSize = (Get-Item $filepath).Length
                Write-Log "Saved successfully: $filepath (Size: $fileSize bytes)"
                $success = $true
                break
            } else {
                throw "Empty or invalid file created"
            }
        } catch {
            $errorMessage = $_.Exception.Message
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode
                Write-Log "Attempt $attempt failed with HTTP $statusCode : $errorMessage"
                
                # Handle specific OAuth2 errors
                if ($statusCode -eq 401) {
                    Write-Log "Authentication failed - token may be expired or invalid"
                } elseif ($statusCode -eq 403) {
                    Write-Log "Access denied - token may not have sufficient permissions"
                }
            } else {
                Write-Log "Attempt $attempt failed: $errorMessage"
            }
            
            # Clean up failed file
            if (Test-Path $filepath) { 
                Remove-Item $filepath -Force 
                Write-Log "Removed incomplete file"
            }
            
            if ($attempt -lt $MaxRetries) {
                Write-Log "Waiting 2 seconds before retry..."
                Start-Sleep -Seconds 2
            }
            $attempt++
        }
    } while ($attempt -le $MaxRetries -and -not $success)
    
    if (-not $success) {
        Write-Log "ERROR: Failed to get thread dump after $MaxRetries attempts."
    }
    
    # Wait between iterations (except for the last one)
    if ($count -lt $Iterations) {
        Write-Log "Waiting $DelayInSeconds seconds before next iteration..."
        Start-Sleep -Seconds $DelayInSeconds
    }
}

# Compress all logs into a single archive
$archiveName = "${WebNode}_thread_dumps_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
Write-Log "Creating archive: $archiveName"

try {
    Compress-Archive -Path "$logDir\*" -DestinationPath $archiveName -Force
    Write-Log "Compressed logs into archive: $archiveName"
    
    # Clean up individual logs (keep the main log file)
    Get-ChildItem -Path $logDir -Exclude "*.txt" | Remove-Item -Force
    Write-Log "Individual dump files removed. Archive and log file remain."
    
} catch {
    Write-Log "ERROR: Failed to create archive: $_"
}

Write-Log "Script completed."