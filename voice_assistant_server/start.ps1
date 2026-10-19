<#
  start.ps1 - Khoi dong backend (uvicorn), relay va Cloudflare Tunnel bang mot lenh.

  Dat file nay trong thu muc voice_assistant_server (cung cho voi main.py,
  config.py, .env, relay-server-v2.js).

  Cach dung (PowerShell):
      .\start.ps1               # chay backend + relay + tunnel
      .\start.ps1 -NoTunnel     # chi chay trong mang LAN (khong dung Cloudflare)
      .\start.ps1 -Stop         # dung cac tien trinh do script nay da bat

  Neu bi chan boi ExecutionPolicy:
      powershell -ExecutionPolicy Bypass -File .\start.ps1

  Script doc JWT_SECRET_KEY va JWT_ALGORITHM tu file .env roi dung CHUNG mot
  gia tri cho ca backend lan relay, nen khong can copy secret bang tay.
  (File nay ASCII de tranh loi hien thi tieng Viet tren PowerShell 5.1.)
#>
param(
    [switch]$NoTunnel,
    [switch]$Stop
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

# ---------------- Cau hinh ----------------
$BackendHost = '0.0.0.0'      # 0.0.0.0 = LAN + tunnel; doi thanh 127.0.0.1 neu chi dung tunnel
$BackendPort = 8000
$RelayPort   = 8080
$TunnelName  = 'voice'        # ten tunnel da tao bang: cloudflared tunnel create voice
$ApiHost     = 'api.trolyamthanh.online'
$RelayHost   = 'relay.trolyamthanh.online'
$PlaceholderSecret = 'change_me_to_a_long_random_string'
$PidFile     = Join-Path $PSScriptRoot '.run-pids'
# ------------------------------------------

function Fail([string]$msg) {
    Write-Host "[LOI] $msg" -ForegroundColor Red
    exit 1
}

function Stop-All {
    if (-not (Test-Path $PidFile)) {
        Write-Host 'Khong co tien trinh nao dang duoc theo doi.'
        return
    }
    $allowed = @('uvicorn', 'python', 'node', 'cloudflared')
    foreach ($line in Get-Content $PidFile) {
        $procId = 0
        if ([int]::TryParse($line.Trim(), [ref]$procId)) {
            $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($p -and ($allowed -contains $p.ProcessName.ToLower())) {
                cmd /c "taskkill /PID $procId /T /F >nul 2>&1" | Out-Null
            }
        }
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    Write-Host 'Da dung cac tien trinh cu.'
}

function Read-DotEnv([string]$path) {
    $map = @{}
    foreach ($line in Get-Content $path -Encoding UTF8) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $i = $l.IndexOf('=')
        if ($i -lt 1) { continue }
        $k = $l.Substring(0, $i).Trim()
        $v = $l.Substring($i + 1).Trim()
        $quoted = ($v.Length -ge 2) -and (
            ($v.StartsWith('"') -and $v.EndsWith('"')) -or
            ($v.StartsWith("'") -and $v.EndsWith("'")))
        if ($quoted) {
            $v = $v.Substring(1, $v.Length - 2)
        } else {
            $v = ($v -replace '\s+#.*$', '').Trim()   # bo comment cuoi dong nhu python-dotenv
        }
        $map[$k] = $v
    }
    return $map
}

function Wait-Http([string]$url, [int]$seconds) {
    $end = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $end) {
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Milliseconds 800
    }
    return $false
}

# ---------------- -Stop ----------------
if ($Stop) { Stop-All; exit 0 }

# Don tien trinh do lan chay truoc de lai (neu co)
if (Test-Path $PidFile) { Stop-All; Start-Sleep -Seconds 1 }

# ---------------- Kiem tra moi truong ----------------
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Fail 'Chua cai Node.js (hoac node khong nam trong PATH).'
}

$uvicorn = Join-Path $PSScriptRoot '.venv\Scripts\uvicorn.exe'
if (-not (Test-Path $uvicorn)) {
    $cmd = Get-Command uvicorn -ErrorAction SilentlyContinue
    if (-not $cmd) { Fail 'Khong tim thay uvicorn. Hay cai: pip install uvicorn (hoac kich hoat venv truoc).' }
    $uvicorn = $cmd.Source
}

foreach ($port in @($BackendPort, $RelayPort)) {
    $busy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($busy) {
        $owner = (Get-Process -Id @($busy)[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName
        Fail "Cong $port dang bi chiem boi '$owner'. Dong cua so uvicorn/node cu roi chay lai."
    }
}

# ---------------- Doc .env ----------------
$envFile = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envFile)) {
    Fail 'Khong tim thay file .env canh script nay. Copy .env.example thanh .env roi dien gia tri that.'
}
$cfg = Read-DotEnv $envFile

if (-not $cfg['GEMINI_API_KEY']) { Fail 'Thieu GEMINI_API_KEY trong .env.' }

