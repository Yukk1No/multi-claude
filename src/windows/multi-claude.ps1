# multi-claude for Windows - run several Claude Desktop accounts side by side.
# https://github.com/thomasog/multi-claude
#
# A profile is the official Claude Desktop started with its own --user-data-dir, so it keeps its own
# sign-in. Windows groups taskbar buttons by AppUserModelID and every Claude window declares the same
# one, so while a profile is open, `open` stays running hidden and gives that profile's windows the ID
# "MultiClaude.<name>" - the ID of its Start menu shortcut - so it gets its own button. It exits when
# the profile closes. If tagging ever fails, windows just show under the regular Claude button.

$ErrorActionPreference = 'Stop'
$Version = '0.1.0'
$Root    = Join-Path $env:USERPROFILE '.multi-claude'
$Palette = [ordered]@{
    green = '1F6F43'; blue = '1F4E8C'; purple = '5B3A8E'; red = '9B2C2C'
    teal  = '146C6C'; pink = 'A0346B'; gray   = '4A4F57'
}
$NotFound = 'Claude Desktop was not found. Install it from https://claude.ai/download'

function Say([string]$text, [string]$color) { if ($color) { Write-Host $text -ForegroundColor $color } else { Write-Host $text } }
function Fail([string]$text, [int]$code = 1) { [Console]::Error.WriteLine($text); exit $code }

$Usage = @"
multi-claude $Version - several Claude Desktop accounts side by side

  multi-claude add <name> [--color <color>]   new profile: own sign-in, icon and taskbar button
  multi-claude list                           installed profiles
  multi-claude open <name>                    open a profile (what its shortcut runs)
  multi-claude remove <name>                  remove a profile (its sign-in data is kept)
  multi-claude doctor [--selftest]            check this PC
  multi-claude uninstall                      remove multi-claude and every profile shortcut

Colors: $($Palette.Keys -join ', ') or a hex value like C0392B
"@

# --- arguments ---------------------------------------------------------------------------------------
$Command = $null; $Name = $null; $Color = 'green'; $Preview = $null; $SelfTest = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ([string]$args[$i]) {
        '^(-c|--color)$' { if ($i + 1 -ge $args.Count) { Fail '--color needs a value.' 64 }; $Color = [string]$args[++$i]; break }
        '^--preview$'    { if ($i + 1 -ge $args.Count) { Fail '--preview needs a folder.' 64 }; $Preview = [string]$args[++$i]; break }
        '^--selftest$'   { $SelfTest = $true; break }
        '^(-h|--help)$'  { $Command = 'help'; break }
        '^(-v|--version)$' { $Command = 'version'; break }
        '^-'             { Fail "Unknown option '$_'.`n`n$Usage" 64 }
        default {
            if (-not $Command) { $Command = $_.ToLower() }
            elseif (-not $Name) { $Name = $_ }
            else { Fail "Unexpected argument '$_'.`n`n$Usage" 64 }
        }
    }
}

# --- helpers -----------------------------------------------------------------------------------------
# Validates the name and adopts an existing profile's spelling, so `open work` finds profile "Work".
function Assert-Name {
    if ($Name -notmatch '^[A-Za-z0-9-]{1,24}$') { Fail 'Profile name: letters, digits and dashes, up to 24 characters (e.g. Work).' 64 }
    $existing = Get-ProfileName | Where-Object { $_ -eq $Name }   # -eq ignores case
    if ($existing) { $script:Name = $existing }
}
function Get-DataDir([string]$n)    { Join-Path $env:LOCALAPPDATA "Claude-$n" }
function Get-ProfileDir([string]$n) { Join-Path $Root "profiles\$n" }
function Get-Shortcut([string]$n)   { Join-Path ([Environment]::GetFolderPath('Programs')) "Claude $n.lnk" }
function Get-ClaudePackage          { Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue | Select-Object -First 1 }
function Get-LaunchAlias            { Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\claude-desktop.exe' }
function Get-ProfileName           { @(Get-ChildItem (Join-Path $Root 'profiles') -Directory -ErrorAction SilentlyContinue | ForEach-Object Name) }

function Import-Interop {
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Fail "PowerShell runs in $($ExecutionContext.SessionState.LanguageMode) mode here (usually a company policy), so multi-claude can't set icons or taskbar buttons."
    }
    try { Add-Type -Path (Join-Path $PSScriptRoot 'MultiClaude.cs') -ReferencedAssemblies System.Drawing }
    catch { Fail "Could not load multi-claude's Windows helpers (blocked by a security policy?): $($_.Exception.Message)" }
}

