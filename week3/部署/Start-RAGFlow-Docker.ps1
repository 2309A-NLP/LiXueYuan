<#
.SYNOPSIS
One-click Docker launcher for the local RAGFlow stack.

.EXAMPLE
.\Start-RAGFlow-Docker.ps1

.EXAMPLE
.\Start-RAGFlow-Docker.ps1 -Device gpu

.EXAMPLE
.\Start-RAGFlow-Docker.ps1 -Action logs -Follow
#>
[CmdletBinding()]
param(
    [ValidateSet("up", "restart", "stop", "down", "logs", "status", "pull")]
    [string]$Action = "up",

    [ValidateSet("infinity", "elasticsearch", "opensearch", "oceanbase", "seekdb")]
    [string]$DocEngine = "infinity",

    [ValidateSet("cpu", "gpu")]
    [string]$Device = "cpu",

    [string]$ProjectName = "ragflow_local",

    [int]$WebPort = 0,

    [int]$HttpsPort = 0,

    [int]$WaitTimeoutSeconds = 600,

    [switch]$Pull,

    [switch]$Follow,

    [switch]$UseDockerEnvPorts,

    [switch]$SkipPortCheck
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DockerDir = Join-Path $RepoRoot "docker"
$EnvFile = Join-Path $DockerDir ".env"
$ComposeFile = Join-Path $DockerDir "docker-compose.yml"

$IsolatedHostPorts = [ordered]@{
    SVR_WEB_HTTP_PORT = "8080"
    SVR_WEB_HTTPS_PORT = "8443"
    SVR_HTTP_PORT = "19380"
    ADMIN_SVR_HTTP_PORT = "19381"
    SVR_MCP_PORT = "19382"
    GO_ADMIN_PORT = "19383"
    GO_HTTP_PORT = "19384"
    EXPOSE_MYSQL_PORT = "15455"
    MINIO_PORT = "19000"
    MINIO_CONSOLE_PORT = "19001"
    REDIS_PORT = "16379"
    INFINITY_THRIFT_PORT = "33817"
    INFINITY_HTTP_PORT = "33820"
    INFINITY_PSQL_PORT = "15432"
    ES_PORT = "11200"
    OS_PORT = "11201"
    OCEANBASE_PORT = "12881"
    SEEKDB_PORT = "12882"
    KIBANA_PORT = "16601"
    TEI_PORT = "16380"
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Note {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found. Install Docker Desktop and try again."
    }
}

function Test-DockerReady {
    & docker info *> $null
    return $LASTEXITCODE -eq 0
}

function Start-DockerDesktopIfAvailable {
    $isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $dockerDesktop = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
    if ($isWindowsHost -and (Test-Path -LiteralPath $dockerDesktop)) {
        Write-Step "Starting Docker Desktop"
        Start-Process -FilePath $dockerDesktop -WindowStyle Hidden
        return $true
    }
    return $false
}

function Wait-ForDocker {
    param([int]$TimeoutSeconds = 180)

    if (Test-DockerReady) {
        return
    }

    [void](Start-DockerDesktopIfAvailable)
    Write-Step "Waiting for Docker to become ready"

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if (Test-DockerReady) {
            return
        }
    }

    throw "Docker is not ready. Open Docker Desktop, wait until it finishes starting, then run this script again."
}

function Get-EnvValue {
    param(
        [string]$Name,
        [string]$DefaultValue = ""
    )

    $processValue = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ($processValue) {
        return $processValue
    }

    if (Test-Path -LiteralPath $EnvFile) {
        foreach ($line in Get-Content -LiteralPath $EnvFile) {
            if ($line -match "^\s*$([regex]::Escape($Name))\s*=\s*(.+?)\s*$") {
                $value = $matches[1].Trim()
                $value = $value.Trim('"').Trim("'")
                if ($value -match "^\$\{[^:}]+:-([^}]+)\}$") {
                    return $matches[1]
                }
                return $value
            }
        }
    }

    return $DefaultValue
}

function Get-EnvPort {
    param(
        [string]$Name,
        [int]$DefaultValue
    )

    $value = Get-EnvValue -Name $Name -DefaultValue ([string]$DefaultValue)
    $port = 0
    if ([int]::TryParse($value, [ref]$port)) {
        return $port
    }
    return $DefaultValue
}

