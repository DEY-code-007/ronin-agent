# RONIN launcher: starts the whole stack and opens the face as an app window.
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File RONIN.ps1 [-Startup]
# Works from wherever the install lives: the install folder is the parent of this script's folder.
# Every piece is skipped if it is already running, so a second launch only reopens the window.
#   8797 HUD sidecar (hidden)   8790 face server (hidden)   8791 backtalk's lock = the voice (minimized)
#   Telegram: ronin-telegram\start_telegram.cmd (minimized), detected by its claude.exe command line
#   Remote:   ronin-remote\start_remote.cmd (minimized, optional), same detection
#   Island:   ronin-island (Electron, optional)
# What starts is controlled by config.json -> launcher (see config.example.json).
param([switch]$Startup)

$root = Split-Path -Parent $PSScriptRoot
$app  = $PSScriptRoot
$log  = Join-Path $app 'ronin-app.log'
$prof = Join-Path $app 'edge-profile'

function Log($msg) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg" | Add-Content -Path $log -Encoding utf8 }
function PortUp($port) { [bool](Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) }
function Opt($obj, $name, $default) { if ($null -ne $obj -and $null -ne $obj.$name) { $obj.$name } else { $default } }
function ClaudeRunning($pattern) {
    [bool](Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue |
           Where-Object { $_.CommandLine -like $pattern })
}

$cfg = $null
try { $cfg = Get-Content (Join-Path $root 'config.json') -Raw -Encoding utf8 | ConvertFrom-Json } catch { }
$launcher = Opt $cfg 'launcher' $null
$hudPort  = [int](Opt (Opt $cfg 'hud' $null) 'port' 8797)
$url      = Opt $cfg 'face_url' 'http://127.0.0.1:8790/faces/radial/'

# Python: the backtalk venv if it exists (created by uv on the first voice start), else python on PATH.
$py = Join-Path $root 'backtalk\.venv\Scripts\python.exe'
if (-not (Test-Path $py)) { $c = Get-Command python.exe -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike '*WindowsApps*' } | Select-Object -First 1; if ($c) { $py = $c.Source } else { $py = $null } }
$uv = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
if (-not (Test-Path $uv)) { $c = Get-Command uv.exe -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { $uv = $c.Source } else { $uv = $null } }
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1

# Claude Code sets this in its own shells; cmd then can't find relative commands.
$env:NoDefaultCurrentDirectoryInExePath = $null

try {
    if ($Startup) { Start-Sleep -Seconds 15 }   # let audio devices and the network come up after logon
    Log "launch (startup=$Startup, root=$root)"

    if ((Opt $launcher 'start_hud' $true) -and $py -and -not (PortUp $hudPort)) {
        Start-Process $py -ArgumentList "`"$root\ronin-hud\hud_server.py`"" -WindowStyle Hidden
        Log 'hud: started'
    }
    if ((Opt $launcher 'start_face' $true) -and $py -and (Test-Path "$root\ai-visualizer\server.py") -and -not (PortUp 8790)) {
        Start-Process $py -ArgumentList 'server.py', '--no-open' -WorkingDirectory "$root\ai-visualizer" -WindowStyle Hidden
        Log 'face: started'
    }
    if ((Opt $launcher 'start_voice' $true) -and (Test-Path "$root\backtalk") -and -not (PortUp 8791)) {
        if ($uv) {
            # Minimized, not hidden: if the voice fails, the error must stay readable ("pause" holds the window).
            $cmd = "title Agent voice && `"$uv`" sync --inexact && `"$uv`" run python -m backtalk.main || pause"
            Start-Process cmd.exe -ArgumentList '/c', $cmd -WorkingDirectory "$root\backtalk" -WindowStyle Minimized
            Log 'voice: started'
        } else { Log 'voice: uv not found, skipped' }
    }
    if ((Opt $launcher 'start_telegram' $false) -and -not (ClaudeRunning '*--channels plugin:telegram*')) {
        Start-Process cmd.exe -ArgumentList '/c', "`"$root\ronin-telegram\start_telegram.cmd`"" -WindowStyle Minimized
        Log 'telegram: started'
    }
    if ((Opt $launcher 'start_remote_control' $false) -and -not (ClaudeRunning '*--remote-control*')) {
        Start-Process cmd.exe -ArgumentList '/c', "`"$root\ronin-remote\start_remote.cmd`"" -WindowStyle Minimized
        Log 'remote: started'
    }
    $electron = Join-Path $root 'ronin-island\node_modules\electron\dist\electron.exe'
    if ((Opt $launcher 'start_island' $false) -and (Test-Path $electron)) {
        $island = Get-CimInstance Win32_Process -Filter "Name='electron.exe'" -ErrorAction SilentlyContinue |
                  Where-Object { $_.CommandLine -like '*ronin-island*' }
        if (-not $island) { Start-Process $electron -ArgumentList "`"$root\ronin-island`""; Log 'island: started' }
    }

    if (-not (Opt $launcher 'open_face_window' $true)) { exit 0 }
    for ($i = 0; $i -lt 60 -and -not (PortUp 8790); $i++) { Start-Sleep -Milliseconds 500 }
    if (-not (PortUp 8790)) { Log 'face: NOT listening after 30s, window not opened'; exit 1 }
    if (-not $edge) { Start-Process $url; Log 'window: Edge not found, opened in the default browser'; exit 0 }

    $open = Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -like '*--app=*' }
    if ($open) { Log 'window: already open'; exit 0 }

    Start-Process $edge -ArgumentList "--app=$url", "--user-data-dir=`"$prof`"", '--window-size=1200,800',
        '--no-first-run', '--no-default-browser-check', '--autoplay-policy=no-user-gesture-required'
    Log 'window: opened'
}
catch {
    Log "error: $_"
    exit 1
}