$secret = $cfg['JWT_SECRET_KEY']
if (-not $secret) {
    Fail 'Thieu JWT_SECRET_KEY trong .env. Sinh key: python -c "import secrets; print(secrets.token_hex(32))"'
}
if ($secret -eq $PlaceholderSecret) {
    Fail 'JWT_SECRET_KEY van la gia tri mau (change_me...). Hay thay bang key that, dai va ngau nhien.'
}
if ($secret.Length -lt 32) {
    Fail 'JWT_SECRET_KEY qua ngan (< 32 ky tu). Hay dung token_hex(32).'
}
$alg = $cfg['JWT_ALGORITHM']
if (-not $alg) { $alg = 'HS256' }

# Backend (config.py) va relay dung CHUNG mot gia tri, ke ca khi may co bien moi truong cu de len.
$env:JWT_SECRET_KEY = $secret
$env:JWT_ALGORITHM  = $alg
$env:JWT_SECRET     = $secret

# ---------------- Thu vien relay ----------------
$hasWs  = Test-Path (Join-Path $PSScriptRoot 'node_modules\ws')
$hasJwt = Test-Path (Join-Path $PSScriptRoot 'node_modules\jsonwebtoken')
if ((-not $hasWs) -or (-not $hasJwt)) {
    Write-Host 'Cai thu vien cho relay (ws, jsonwebtoken)...'
    & npm install ws jsonwebtoken
    if ($LASTEXITCODE -ne 0) { Fail 'npm install that bai.' }
}

# ---------------- Khoi dong ----------------
$started = @()

Write-Host "Khoi dong backend tren cong $BackendPort ..."
$backend = Start-Process -FilePath $uvicorn `
    -ArgumentList 'main:app', '--host', $BackendHost, '--port', "$BackendPort" `
    -WorkingDirectory $PSScriptRoot -PassThru
$started += $backend.Id

Write-Host "Khoi dong relay tren cong $RelayPort ..."
$relay = Start-Process -FilePath 'node' `
    -ArgumentList 'relay-server-v2.js' `
    -WorkingDirectory $PSScriptRoot -PassThru
$started += $relay.Id

$tunnelOn = $false
if (-not $NoTunnel) {
    $cf       = Get-Command cloudflared -ErrorAction SilentlyContinue
    $cfConfig = Join-Path $env:USERPROFILE '.cloudflared\config.yml'
    $cfSvc    = Get-Service -Name cloudflared -ErrorAction SilentlyContinue

    if ($cfSvc -and $cfSvc.Status -eq 'Running') {
        Write-Host 'cloudflared da chay duoi dang dich vu Windows -> khong khoi dong them.'
        $tunnelOn = $true
    } elseif (-not $cf) {
        Write-Warning 'Chua cai cloudflared -> bo qua tunnel (chi dung duoc trong LAN).'
    } elseif (-not (Test-Path $cfConfig)) {
        Write-Warning "Chua co $cfConfig -> bo qua tunnel (chi dung duoc trong LAN)."
    } else {
        Write-Host "Khoi dong Cloudflare Tunnel '$TunnelName' ..."
        $tunnel = Start-Process -FilePath 'cloudflared' `
            -ArgumentList 'tunnel', 'run', $TunnelName -PassThru
        $started += $tunnel.Id
        $tunnelOn = $true
    }
}

$started | Set-Content -Path $PidFile

# ---------------- Kiem tra suc khoe ----------------
Write-Host ''
Write-Host 'Dang kiem tra cac dich vu...'

$okApi   = Wait-Http "http://localhost:$BackendPort/docs" 40
$okRelay = Wait-Http "http://localhost:$RelayPort/health" 20

if ($okApi)   { Write-Host "[OK]  Backend  http://localhost:$BackendPort/docs" -ForegroundColor Green }
else          { Write-Host '[LOI] Backend chua len - xem cua so uvicorn de biet loi.' -ForegroundColor Red }

if ($okRelay) { Write-Host "[OK]  Relay    http://localhost:$RelayPort/health" -ForegroundColor Green }
else          { Write-Host '[LOI] Relay chua len - xem cua so node de biet loi.' -ForegroundColor Red }

if ($tunnelOn) {
    if (Wait-Http "https://$RelayHost/health" 25) {
        Write-Host "[OK]  Tunnel   https://$RelayHost/health" -ForegroundColor Green
    } else {
        Write-Warning "Chua goi duoc https://$RelayHost/health. Kiem tra DNS/nameserver va cua so cloudflared."
    }
}

Write-Host ''
Write-Host 'Dia chi de cau hinh trong app:'
if ($tunnelOn) {
    Write-Host "  Backend : https://$ApiHost"
    Write-Host "  Relay   : wss://$RelayHost"
}
Write-Host "  (LAN)   : http://<IP-LAN-cua-PC>:$BackendPort  va  ws://<IP-LAN-cua-PC>:$RelayPort"
Write-Host ''
Write-Host 'Bay gio mo app Windows (agent) va dang nhap cung tai khoan voi dien thoai.'
Write-Host 'Dung tat ca:  .\start.ps1 -Stop   (hoac dong cac cua so uvicorn / node / cloudflared)'
