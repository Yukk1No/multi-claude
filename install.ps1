# multi-claude installer for Windows.
#
#   irm https://github.com/thomasog/multi-claude/releases/latest/download/install.ps1 | iex
#   powershell -ExecutionPolicy Bypass -File install.ps1     (from a clone: installs that checkout)
#
# Installs the `multi-claude` command for the current user, no admin: files go to
# %USERPROFILE%\.multi-claude and its bin folder joins your user PATH. The release workflow stamps
# this file with its version and the archive's SHA-256, so the download is pinned and verified.
# Everything runs in its own scope: piped through `iex`, nothing leaks into your session.

& {
    $ErrorActionPreference = 'Stop'
    $repo    = 'thomasog/multi-claude'
    $version = '__VERSION__'
    $sha256  = '__SHA256__'
    $root    = Join-Path $env:USERPROFILE '.multi-claude'

    # A failure sets the exit code without `exit`, which would close a window that piped us into iex.
    function Show-Failure([string]$text) { Write-Host $text -ForegroundColor Red; $global:LASTEXITCODE = 1 }

    if (-not (Get-AppxPackage -Name Claude -ErrorAction SilentlyContinue)) {
        return Show-Failure 'Claude Desktop was not found. Install it from https://claude.ai/download'
    }
    # Inside an app package (e.g. a terminal opened from Claude Desktop) Windows redirects these writes.
    $packaged = try {
        Add-Type -Namespace MultiClaudeSetup -Name Native -MemberDefinition '[DllImport("kernel32.dll")] public static extern int GetCurrentPackageFullName(ref int length, System.Text.StringBuilder name);'
        $length = 0; [MultiClaudeSetup.Native]::GetCurrentPackageFullName([ref]$length, $null) -ne 15700
    } catch { $false }
    if ($packaged) { return Show-Failure 'Run this from a regular PowerShell window: this one runs inside an app package, where Windows redirects file writes.' }

    $tmp = $null
    try {
        # 1. The files: this checkout, or the pinned release archive checked against its SHA-256.
        $checkout = if ($PSCommandPath) { Join-Path (Split-Path $PSCommandPath) 'src\windows' }
        if ($checkout -and (Test-Path (Join-Path $checkout 'multi-claude.ps1'))) {
            $src = $checkout
        } else {
            if ($version.StartsWith('__')) { return Show-Failure 'This installer is not from a release. Run it from a clone, or use the release URL.' }
            $tmp = Join-Path ([IO.Path]::GetTempPath()) ('multi-claude-' + [guid]::NewGuid())
            New-Item -ItemType Directory -Path $tmp | Out-Null
            $zip = Join-Path $tmp 'multi-claude.zip'
            Write-Host "Downloading multi-claude $version ..."
            Invoke-WebRequest "https://github.com/$repo/releases/download/$version/multi-claude.zip" -OutFile $zip -UseBasicParsing
            $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
            if ($actual -ne $sha256) { return Show-Failure "Checksum mismatch (expected $sha256, got $actual). Nothing was installed." }
            Expand-Archive $zip -DestinationPath $tmp
            $src = Join-Path $tmp 'src\windows'
        }

        # 2. The command.
        $app = Join-Path $root 'app'
        $bin = Join-Path $root 'bin'
        New-Item -ItemType Directory -Path $app, $bin -Force | Out-Null
        Copy-Item (Join-Path $src '*') $app -Force
        Set-Content -Path (Join-Path $bin 'multi-claude.cmd') -Encoding Ascii -Value @(
            '@echo off'
            # One line, so cmd never reads past it: `multi-claude uninstall` deletes this very file.
            'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\app\multi-claude.ps1" %* & exit /b'
        )
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($userPath -split ';') -notcontains $bin) {
            [Environment]::SetEnvironmentVariable('Path', (@($userPath, $bin) | Where-Object { $_ }) -join ';', 'User')
        }
        if (($env:Path -split ';') -notcontains $bin) { $env:Path += ";$bin" }
        Write-Host ''
        Write-Host '  multi-claude is installed. Add a profile with: multi-claude add Work --color blue' -ForegroundColor Green
        Write-Host ''

        # 3. The first profile, right away.
        $name = Read-Host 'Name your first profile (e.g. Work), or press Enter to skip'
        if ($name) {
            $color = Read-Host 'Color (e.g. blue) [green]'
            if (-not $color) { $color = 'green' }
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $app 'multi-claude.ps1') add $name --color $color
        }
    } finally {
        if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
