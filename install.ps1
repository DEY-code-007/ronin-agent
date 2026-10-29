# ronin-agent installer for Windows (Windows PowerShell 5.1 or PowerShell 7).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -InstallDir "$env:USERPROFILE\ronin" -RegisterTasks
#
# What it does (safe to run again; it never overwrites your vault, config.json or CLAUDE.md):
#   1. checks prerequisites (git, node + npm, python, Claude Code CLI; uv and bun are optional)
#   2. clones the four upstream projects by Jared Rhodenizer from GitHub (never vendored here)
#   3. copies this repo's own layer (ronin-*) into the install folder
#   4. writes config.json, CLAUDE.md, the Telegram prompt and (if missing) backtalk.json from templates
#   5. creates a fresh, empty vault from vault-template\ at a path you choose (only if that folder is empty)
#   6. installs the npm dependencies (Electron) for ronin-island and ronin-guard
#   7. optionally registers Task Scheduler tasks (-RegisterTasks)
#   8. prints the next steps (Telegram bot, optional ElevenLabs key, Claude connectors, hooks)
# It never asks for, reads or stores a token, key or password.
[CmdletBinding()]
param(
    [string]$InstallDir,
    [string]$VaultPath,
    [string]$AgentName,
    [string]$OwnerName,
    [string]$Language,
    [string]$Tone,
    [string]$WelcomeLine,
    [switch]$SkipClone,
    [switch]$SkipNpm,
    [switch]$RegisterTasks,
    [switch]$Yes            # accept defaults for anything not given on the command line
)

$ErrorActionPreference = 'Stop'
$Src = $PSScriptRoot
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