# Inside an MSIX package context (e.g. a terminal opened from Claude Desktop) Windows redirects AppData
# writes, so Start menu shortcuts would land where Windows can't see them.
function Assert-NotPackaged {
    if ([MultiClaude.Package]::IsPackaged()) { Fail 'Run this from a regular terminal: this one runs inside an app package, where Windows redirects file writes.' 3 }
}

# The app's main processes only: not its helpers (--type=), not Claude Code's own claude.exe.
function Get-ClaudeMainProcess {
    @(Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" |
        Where-Object { $_.ExecutablePath -like '*\WindowsApps\Claude_*' -and $_.CommandLine -notmatch '--type=' })
}

# Claude in Chrome: browsers find Claude through one registry entry per user, and every Claude
# instance writes its own data folder there. Keep it pointing at the regular Claude.
$ChromeHostKeys = 'Google\Chrome', 'Microsoft\Edge', 'BraveSoftware\Brave-Browser', 'Chromium' |
    ForEach-Object { "HKCU:\Software\$_\NativeMessagingHosts\com.anthropic.claude_browser_extension" }
$ProfileHostPath = '\\Claude-([A-Za-z0-9-]+)\\ChromeNativeHost\\'
function Get-MainChromeHost { Join-Path $env:APPDATA 'Claude\ChromeNativeHost\com.anthropic.claude_browser_extension.json' }

function Repair-ChromePairing {
    $main = Get-MainChromeHost
    $package = Get-ClaudePackage
    $mirrored = if ($package) { Join-Path $env:LOCALAPPDATA "Packages\$($package.PackageFamilyName)\LocalCache\Roaming\Claude\ChromeNativeHost\com.anthropic.claude_browser_extension.json" }
    if (-not ((Test-Path $main) -or ($mirrored -and (Test-Path $mirrored)))) { return }   # regular Claude never paired
    foreach ($key in $ChromeHostKeys) {
        if ((Test-Path $key) -and ((Get-Item $key).GetValue('') -match $ProfileHostPath)) { Set-Item -Path $key -Value $main }
    }
}

# "Chrome: regular Claude", "Edge: profile Work"... for each browser that has the pairing.
function Get-ChromePairing {
    $pairs = foreach ($key in $ChromeHostKeys | Where-Object { Test-Path $_ }) {
        $browser = ($key -split '\\')[-3]
        if ((Get-Item $key).GetValue('') -match $ProfileHostPath) { "${browser}: profile $($Matches[1])" } else { "${browser}: regular Claude" }
    }
    if ($pairs) { $pairs -join ', ' } else { 'not set up' }
}
function Get-ProfileOf($process) {
    if ($process.CommandLine -match '--user-data-dir="?[^"]*\\Claude-([A-Za-z0-9-]+)"?') { return $Matches[1] }
    '(default)'
}
function Get-OpenArgument([string]$n) {
    $powershell = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    '--headless "{0}" -NoProfile -ExecutionPolicy Bypass -File "{1}" open {2}' -f $powershell, $PSCommandPath, $n
}

# --- commands ----------------------------------------------------------------------------------------
function Invoke-Add {
    Assert-Name
    $hex = if ($Palette.Contains($Color.ToLower())) { $Palette[$Color.ToLower()] } else { $Color.TrimStart('#') }
    if ($hex -notmatch '^[0-9A-Fa-f]{6}$') { Fail "Unknown color '$Color'. Use $($Palette.Keys -join ', ') or a hex value like C0392B." 64 }
    $package = Get-ClaudePackage
    if (-not $package -or -not (Test-Path (Get-LaunchAlias))) { Fail $NotFound }
    $logo = Join-Path $package.InstallLocation 'Assets\Square44x44Logo.targetsize-256_altform-unplated.png'
    if (-not (Test-Path $logo)) { Fail "Claude's logo was not found in its package: $logo" }
    Import-Interop
    if (-not $Preview) { Assert-NotPackaged }

    $dir      = if ($Preview) { Join-Path $Preview $Name } else { Get-ProfileDir $Name }
    $shortcut = if ($Preview) { Join-Path $Preview "Claude $Name.lnk" } else { Get-Shortcut $Name }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    # The icon is Claude's own installed logo, recolored: no artwork ships with this tool.
    $rgb  = [Convert]::ToInt32($hex, 16)
    $icon = [MultiClaude.Icon]::Recolor($logo, [Drawing.Color]::FromArgb(($rgb -shr 16) -band 255, ($rgb -shr 8) -band 255, $rgb -band 255))
    $ico  = Join-Path $dir 'icon.ico'
    [MultiClaude.Icon]::SaveIco($icon, $ico)
    $icon.Save((Join-Path $dir 'icon.png'), [Drawing.Imaging.ImageFormat]::Png)
    $icon.Dispose()

    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
    $link.TargetPath   = Join-Path $env:windir 'System32\conhost.exe'
    $link.Arguments    = Get-OpenArgument $Name
    $link.IconLocation = "$ico,0"
    $link.Description  = "Claude Desktop - $Name"
    $link.WindowStyle  = 7
    $link.Save()
    [MultiClaude.Shortcut]::SetId($shortcut, "MultiClaude.$Name")
    if ([MultiClaude.Shortcut]::GetId($shortcut) -ne "MultiClaude.$Name") { Fail "Could not set the taskbar ID on $shortcut" }

    if ($Preview) { Say "Preview written to $Preview"; return }
    Say ''
    Say "  Claude $Name is ready." Green
    Say '  Open it from the Start menu, then right-click its taskbar button > Pin to taskbar.'
    Say '  To sign in, choose "Sign in with a code". With single sign-on, quit the regular Claude first:'
    Say '  the browser hands the login to whichever Claude is open.'
}

