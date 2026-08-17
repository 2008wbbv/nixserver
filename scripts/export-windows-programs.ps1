<#
.SYNOPSIS
    Export every installed program on this Windows box, from all four places
    Windows hides them, into one file you can work from on the NixOS side.

.DESCRIPTION
    No single Windows API knows about everything you've installed. This checks:

      1. winget          — the package manager. Clean IDs, but only knows about
                           things installed through it or matched to its catalog.
      2. Uninstall keys  — the registry. This is the real list: every classic
                           installer registers here, including things winget has
                           never heard of. Both 64- and 32-bit hives.
      3. Appx packages   — Microsoft Store / UWP apps, which live nowhere else.
      4. Steam manifests — your actual game library, parsed off disk.

    Run in PowerShell (no admin needed for most of it; run as admin to catch
    machine-wide installs from other user accounts).

.EXAMPLE
    .\export-windows-programs.ps1
    .\export-windows-programs.ps1 -OutDir C:\temp\export
#>

param(
    [string]$OutDir = "$env:USERPROFILE\Desktop\windows-programs"
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Write-Host "Writing to $OutDir`n" -ForegroundColor Cyan

# --- 1. winget ---------------------------------------------------------------
# The most useful output: machine-readable IDs that map cleanly to search terms.
Write-Host "[1/4] winget export..." -ForegroundColor Yellow
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget export -o "$OutDir\winget.json" --accept-source-agreements 2>$null
    winget list | Out-File -Encoding utf8 "$OutDir\winget-list.txt"
    Write-Host "      ok"
} else {
    Write-Host "      winget not found — skipping" -ForegroundColor DarkGray
}

# --- 2. Registry uninstall entries -------------------------------------------
# The authoritative list. Note both hives: 32-bit apps on 64-bit Windows land
# in WOW6432Node and are invisible if you only check one.
Write-Host "[2/4] registry uninstall keys..." -ForegroundColor Yellow
$paths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$installed = foreach ($p in $paths) {
    Get-ItemProperty $p -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
        Select-Object @{n = 'Name'; e = { $_.DisplayName } },
                      @{n = 'Version'; e = { $_.DisplayVersion } },
                      @{n = 'Publisher'; e = { $_.Publisher } },
                      @{n = 'InstallDate'; e = { $_.InstallDate } }
}

$installed |
    Sort-Object Name -Unique |
    Export-Csv -NoTypeInformation -Encoding utf8 "$OutDir\installed-programs.csv"
Write-Host "      $($installed.Count) entries"

# --- 3. Store / UWP apps -----------------------------------------------------
Write-Host "[3/4] Store apps..." -ForegroundColor Yellow
Get-AppxPackage |
    Where-Object { -not $_.IsFramework -and $_.SignatureKind -ne 'System' } |
    Select-Object Name, PackageFullName, Publisher |
    Sort-Object Name |
    Export-Csv -NoTypeInformation -Encoding utf8 "$OutDir\store-apps.csv"
Write-Host "      ok"

# --- 4. Steam library --------------------------------------------------------
# Parsed straight off disk. Every installed game leaves an appmanifest_*.acf
# with its ID and name, across every library folder you've configured.
Write-Host "[4/4] Steam library..." -ForegroundColor Yellow
$steamRoot = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath

if ($steamRoot) {
    $libs = @($steamRoot)
    $vdf = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        # Pull every "path" value out of the VDF. Crude, but the format is
        # stable enough that a regex is the right amount of machinery here.
        $libs += Select-String -Path $vdf -Pattern '"path"\s+"(.+?)"' -AllMatches |
                 ForEach-Object { $_.Matches } |
                 ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }
    }

    $games = foreach ($lib in ($libs | Sort-Object -Unique)) {
        $apps = Join-Path $lib 'steamapps'
        if (Test-Path $apps) {
            Get-ChildItem "$apps\appmanifest_*.acf" -ErrorAction SilentlyContinue | ForEach-Object {
                $c = Get-Content $_.FullName -Raw
                if ($c -match '"appid"\s+"(\d+)"' ) { $id = $Matches[1] }
                if ($c -match '"name"\s+"(.+?)"') { $nm = $Matches[1] }
                [PSCustomObject]@{ AppID = $id; Name = $nm; Library = $lib }
            }
        }
    }

    $games | Sort-Object Name -Unique |
        Export-Csv -NoTypeInformation -Encoding utf8 "$OutDir\steam-games.csv"
    Write-Host "      $($games.Count) games"

    # ProtonDB URLs, so you can check Linux compatibility in bulk rather than
    # searching each title by hand.
    $games | Sort-Object Name -Unique | ForEach-Object {
        "https://www.protondb.com/app/$($_.AppID)  # $($_.Name)"
    } | Out-File -Encoding utf8 "$OutDir\protondb-links.txt"
} else {
    Write-Host "      Steam not found — skipping" -ForegroundColor DarkGray
}

Write-Host "`nDone. Files in $OutDir" -ForegroundColor Green
Get-ChildItem $OutDir | Select-Object Name, Length | Format-Table -AutoSize
Write-Host @"

Next:
  1. Copy this folder somewhere the NixOS side can read it.
  2. Run scripts/match-nixpkgs.sh against installed-programs.csv to see which
     of these exist in nixpkgs and under what name.
  3. Check protondb-links.txt for which games survive the move.
"@ -ForegroundColor Cyan
