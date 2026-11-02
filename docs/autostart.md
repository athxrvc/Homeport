# Start on boot (optional)

Everything works fine if you start the gateway by hand when you want it. This page is for when you want the URL to be **always available whenever your computer is on**, without you doing anything.

> The Windows and macOS recipes below work. The Linux one hasn't been run by the maintainers yet; issues are welcome.

## Before you set this up

- **Use a named tunnel or Tailscale Funnel** ([tunnels](tunnels.md)). A quick tunnel's URL changes every start, so after a reboot nobody would know it.
- **Run the gateway by hand once first** (`start.ps1 -Tunnel named` / `start.sh --tunnel named`) so you know it works and `.env` exists.
- **Ollama must be running too.** Its desktop app starts at login on Windows and macOS; on Linux its installer sets up a service.
- These start the gateway at **login**, so it's only up while you're logged in.

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

`Stop-ScheduledTask` ends the whole gateway, tunnel included. The window is hidden, so the startup summary isn't visible: your key is in `.env` and your URL is the hostname you configured.

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
    <!-- launchd has a minimal PATH. start.sh adds the project's .venv/bin itself, so this only needs the folders of tools you installed some other way (add /opt/homebrew/bin if your cloudflared came from Homebrew). -->
    <key>PATH</key><string>/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
```

`launchd` does not expand `~` or `$HOME` in these values, so write full paths.

Start it, check it, and stop it:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.homeport.plist
launchctl list | grep homeport
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.homeport.plist   # to stop
```

The older `launchctl load` / `unload` still work but are deprecated. Because of `KeepAlive`, launchd restarts the script within about 15 seconds whenever it exits, including when LiteLLM or the tunnel dies. Don't add `StandardOutPath` casually: the startup summary prints your API key, so that file would contain it.

## Checking it after a reboot

Reboot, log in, wait a minute or two (Ollama and LiteLLM take a moment), then call your URL with your key from another device ([using the API](using-the-api.md)). If it doesn't work, check `logs/` and [troubleshooting](troubleshooting.md).