function Set-IsolatedHostPorts {
    if ($UseDockerEnvPorts) {
        return
    }

    foreach ($entry in $IsolatedHostPorts.GetEnumerator()) {
        if (-not [Environment]::GetEnvironmentVariable($entry.Key, "Process")) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
        }
    }
}

function Get-PortPlan {
    $ports = [ordered]@{
        "RAGFlow web UI" = Get-EnvPort "SVR_WEB_HTTP_PORT" 80
        "RAGFlow HTTPS" = Get-EnvPort "SVR_WEB_HTTPS_PORT" 443
        "RAGFlow API" = Get-EnvPort "SVR_HTTP_PORT" 9380
        "RAGFlow admin API" = Get-EnvPort "ADMIN_SVR_HTTP_PORT" 9381
        "RAGFlow MCP" = Get-EnvPort "SVR_MCP_PORT" 9382
        "MySQL" = Get-EnvPort "EXPOSE_MYSQL_PORT" 3306
        "MinIO API" = Get-EnvPort "MINIO_PORT" 9000
        "MinIO console" = Get-EnvPort "MINIO_CONSOLE_PORT" 9001
        "Redis" = Get-EnvPort "REDIS_PORT" 6379
    }

    if ($Device -eq "cpu") {
        $ports["Go API"] = Get-EnvPort "GO_HTTP_PORT" 9384
        $ports["Go admin API"] = Get-EnvPort "GO_ADMIN_PORT" 9383
    }

    switch ($DocEngine) {
        "infinity" {
            $ports["Infinity thrift"] = Get-EnvPort "INFINITY_THRIFT_PORT" 23817
            $ports["Infinity HTTP"] = Get-EnvPort "INFINITY_HTTP_PORT" 23820
            $ports["Infinity PostgreSQL"] = Get-EnvPort "INFINITY_PSQL_PORT" 5432
        }
        "elasticsearch" {
            $ports["Elasticsearch"] = Get-EnvPort "ES_PORT" 1200
        }
        "opensearch" {
            $ports["OpenSearch"] = Get-EnvPort "OS_PORT" 1201
        }
        "oceanbase" {
            $ports["OceanBase"] = Get-EnvPort "OCEANBASE_PORT" 2881
        }
        "seekdb" {
            $ports["SeekDB"] = Get-EnvPort "SEEKDB_PORT" 2881
        }
    }

    return $ports
}

function Test-PortConflicts {
    if ($SkipPortCheck) {
        return
    }

    $ports = Get-PortPlan
    $busy = @()
    foreach ($entry in $ports.GetEnumerator()) {
        if ($entry.Value -le 0) {
            continue
        }

        try {
            $listener = Get-NetTCPConnection -LocalPort $entry.Value -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($listener) {
                $busy += [pscustomobject]@{
                    Name = $entry.Key
                    Port = $entry.Value
                    ProcessId = $listener.OwningProcess
                }
            }
        } catch {
            return
        }
    }

    if ($busy.Count -gt 0) {
        Write-Host ""
        Write-Host "Port check found listeners that may conflict with Docker:" -ForegroundColor Yellow
        $busy | Format-Table -AutoSize | Out-String | Write-Host
        Write-Host "Startup was stopped so existing containers are not disturbed." -ForegroundColor Yellow
        Write-Host "Change the ports in docker\.env, pass -WebPort/-HttpsPort, or use the default isolated ports." -ForegroundColor Yellow
        Write-Host ""
        throw "Port conflict detected. RAGFlow was not started."
    }
}