function Invoke-List {
    $profiles = Get-ProfileName
    if (-not $profiles) { Say 'No profiles yet. Add one with: multi-claude add <name>'; return }
    $running = @(Get-ClaudeMainProcess | ForEach-Object { Get-ProfileOf $_ })
    foreach ($p in $profiles) {
        Say ('{0,-16} {1,-8} {2}' -f $p, $(if ($running -contains $p) { 'running' } else { '' }), (Get-DataDir $p))
    }
}

function Invoke-Remove {
    Assert-Name
    $dir = Get-ProfileDir $Name
    if (-not (Test-Path $dir)) { Fail "No profile named '$Name'." }
    Import-Interop
    Assert-NotPackaged
    $shortcut = Get-Shortcut $Name
    if (Test-Path $shortcut) { Remove-Item -LiteralPath $shortcut -Force }
    Remove-Item -LiteralPath $dir -Recurse -Force
    Repair-ChromePairing
    Say "Removed Claude $Name. Unpin its taskbar button if pinned."
    Say "Its sign-in data is kept in $(Get-DataDir $Name) - delete that folder to sign out for good."
}

function Invoke-Open {
    Assert-Name
    $id       = "MultiClaude.$Name"
    $ico      = Join-Path (Get-ProfileDir $Name) 'icon.ico'
    $log      = Join-Path (Get-ProfileDir $Name) 'open.log'
    $relaunch = '"{0}" {1}' -f (Join-Path $env:windir 'System32\conhost.exe'), (Get-OpenArgument $Name)
    function Write-Log([string]$text) {
        if ((Test-Path $log) -and (Get-Item $log).Length -gt 256KB) { Remove-Item $log -Force -ErrorAction SilentlyContinue }
        Add-Content -LiteralPath $log -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $text) -ErrorAction SilentlyContinue
    }

    # Started from inside a Claude session, we would hand its CLAUDE_*/ANTHROPIC_* variables to Claude.
    Get-ChildItem Env: | Where-Object Name -Match '^(CLAUDE|ANTHROPIC)' | ForEach-Object { Remove-Item -LiteralPath "Env:$($_.Name)" }
    if (-not (Test-Path (Get-LaunchAlias))) { Write-Log $NotFound; Fail $NotFound }
    Repair-ChromePairing
    Start-Process -FilePath (Get-LaunchAlias) -ArgumentList ('--user-data-dir="{0}"' -f (Get-DataDir $Name))

    $isFirst = $false
    $mutex = New-Object System.Threading.Mutex($true, "Local\MultiClaude-$Name", [ref]$isFirst)
    if (-not $isFirst) { return }   # this profile already has a watcher
    Import-Interop
    try {
        $start = Get-Date; $pids = @(); $goneSince = $null
        while ($true) {
            $elapsed = ((Get-Date) - $start).TotalSeconds
            $pids = @($pids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
            if (-not $pids) {
                $pids = @(Get-ClaudeMainProcess | Where-Object { (Get-ProfileOf $_) -eq $Name } | ForEach-Object { [uint32]$_.ProcessId })
            }
            if ($pids) {
                $goneSince = $null
                try { Repair-ChromePairing } catch { Write-Log "keeping Claude in Chrome paired failed: $($_.Exception.Message)" }
                foreach ($hwnd in [MultiClaude.Window]::Of([uint32[]]$pids)) {
                    try {
                        if ([MultiClaude.Window]::GetId($hwnd) -ne $id) {
                            [MultiClaude.Window]::Tag($hwnd, $id, $relaunch, "Claude $Name", $ico)
                            Write-Log "tagged window $hwnd"
                        }
                    } catch { Write-Log "tagging window $hwnd failed: $($_.Exception.Message)" }
                }
            } else {
                if (-not $goneSince) { $goneSince = Get-Date }
                $grace = if ($elapsed -lt 60) { 60 } else { 15 }   # a first launch builds the profile: be patient
                if (((Get-Date) - $goneSince).TotalSeconds -gt $grace) { break }
            }
            Start-Sleep -Milliseconds $(if ($elapsed -lt 30) { 300 } else { 2000 })
        }
    } finally {
        Repair-ChromePairing
        $mutex.ReleaseMutex(); $mutex.Dispose()
    }
}