$Upstream = [ordered]@{
    'fullstack-agent' = 'https://github.com/jaredrhod/fullstack-agent'
    'backtalk'        = 'https://github.com/jaredrhod/backtalk'
    'ai-visualizer'   = 'https://github.com/jaredrhod/ai-visualizer'
    'ai-memory-vault' = 'https://github.com/jaredrhod/ai-memory-vault'
}
$Layer = @('ronin-app', 'ronin-hud', 'ronin-island', 'ronin-guard', 'ronin-telegram', 'ronin-reminders', 'ronin-sync', 'ronin-remote')
$SkipNames = @('node_modules', 'data', 'state', 'edge-profile', '__pycache__')

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }
function Step($msg) { Write-Host ''; Write-Host "==> $msg" -ForegroundColor Cyan }
function Ask($prompt, $default) {
    if ($Yes) { return $default }
    $a = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($a)) { $default } else { $a.Trim() }
}
function ReadText($p) { [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function WriteText($p, $t) { [System.IO.File]::WriteAllText($p, $t, $Utf8NoBom) }
function Fill($text) {
    foreach ($k in $Vars.Keys) { $text = $text.Replace('{{' + $k + '}}', $Vars[$k]) }
    $text
}
function FindExe($name) {
    Get-Command $name -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike '*\WindowsApps\*' } | Select-Object -First 1
}
function SamePath($a, $b) {
    [System.IO.Path]::GetFullPath($a).TrimEnd('\') -eq [System.IO.Path]::GetFullPath($b).TrimEnd('\')
}
function CopyTree($from, $to) {
    # Copies files, skipping runtime folders; overwrites code files with the repo version.
    New-Item -ItemType Directory -Force -Path $to | Out-Null
    Get-ChildItem -LiteralPath $from -Force | ForEach-Object {
        if ($SkipNames -contains $_.Name) { return }
        $dest = Join-Path $to $_.Name
        if ($_.PSIsContainer) { CopyTree $_.FullName $dest }
        else { Copy-Item -LiteralPath $_.FullName -Destination $dest -Force }
    }
}

Write-Host ''
Write-Host 'ronin-agent installer' -ForegroundColor White
Write-Host 'Your own AI chief of staff on top of Claude Code, with your own empty memory vault.' -ForegroundColor DarkGray

# ---------------------------------------------------------------- 1. prerequisites
Step 'Checking prerequisites'
$missing = @()
$git = FindExe 'git.exe';     if ($git) { Say "  git     ok  $($git.Source)" } else { $missing += 'git     ->  winget install Git.Git' }
$node = FindExe 'node.exe';   if ($node) { Say "  node    ok  $(& $node.Source --version)" } else { $missing += 'node    ->  winget install OpenJS.NodeJS.LTS' }
$npm = FindExe 'npm.cmd';     if ($npm) { Say '  npm     ok' } elseif ($node) { $missing += 'npm     ->  reinstall Node.js (npm ships with it)' }
$python = FindExe 'python.exe'
if (-not $python) {
    # Fall back to the py launcher or a uv-managed Python.
    $ErrorActionPreference = 'Continue'
    $alt = $null
    $pyl = FindExe 'py.exe'
    if ($pyl) { $alt = (& $pyl.Source -3 -c "import sys; print(sys.executable)" 2>$null) }
    if (-not $alt) { $uvx = FindExe 'uv.exe'; if ($uvx) { $alt = (& $uvx.Source python find 2>$null) } }
    if ($alt -and (Test-Path ([string]$alt).Trim())) { $python = [pscustomobject]@{ Source = ([string]$alt).Trim() } }
    $ErrorActionPreference = 'Stop'
}
if ($python) { Say "  python  ok  $(& $python.Source --version)" } else { $missing += 'python  ->  winget install Python.Python.3.12   (the Microsoft Store stub does not count)' }
$claude = FindExe 'claude.exe'; if (-not $claude) { $claude = FindExe 'claude.cmd' }
if (-not $claude -and (Test-Path "$env:USERPROFILE\.local\bin\claude.exe")) { $claude = Get-Item "$env:USERPROFILE\.local\bin\claude.exe" | Select-Object @{n = 'Source'; e = { $_.FullName } } }
if ($claude) { Say '  claude  ok' } else { $missing += 'claude  ->  install Claude Code: https://docs.claude.com/en/docs/claude-code/setup' }
$uv = FindExe 'uv.exe';   if ($uv) { Say '  uv      ok  (voice)' } else { Say '  uv      missing (optional, needed for the voice: winget install astral-sh.uv)' 'Yellow' }
$bun = FindExe 'bun.exe'; if ($bun) { Say '  bun     ok  (Telegram plugin)' } else { Say '  bun     missing (optional, needed for Telegram: winget install Oven-sh.Bun)' 'Yellow' }
if ($missing.Count) {
    Say ''
    Say 'Missing required tools:' 'Red'
    $missing | ForEach-Object { Say "  $_" 'Red' }
    Say 'Install them, open a NEW terminal, and run this installer again.' 'Red'
    exit 1
}

# ---------------------------------------------------------------- answers
Step 'A few questions (Enter keeps the default)'
if (-not $InstallDir) { $InstallDir = Ask 'Install folder' (Join-Path $env:USERPROFILE 'ronin') }
$InstallDir = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallDir))
if (-not $AgentName) { $AgentName = Ask 'Agent name' 'RONIN' }
while ($AgentName -notmatch '^[A-Za-z0-9][A-Za-z0-9 _-]{0,30}$') {
    if ($Yes) { throw "Agent name '$AgentName' must be letters, digits, space, - or _ (max 31 chars)." }
    $AgentName = Ask 'Agent name (letters, digits, space, - or _ only)' 'RONIN'
}
if (-not $OwnerName) { $OwnerName = Ask 'Your name (what the agent calls you)' 'boss' }
if (-not $Language) { $Language = Ask 'Language the agent answers in (e.g. English, Turkish)' 'English' }
if (-not $Tone) {
    $tones = @{
        '1' = 'Direct and warm, with sharp-witted butler polish. No fluff, no hedging.'
        '2' = 'Talk to me like a friend at a bar: blunt, profane, extremely direct, but with butler polish.'
        '3' = 'Calm, professional and concise.'
    }
    if (-not $Yes) {
        Say '  Tone: 1) direct butler   2) blunt and profane   3) calm professional   (or type your own sentence)'
    }
    $t = Ask 'Tone' '1'
    if ($tones.ContainsKey($t)) { $Tone = $tones[$t] } else { $Tone = $t }
}
if (-not $WelcomeLine) { $WelcomeLine = Ask 'Welcome line (first reply of every session, in your language)' "All systems online, $OwnerName. What are we working on today?" }
if (-not $VaultPath) { $VaultPath = Ask 'Vault folder (your memory; created if missing)' (Join-Path $env:USERPROFILE "$AgentName-memory") }
$VaultPath = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($VaultPath))

