# Start on boot (optional)

Everything works fine if you start the gateway by hand when you want it. This page is for when you want the URL to be **always available whenever your computer is on**, without you doing anything.

> **Status.** The Windows Scheduled Task recipe works on Windows 11 as a normal (non-admin) user, and the macOS launchd recipe works on macOS 27 (Apple Silicon). An actual reboot or logon hasn't been tried with either, and the Linux systemd recipe hasn't been run by the maintainers. If you use one, please open an issue or PR with what worked or didn't.

## Before you set this up

1. **Use a named tunnel or Tailscale Funnel.** A quick tunnel's URL is random and changes on every start, so after a reboot nobody would know the new URL. See [tunnels.md](tunnels.md).
2. **Run the gateway by hand once first** (`start.ps1 -Tunnel named` / `start.sh --tunnel named`), so you know it works and `.env` exists.
3. **Ollama must be running too.** The Ollama desktop app starts at login on Windows and macOS by default. On Linux, the install script sets up an `ollama` systemd service.
4. Autostart on **login** means the gateway is only up while you're logged in. For a machine that should serve without anyone logged in, use a proper service (systemd on Linux) instead.

## Windows: Scheduled Task

Run in PowerShell. Change `$repo` to where you cloned the project.

```powershell
$repo = "C:\path\to\homeport"

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$repo\scripts\start.ps1`" -Tunnel named"

# -User matters: without it the trigger means "any user logs on", which needs administrator
# rights and fails with "Access is denied" in a normal PowerShell window.
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

# Windows' defaults would stop the task after 72 hours and when on battery power.
$settings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName 'Homeport' -Action $action -Trigger $trigger -Settings $settings
```

Try it without rebooting:

```powershell
Start-ScheduledTask -TaskName 'Homeport'
Get-Content "$repo\logs\litellm.err.log" -Tail 5    # is LiteLLM up?
```

Stop and remove it:

```powershell
Stop-ScheduledTask -TaskName 'Homeport'
Unregister-ScheduledTask -TaskName 'Homeport' -Confirm:$false
```

`Stop-ScheduledTask` ends the whole gateway: the script places LiteLLM and the tunnel in a Windows job that is closed when the script's process ends, so nothing is left running afterwards.

Because the window is hidden, the script's summary (URL, key) isn't visible. Your key is in `.env`, and your URL is the hostname you configured.

## Linux: systemd user service

Create `~/.config/systemd/user/homeport.service`:

```ini
[Unit]
Description=Homeport (local LLM API gateway)
After=network-online.target

[Service]
WorkingDirectory=/path/to/homeport
ExecStart=/path/to/homeport/scripts/start.sh --tunnel named
# systemd has a minimal PATH; make sure litellm and cloudflared are on it.
Environment=PATH=/usr/local/bin:/usr/bin:/bin:%h/.local/bin
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

Enable and start it:

```bash
systemctl --user daemon-reload
systemctl --user enable --now homeport
journalctl --user -u homeport -f          # follow the output
```

A user service normally stops when you log out. To keep it running without a login session:

```bash
loginctl enable-linger "$USER"
```

## macOS: launchd agent

> **Keep the project folder out of Documents, Desktop, Downloads and iCloud Drive.** macOS privacy protection stops background jobs from reading them. The agent loads but exits with status 126 ("Operation not permitted") and the gateway never starts. Put the project somewhere unprotected, such as `~/homeport`.

A fresh Mac may not have the LaunchAgents folder yet:

```bash
mkdir -p ~/Library/LaunchAgents
```

Create `~/Library/LaunchAgents/com.homeport.plist` (change the paths):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.homeport</string>
  <key>ProgramArguments</key>
  <array>
    <string>/path/to/homeport/scripts/start.sh</string>
    <string>--tunnel</string>
    <string>named</string>
  </array>
  <key>WorkingDirectory</key><string>/path/to/homeport</string>
  <key>EnvironmentVariables</key>
  <dict>
    <!-- launchd has a minimal PATH; include where litellm and cloudflared live (Homebrew shown). -->
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
```

`launchd` does not expand `$HOME`, so write the full path to your home directory (for example `/Users/you/.local/bin`).

Start it, check it, and stop it:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.homeport.plist
launchctl list | grep homeport
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.homeport.plist   # to stop
```

The older `launchctl load` and `unload` still work but are deprecated, and `load` on a missing file prints "Load failed" yet exits with status 0, so confirm with `launchctl list`.

Because of `KeepAlive`, launchd restarts the script within about 15 seconds whenever it exits, including when LiteLLM or the tunnel dies. If you add `StandardOutPath` for logging, remember that the script's startup summary prints your API key, so that file would contain it (and may be readable by other users). The script's own logs in `logs/` don't contain the key.

## Checking that it survived a reboot

1. Reboot and log in.
2. Wait a minute or two (Ollama and LiteLLM both take a moment to start).
3. From another device, call your URL with your key (see [using-the-api.md](using-the-api.md)).

If it doesn't work, check the logs in `logs/` and see [troubleshooting.md](troubleshooting.md).