function Invoke-Doctor {
    $package = Get-ClaudePackage
    Say "multi-claude $Version"
    Say ('Claude Desktop:   ' + $(if ($package) { $package.Version } else { 'not found - https://claude.ai/download' }))
    Say ('Launch alias:     ' + $(if (Test-Path (Get-LaunchAlias)) { 'ok' } else { 'missing' }))
    Say ('PowerShell mode:  ' + $ExecutionContext.SessionState.LanguageMode)
    Say ('Browser pairing:  ' + (Get-ChromePairing))
    Import-Interop
    Say ('Package context:  ' + $(if ([MultiClaude.Package]::IsPackaged()) { 'yes - run add/remove from a regular terminal' } else { 'no' }))
    Say ''
    Invoke-List
    $windows = foreach ($p in Get-ClaudeMainProcess) {
        foreach ($hwnd in [MultiClaude.Window]::Of([uint32[]]@($p.ProcessId))) {
            $id = try { [MultiClaude.Window]::GetId($hwnd) } catch { "error: $($_.Exception.Message)" }
            '  {0,-16} taskbar id: {1}' -f (Get-ProfileOf $p), $(if ($id) { $id } else { 'Claude default' })
        }
    }
    if ($windows) { Say ''; Say 'Open windows:'; $windows | ForEach-Object { Say $_ } }
    if (-not $SelfTest) { return }

    # Tag a throwaway Character Map window and read the ID back.
    $charmap = Start-Process -FilePath (Join-Path $env:windir 'System32\charmap.exe') -PassThru
    try {
        $hwnd = [IntPtr]::Zero
        for ($i = 0; $i -lt 50 -and $hwnd -eq [IntPtr]::Zero; $i++) {
            Start-Sleep -Milliseconds 200
            $found = [MultiClaude.Window]::Of([uint32[]]@($charmap.Id)); if ($found) { $hwnd = $found[0] }
        }
        if ($hwnd -eq [IntPtr]::Zero) { Fail 'Self-test: the Character Map window did not appear.' }
        [MultiClaude.Window]::Tag($hwnd, 'MultiClaude.SelfTest', 'charmap.exe', 'multi-claude self-test', $charmap.Path)
        $ok = [MultiClaude.Window]::GetId($hwnd) -eq 'MultiClaude.SelfTest'
        [MultiClaude.Window]::Close($hwnd)
        Say ''
        if ($ok) { Say 'Self-test: PASS - taskbar tagging works on this PC' Green } else { Fail 'Self-test: FAIL - the taskbar ID was not set' }
    } finally {
        Start-Sleep -Milliseconds 500
        if (-not $charmap.HasExited) { Stop-Process -Id $charmap.Id -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-Uninstall {
    Import-Interop
    Assert-NotPackaged
    foreach ($p in Get-ProfileName) { $s = Get-Shortcut $p; if (Test-Path $s) { Remove-Item -LiteralPath $s -Force } }
    Repair-ChromePairing
    $bin  = Join-Path $Root 'bin'
    $path = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($path) {
        $kept = ($path -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $bin }) -join ';'
        if ($kept -ne $path) { [Environment]::SetEnvironmentVariable('Path', $kept, 'User') }
    }
    # The multi-claude.cmd running this command lives in $Root, and cmd.exe fails if its batch file
    # vanishes mid-run: delete the folder a moment after we exit.
    if (Test-Path $Root) {
        $cmd = Join-Path $env:windir 'System32\cmd.exe'
        Start-Process $cmd -WindowStyle Hidden -ArgumentList "/d /c ping -n 3 127.0.0.1 >nul & rmdir /s /q `"$Root`""
    }
    Say 'multi-claude removed. Unpin any profile buttons from the taskbar.'
    Say "Sign-in data is kept in $env:LOCALAPPDATA\Claude-* - delete those folders to sign out for good."
}

switch ($Command) {
    'add'       { Invoke-Add }
    'list'      { Invoke-List }
    'open'      { Invoke-Open }
    'remove'    { Invoke-Remove }
    'doctor'    { Invoke-Doctor }
    'uninstall' { Invoke-Uninstall }
    'version'   { Say "multi-claude $Version" }
    'help'      { Say $Usage }
    $null       { Say $Usage }
    default     { Fail "Unknown command '$Command'.`n`n$Usage" 64 }
}
