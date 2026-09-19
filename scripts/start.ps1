<#
.SYNOPSIS
  Start the gateway: LiteLLM in front of your local Ollama, plus an optional public tunnel.

.PARAMETER Tunnel
  quick  (default) Free Cloudflare quick tunnel. No account, random URL each run.
  named  Cloudflare named tunnel. Stable URL on your own domain (see SETUP.md).
  none   Local only, no public URL.

.PARAMETER Port
  Local port for LiteLLM (default 4000).

.PARAMETER BindHost
  Interface LiteLLM listens on (default 127.0.0.1, this machine only; the tunnel
  connects locally). Use 0.0.0.0 to also allow other devices on your LAN.

.EXAMPLE
  .\scripts\start.ps1
  .\scripts\start.ps1 -Tunnel none
#>
param(
  [ValidateSet('quick', 'named', 'none')]
  [string]$Tunnel = 'quick',
  [int]$Port = 4000,
  [string]$BindHost = '127.0.0.1'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

function Require-Command($name, $hint) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) { Fail "'$name' not found. $hint" }
  return $cmd.Source
}

# --- 1. Prerequisites -------------------------------------------------------
$litellmExe = Require-Command 'litellm' 'Install it with: pip install "litellm[proxy]"'
if ($Tunnel -ne 'none') {
  $cloudflaredExe = Require-Command 'cloudflared' 'Install it from https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/'
}

if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
  Fail "Port $Port is already in use. Stop whatever is using it, or pass -Port <other>."
}

$models = @()
try {
  # 127.0.0.1, not "localhost": Windows PowerShell tries IPv6 ::1 first and waits ~2s for it to fail.
  $tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5
  $models = @($tags.models | ForEach-Object { $_.name })
} catch {
  Fail "Can't reach Ollama at http://localhost:11434. Start it (open the Ollama app or run 'ollama serve') and retry."
}
if ($models.Count -eq 0) { Fail "Ollama has no models yet. Pull one first, e.g.: ollama pull llama3.2" }

# --- 2. .env (create with a fresh master key on first run) -------------------
if (-not (Test-Path '.env')) {
  $bytes = New-Object byte[] 32
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  $rng.GetBytes($bytes); $rng.Dispose()
  $key = 'sk-' + [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
  $template = Get-Content '.env.example' -Raw
  $template = $template -replace '(?m)^LITELLM_MASTER_KEY=.*$', "LITELLM_MASTER_KEY=$key"
  Set-Content -Path '.env' -Value $template -Encoding ascii
  Write-Host "Created .env with a new master key." -ForegroundColor Yellow
}

foreach ($line in Get-Content '.env') {
  if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
    $value = $Matches[2].Trim('"').Trim("'")
    if ($value) { Set-Item -Path "Env:$($Matches[1])" -Value $value }
  }
}
if (-not $env:LITELLM_MASTER_KEY) { Fail "LITELLM_MASTER_KEY is empty in .env. Refusing to start without auth." }

# LiteLLM prints a Unicode banner; redirected output on Windows defaults to cp1252 and crashes without this.
$env:PYTHONUTF8 = '1'

New-Item -ItemType Directory -Force -Path 'logs' | Out-Null
$procs = @()

function Stop-All {
  foreach ($p in $script:procs) {
    if ($p -and -not $p.HasExited) { & taskkill /PID $p.Id /T /F 2>&1 | Out-Null }  # /T: launcher + child python
  }
}