$Vars = [ordered]@{
    AGENT_NAME   = $AgentName
    OWNER_NAME   = $OwnerName
    LANGUAGE     = $Language
    TONE         = $Tone
    WELCOME_LINE = $WelcomeLine
    VAULT_PATH   = $VaultPath
    INSTALL_DIR  = $InstallDir
}
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# ---------------------------------------------------------------- 2. upstream clones
Step 'Upstream projects (cloned from GitHub, credited in README)'
if ($SkipClone) { Say '  skipped (-SkipClone)' 'Yellow' }
else {
    foreach ($name in $Upstream.Keys) {
        $dest = Join-Path $InstallDir $name
        if (Test-Path (Join-Path $dest '.git')) { Say "  $name already present (update later with: git -C `"$dest`" pull)"; continue }
        if (Test-Path $dest) { Say "  $name exists but is not a git clone; left untouched" 'Yellow'; continue }
        Say "  cloning $name"
        & $git.Source clone --quiet $Upstream[$name] $dest
        if ($LASTEXITCODE) { Say "  clone of $name failed (network?). Run the installer again later." 'Red' }
    }
}

# ---------------------------------------------------------------- 3. our layer
Step 'ronin-agent layer'
if (SamePath $Src $InstallDir) { Say '  installing in place (install folder is this repo), nothing to copy' }
else {
    foreach ($d in $Layer) { CopyTree (Join-Path $Src $d) (Join-Path $InstallDir $d); Say "  $d" }
    foreach ($f in @('config.example.json', 'README.md', 'README.tr.md', 'LICENSE', 'NOTICE.md')) {
        if (Test-Path (Join-Path $Src $f)) { Copy-Item (Join-Path $Src $f) (Join-Path $InstallDir $f) -Force }
    }
    CopyTree (Join-Path $Src 'templates') (Join-Path $InstallDir 'templates')
}

# ---------------------------------------------------------------- 4. config + boot files
Step 'Configuration'
$cfgPath = Join-Path $InstallDir 'config.json'
if (Test-Path $cfgPath) { Say '  config.json exists, left untouched' }
else {
    $cfg = ReadText (Join-Path $Src 'config.example.json') | ConvertFrom-Json
    $cfg.agent_name = $AgentName
    $cfg.owner_name = $OwnerName
    $cfg.language = $Language
    $cfg.vault_path = $VaultPath
    $cfg.hud.sync_task = "\$AgentName\Vault Sync"
    $cfg.hud.watch_urls = @()
    WriteText $cfgPath ($cfg | ConvertTo-Json -Depth 10)
    Say '  config.json written (edit it any time; no secrets go in it)'
}

$claudeMd = Join-Path $InstallDir 'CLAUDE.md'
$filled = Fill (ReadText (Join-Path $Src 'templates\CLAUDE.md'))
if (Test-Path $claudeMd) {
    WriteText (Join-Path $InstallDir 'CLAUDE.ronin-template.md') $filled
    Say '  CLAUDE.md exists, left untouched; the new version is in CLAUDE.ronin-template.md to compare' 'Yellow'
} else { WriteText $claudeMd $filled; Say '  CLAUDE.md written (boot config)' }

$tgPrompt = Join-Path $InstallDir 'ronin-telegram\telegram-prompt.md'
if (-not (Test-Path $tgPrompt)) {
    WriteText $tgPrompt (Fill (ReadText (Join-Path $Src 'ronin-telegram\telegram-prompt.template.md')))
    Say '  ronin-telegram\telegram-prompt.md written'
}

$btDir = Join-Path $InstallDir 'backtalk'
$btJson = Join-Path $btDir 'backtalk.json'
if ((Test-Path (Join-Path $btDir 'backtalk.json.example')) -and -not (Test-Path $btJson)) {
    $bt = ReadText (Join-Path $btDir 'backtalk.json.example') | ConvertFrom-Json
    $bt.name = $AgentName
    $bt.agent_dir = $InstallDir
    if ($Language -notmatch '^(en|english)$' -and $bt.stt_model -like '*.en') { $bt.stt_model = 'small' }   # multilingual speech recognition
    WriteText $btJson ($bt | ConvertTo-Json -Depth 10)
    Say '  backtalk\backtalk.json written (voice settings: see backtalk\README.md)'
}

# ---------------------------------------------------------------- 5. vault
Step 'Vault'
$vaultHasFiles = (Test-Path $VaultPath) -and [bool](Get-ChildItem -LiteralPath $VaultPath -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($vaultHasFiles) { Say "  $VaultPath already has files: NOT touched (your existing vault stays as it is)" 'Yellow' }
else {
    $tpl = Join-Path $Src 'vault-template'
    Get-ChildItem -LiteralPath $tpl -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($tpl.Length).TrimStart('\')
        $dest = Join-Path $VaultPath (Fill $rel)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        if ($_.Extension -eq '.md') { WriteText $dest (Fill (ReadText $_.FullName)) } else { Copy-Item -LiteralPath $_.FullName -Destination $dest }
    }
    Push-Location $VaultPath
    try {
        & $git.Source init --quiet
        # The vault sync commits on its own; give this repo a local identity if git has no global one.
        $ErrorActionPreference = 'Continue'
        $who = (& $git.Source config user.email 2>$null)
        $ErrorActionPreference = 'Stop'
        if (-not $who) { & $git.Source config user.name "$AgentName vault sync"; & $git.Source config user.email 'vault-sync@localhost' }
        Say "  vault created at $VaultPath (local git repo, no remote)"
    } finally { Pop-Location }
}

# Claude Code's own memory file -> pointer into the vault (only if it does not exist yet).
$slug = ($InstallDir -replace '[^A-Za-z0-9-]', '-')   # Claude Code's per-project folder naming
$memDir = Join-Path $env:USERPROFILE ".claude\projects\$slug\memory"
$memFile = Join-Path $memDir 'MEMORY.md'
if (Test-Path $memFile) { Say "  $memFile exists, left untouched (move its contents into the vault, then replace it with templates\MEMORY.md)" 'Yellow' }
else {
    New-Item -ItemType Directory -Force -Path $memDir | Out-Null
    $mem = Fill (ReadText (Join-Path $Src 'templates\MEMORY.md'))
    WriteText $memFile (($mem -replace '(?s)^<!--.*?-->\s*', ''))
    Say '  Claude Code memory pointer written'
}

# ---------------------------------------------------------------- 6. npm
Step 'Electron apps (ronin-island, ronin-guard)'
if ($SkipNpm) { Say '  skipped (-SkipNpm)' 'Yellow' }
else {
    foreach ($d in @('ronin-island', 'ronin-guard')) {
        $p = Join-Path $InstallDir $d
        if (Test-Path (Join-Path $p 'node_modules\electron\dist\electron.exe')) { Say "  $d ok (already installed)"; continue }
        Push-Location $p
        try {
            Say "  npm install in $d (downloads Electron, ~100 MB)"
            & $npm.Source install --no-fund --no-audit --loglevel=error
            if ($LASTEXITCODE) { Say "  npm install failed in $d; run it there by hand later" 'Red' }
        } finally { Pop-Location }
    }
}

# ---------------------------------------------------------------- 7. scheduled tasks
if ($RegisterTasks) {
    Step "Task Scheduler (folder \$AgentName\)"
    $pyw = Join-Path (Split-Path -Parent $python.Source) 'pythonw.exe'
    if (-not (Test-Path $pyw)) { $pyw = $python.Source }
    $tasks = @(
        @{ n = 'Vault Sync';    tr = "`"$pyw`" `"$InstallDir\ronin-sync\sync.py`"";            a = @('/sc', 'minute', '/mo', '30') },
        @{ n = 'Reminders';     tr = "`"$pyw`" `"$InstallDir\ronin-reminders\remind.py`"";     a = @('/sc', 'minute', '/mo', '15') },
        @{ n = 'Daily Summary'; tr = "`"$pyw`" `"$InstallDir\ronin-telegram\daily_summary.py`""; a = @('/sc', 'daily', '/st', '07:30') }
    )
    foreach ($t in $tasks) {
        $tn = "\$AgentName\$($t.n)"
        $ErrorActionPreference = 'Continue'
        cmd.exe /c "schtasks /query /tn `"$tn`" >nul 2>&1"
        $exists = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = 'Stop'
        if ($exists) { Say "  $tn exists, left untouched"; continue }
        & schtasks.exe /create /tn $tn /tr $t.tr @($t.a) /f | Out-Null
        if ($LASTEXITCODE) { Say "  could not create $tn" 'Red'; continue }
        if ($t.n -eq 'Daily Summary') { & schtasks.exe /change /tn $tn /disable | Out-Null; Say "  $tn created (DISABLED until Telegram is set up: schtasks /change /tn `"$tn`" /enable)" }
        else { Say "  $tn created" }
    }
}

# ---------------------------------------------------------------- 8. next steps
$hookCmd = ((Join-Path $InstallDir 'ronin-island\hook.mjs') -replace '\\', '/')
Step 'Done. Next steps'
Say @"
  1. Start your agent: open a terminal in $InstallDir and run:  claude
     It reads CLAUDE.md, then offers to interview you and fill in your vault.

  2. Voice and face (optional): in $InstallDir\fullstack-agent run  claude "set me up"
     and pick only the voice/face parts; or start everything with:
       powershell -NoProfile -ExecutionPolicy Bypass -File "$InstallDir\ronin-app\RONIN.ps1"

  3. Telegram (optional):
     a. In Telegram, talk to @BotFather -> /newbot -> copy the token. Never paste it into a chat or a file.
     b. Store it as a USER environment variable (type the value yourself in this prompt):
          `$v = Read-Host 'Bot token' -AsSecureString
          [Environment]::SetEnvironmentVariable('TELEGRAM_BOT_TOKEN', [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$v)), 'User')
        and your numeric chat id (send /start to @userinfobot to see it):
          [Environment]::SetEnvironmentVariable('TELEGRAM_CHAT_ID', '<your chat id>', 'User')
     c. In Claude Code:  /plugin install telegram@claude-plugins-official  then  /telegram:configure  and
        /telegram:access  so ONLY your own Telegram user id is on the allowlist. Keep the plugin disabled
        at user scope; ronin-telegram\start_telegram.cmd enables it for its own session.
     d. Set launcher.start_telegram to true in config.json.

  4. ElevenLabs voice (optional): store the key the same way as ELEVENLABS_API_KEY, put your voice id in
     config.json (reminders.voice_id) and/or backtalk.json, never the key.

  5. Connected accounts (optional): claude.ai -> Settings -> Connectors (mail, calendar, drive...).
     CLAUDE.md already makes the agent show you every email or calendar change and wait for your yes.

  6. RONIN Island hooks (optional): add to %USERPROFILE%\.claude\settings.json under "hooks":
       "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "node $hookCmd working", "timeout": 5 }] }],
       "Stop":             [{ "hooks": [{ "type": "command", "command": "node $hookCmd done", "timeout": 5 }] }],
       "Notification":     [{ "hooks": [{ "type": "command", "command": "node $hookCmd needs", "timeout": 5 }] }],
       "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "node $hookCmd end", "timeout": 5 }] }]
     then set launcher.start_island to true in config.json.

  7. Vault backup (optional): create a PRIVATE GitHub repo, then
       git -C "$VaultPath" remote add origin <your private repo url>
     and run the installer once with -RegisterTasks (or register the tasks yourself).
"@