function Invoke-RagFlowCompose {
    param([string[]]$ComposeArgs)

    $profileArgs = @("--profile", $DocEngine, "--profile", $Device)
    Push-Location $DockerDir
    try {
        & docker compose @profileArgs @ComposeArgs
        if ($LASTEXITCODE -ne 0) {
            throw "docker compose failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
}

function Wait-ForRagFlowWeb {
    param(
        [int]$Port,
        [int]$TimeoutSeconds
    )

    if ($TimeoutSeconds -le 0) {
        return
    }

    $url = "http://127.0.0.1:$Port"
    Write-Step "Waiting for RAGFlow web UI at $url"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                Write-Host "RAGFlow is responding at $url" -ForegroundColor Green
                return
            }
        } catch {
            Start-Sleep -Seconds 5
        }
    }

    Write-Host "RAGFlow did not respond within $TimeoutSeconds seconds. Check logs with:" -ForegroundColor Yellow
    Write-Host "  .\Start-RAGFlow-Docker.ps1 -Action logs -Follow" -ForegroundColor Yellow
}

function Show-Endpoints {
    $web = Get-EnvPort "SVR_WEB_HTTP_PORT" 80
    $api = Get-EnvPort "SVR_HTTP_PORT" 9380
    $admin = Get-EnvPort "ADMIN_SVR_HTTP_PORT" 9381
    $minio = Get-EnvPort "MINIO_CONSOLE_PORT" 9001

    Write-Host ""
    Write-Host "RAGFlow Docker stack is configured." -ForegroundColor Green
    Write-Host "  Web UI:        http://127.0.0.1:$web"
    Write-Host "  API:           http://127.0.0.1:$api"
    Write-Host "  Admin API:     http://127.0.0.1:$admin"
    Write-Host "  MinIO console: http://127.0.0.1:$minio"
    Write-Host ""
    Write-Host "Useful commands:"
    Write-Host "  .\Start-RAGFlow-Docker.ps1 -Action logs -Follow"
    Write-Host "  .\Start-RAGFlow-Docker.ps1 -Action status"
    Write-Host "  .\Start-RAGFlow-Docker.ps1 -Action stop"
    Write-Host "  .\Start-RAGFlow-Docker.ps1 -Action down"
}

if (-not (Test-Path -LiteralPath $ComposeFile)) {
    throw "Cannot find $ComposeFile. Run this script from the RAGFlow repository root."
}

Require-Command "docker"
Wait-ForDocker
& docker compose version *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Docker Compose v2 is required. Update Docker Desktop and try again."
}

$env:DOC_ENGINE = $DocEngine
$env:DEVICE = $Device
$env:COMPOSE_PROFILES = "$DocEngine,$Device"
$env:COMPOSE_PROJECT_NAME = $ProjectName

Set-IsolatedHostPorts

if ($WebPort -gt 0) {
    $env:SVR_WEB_HTTP_PORT = [string]$WebPort
}
if ($HttpsPort -gt 0) {
    $env:SVR_WEB_HTTPS_PORT = [string]$HttpsPort
}

Write-Step "Using Docker profiles: $DocEngine, $Device"
Write-Note "Compose project: $ProjectName"
if (-not $UseDockerEnvPorts) {
    Write-Note "Using isolated host ports so existing containers are left untouched"
}

switch ($Action) {
    "up" {
        Test-PortConflicts
        $args = @("up", "-d")
        if ($Pull) { $args += "--pull"; $args += "always" }
        Invoke-RagFlowCompose $args
        Wait-ForRagFlowWeb -Port (Get-EnvPort "SVR_WEB_HTTP_PORT" 80) -TimeoutSeconds $WaitTimeoutSeconds
        Show-Endpoints
    }
    "restart" {
        Test-PortConflicts
        Invoke-RagFlowCompose @("down")
        $args = @("up", "-d")
        if ($Pull) { $args += "--pull"; $args += "always" }
        Invoke-RagFlowCompose $args
        Wait-ForRagFlowWeb -Port (Get-EnvPort "SVR_WEB_HTTP_PORT" 80) -TimeoutSeconds $WaitTimeoutSeconds
        Show-Endpoints
    }
    "stop" {
        Invoke-RagFlowCompose @("stop")
    }
    "down" {
        Invoke-RagFlowCompose @("down")
    }
    "logs" {
        $args = @("logs", "--tail", "200")
        if ($Follow) { $args += "-f" }
        Invoke-RagFlowCompose $args
    }
    "status" {
        Invoke-RagFlowCompose @("ps")
    }
    "pull" {
        Invoke-RagFlowCompose @("pull")
    }
}