try {
  # --- 3. LiteLLM ------------------------------------------------------------
  Write-Host "Starting LiteLLM on port $Port ..."
  $lite = Start-Process -FilePath $litellmExe `
    -ArgumentList '--config', 'LiteLLM/config.yaml', '--host', $BindHost, '--port', $Port `
    -NoNewWindow -PassThru `
    -RedirectStandardOutput 'logs/litellm.out.log' -RedirectStandardError 'logs/litellm.err.log'
  $procs += $lite

  $ready = $false
  for ($i = 0; $i -lt 60; $i++) {
    if ($lite.HasExited) { break }
    try {
      Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health/readiness" -UseBasicParsing -TimeoutSec 5 | Out-Null
      $ready = $true; break
    } catch { Start-Sleep -Seconds 1 }
  }
  if (-not $ready) { Fail "LiteLLM didn't come up. See logs/litellm.err.log and logs/litellm.out.log" }

  # --- 4. Tunnel -------------------------------------------------------------
  $publicUrl = $null
  if ($Tunnel -eq 'quick') {
    Write-Host "Opening quick tunnel ..."
    $cf = Start-Process -FilePath $cloudflaredExe `
      -ArgumentList 'tunnel', '--config', 'cloudflared/quick-tunnel.yml', '--url', "http://127.0.0.1:$Port", '--no-autoupdate' `
      -NoNewWindow -PassThru `
      -RedirectStandardOutput 'logs/cloudflared.out.log' -RedirectStandardError 'logs/cloudflared.err.log'
    $procs += $cf
    for ($i = 0; $i -lt 40 -and -not $publicUrl; $i++) {
      if ($cf.HasExited) { break }
      Start-Sleep -Seconds 1
      $text = (Get-Content 'logs/cloudflared.err.log' -Raw -ErrorAction SilentlyContinue) + (Get-Content 'logs/cloudflared.out.log' -Raw -ErrorAction SilentlyContinue)
      if ($text -match 'https://[a-z0-9-]+\.trycloudflare\.com') { $publicUrl = $Matches[0] }
    }
    if (-not $publicUrl) { Fail "Tunnel didn't report a URL. See logs/cloudflared.err.log" }
  }
  elseif ($Tunnel -eq 'named') {
    Write-Host "Starting named tunnel ..."
    if ($env:CLOUDFLARE_TUNNEL_TOKEN) {
      $cfArgs = @('tunnel', '--no-autoupdate', 'run', '--token', $env:CLOUDFLARE_TUNNEL_TOKEN)
    } elseif ((Test-Path 'cloudflared/config.yml') -and -not ((Get-Content 'cloudflared/config.yml' -Raw) -match '<TUNNEL-UUID>')) {
      $cfArgs = @('tunnel', '--no-autoupdate', '--config', 'cloudflared/config.yml', 'run')
    } else {
      # Repo template not filled in: use cloudflared's own default config (~/.cloudflared/config.yml).
      $cfArgs = @('tunnel', '--no-autoupdate', 'run')
    }
    $cf = Start-Process -FilePath $cloudflaredExe -ArgumentList $cfArgs -NoNewWindow -PassThru `
      -RedirectStandardOutput 'logs/cloudflared.out.log' -RedirectStandardError 'logs/cloudflared.err.log'
    $procs += $cf
    Start-Sleep -Seconds 4
    if ($cf.HasExited) { Fail "cloudflared exited. See logs/cloudflared.err.log" }
    $publicUrl = $env:PUBLIC_URL   # cloudflared can't tell us the hostname, so it's optional in .env
  }

  # --- 5. Summary ------------------------------------------------------------
  $base = "http://localhost:$Port"
  if ($publicUrl) { $base = $publicUrl.TrimEnd('/') }
  $example = $models[0]

  Write-Host ""
  Write-Host "Gateway is up." -ForegroundColor Green
  Write-Host "  Local URL : http://localhost:$Port/v1"
  if ($publicUrl) { Write-Host "  Public URL: $base/v1" -ForegroundColor Green }
  elseif ($Tunnel -eq 'named') { Write-Host "  Public URL: (the hostname you mapped to the tunnel, add /v1; set PUBLIC_URL in .env to see it here)" }
  Write-Host "  API key   : $($env:LITELLM_MASTER_KEY)"
  Write-Host "  Models    : $($models -join ', ')"
  Write-Host ""
  Write-Host "Try it (PowerShell):"
  Write-Host "  Invoke-RestMethod -Uri `"$base/v1/chat/completions`" -Method Post -Headers @{Authorization=`"Bearer <key>`"} -ContentType 'application/json' -Body '{`"model`":`"$example`",`"messages`":[{`"role`":`"user`",`"content`":`"Hello`"}]}'"
  Write-Host ""
  Write-Host "Any OpenAI SDK: base_url = $base/v1 , api_key = <key above> , model = $example"
  if ($Tunnel -eq 'quick') { Write-Host "Quick-tunnel URLs change every run; use -Tunnel named for a permanent one." -ForegroundColor DarkGray }
  Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray

  while (-not $lite.HasExited) { Start-Sleep -Seconds 2 }
  Write-Host "LiteLLM exited. See logs/litellm.err.log" -ForegroundColor Red
}
finally {
  Stop-All
}
