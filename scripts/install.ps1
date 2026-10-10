<#
.SYNOPSIS
  Install everything Homeport needs: Ollama, LiteLLM (in a private .venv) and cloudflared.
.DESCRIPTION
  Uses winget for Python, cloudflared and Ollama. Safe to run again: anything already
  installed is kept, and LiteLLM is upgraded.
.PARAMETER Model
  Model to pull if Ollama has none yet (default llama3.2, about 2 GB).
.PARAMETER NoModel
  Don't pull a model.
.PARAMETER NoTunnel
  Skip cloudflared (local-only use).
#>
param(
  [string]$Model = 'llama3.2',
  [switch]$NoModel,
  [switch]$NoTunnel
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Venv = Join-Path $Root '.venv'
$VenvPy = Join-Path $Venv 'Scripts\python.exe'

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Have($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }
# winget installs update PATH in the registry, not in this session; reload it.
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Winget-Install($id) {
  & winget install --id $id --exact --silent --accept-source-agreements --accept-package-agreements
  # -1978335189: already installed / no newer version.
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { Fail "winget install $id failed (exit $LASTEXITCODE)." }
  Refresh-Path
}

if (-not (Have 'winget')) {
  Fail "winget not found. Install 'App Installer' from the Microsoft Store, or install the tools by hand (see SETUP.md)."
}

# --- 1. Python 3.10+ ----------------------------------------------------------
Step 'Python 3.10 or newer'
function Py-Ok($exe, [string[]]$pre = @()) {
  try { & $exe @pre -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>$null; return $LASTEXITCODE -eq 0 }
  catch { return $false }
}
function Find-Python {
  # The py launcher picks the newest installed Python; plain "python" may be the Microsoft Store stub.
  if ((Have 'py') -and (Py-Ok 'py' @('-3'))) { return ,@('py', '-3') }
  if ((Have 'python') -and (Py-Ok 'python')) { return ,@('python') }
  return $null
}
$py = Find-Python
if (-not $py) {
  Write-Host 'Installing Python 3.12 with winget ...'
  Winget-Install 'Python.Python.3.12'
  $py = Find-Python
  if (-not $py) { Fail 'Python was installed but cannot be found yet. Open a new PowerShell window and run this again.' }
}
$pyExe = $py[0]; $pyArgs = @($py | Select-Object -Skip 1)
Write-Host "Using $(& $pyExe @pyArgs --version)"

# --- 2. LiteLLM in .venv ------------------------------------------------------
Step 'LiteLLM (into .venv)'
if ((Test-Path $VenvPy) -and -not (Py-Ok $VenvPy)) {
  Write-Host 'Existing .venv uses an old Python; recreating it.'
  Remove-Item -Recurse -Force $Venv
}
if (-not (Test-Path $VenvPy)) {
  & $pyExe @pyArgs -m venv $Venv
  if ($LASTEXITCODE -ne 0) { Fail "Couldn't create a virtual environment in $Venv." }
}
& $VenvPy -m pip install --quiet --upgrade pip
if ($LASTEXITCODE -ne 0) { Fail 'pip upgrade failed.' }
& $VenvPy -m pip install --quiet --upgrade 'litellm[proxy]'
if ($LASTEXITCODE -ne 0) { Fail 'Installing LiteLLM failed.' }
Write-Host "LiteLLM $(& $VenvPy -c 'import importlib.metadata as m; print(m.version(''litellm''))') installed."

# --- 3. cloudflared -----------------------------------------------------------
if (-not $NoTunnel) {
  Step 'cloudflared'
  if (Have 'cloudflared') { Write-Host 'Already installed.' } else { Winget-Install 'Cloudflare.cloudflared' }
}

# --- 4. Ollama ----------------------------------------------------------------
Step 'Ollama'
if (Have 'ollama') { Write-Host 'Already installed.' } else { Winget-Install 'Ollama.Ollama' }

function Ollama-Up {
  try { Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 } catch { $null }
}
$tags = Ollama-Up
if (-not $tags) {
  Write-Host 'Starting Ollama ...'
  $app = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe'
  if (Test-Path $app) { Start-Process $app } elseif (Have 'ollama') { Start-Process 'ollama' -ArgumentList 'serve' -WindowStyle Hidden }
  for ($i = 0; $i -lt 20 -and -not $tags; $i++) { Start-Sleep 1; $tags = Ollama-Up }
}

# --- 5. A model ---------------------------------------------------------------
if (-not $tags) {
  Write-Host "Ollama is installed but not running. Open the Ollama app (or run 'ollama serve') before scripts\start.ps1." -ForegroundColor Yellow
} elseif (@($tags.models).Count -gt 0) {
  Write-Host 'Ollama is running and has models.'
} elseif (-not $NoModel) {
  Step "Pulling $Model (first model; this can take a while)"
  & ollama pull $Model
  if ($LASTEXITCODE -ne 0) { Fail "ollama pull $Model failed." }
} else {
  Write-Host 'Ollama has no models yet. Pull one before starting, e.g.: ollama pull llama3.2'
}

Write-Host ""
Write-Host 'All set. Start the gateway with:' -ForegroundColor Green
Write-Host '  .\scripts\start.ps1'
