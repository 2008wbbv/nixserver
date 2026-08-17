<#
.SYNOPSIS
    Find what's eating your disks, so you can decide what to delete.

.DESCRIPTION
    Three reports:

      1. Steam games, sorted by size, with last-played dates and a running
         cumulative total. The cumulative column is the useful one — read down
         until it passes your target and stop.
      2. Xbox / Game Pass installs, which hide in a protected folder that
         Explorer won't show you honestly.
      3. Biggest directories overall, for everything that isn't a game.

    Nothing is deleted. This only reports.

.EXAMPLE
    .\disk-report.ps1
    .\disk-report.ps1 -TargetGB 600
#>

param(
    [int]$TargetGB = 600,
    [string]$OutDir = "$env:USERPROFILE\Desktop\windows-programs"
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Format-GB($bytes) { "{0,8:N1} GB" -f ($bytes / 1GB) }

Write-Host "`n=== Free space now ===" -ForegroundColor Cyan
Get-PSDrive -PSProvider FileSystem |
    Where-Object { $_.Used -ne $null } |
    Select-Object Name,
        @{n = 'Used(GB)'; e = { [math]::Round($_.Used / 1GB, 1) } },
        @{n = 'Free(GB)'; e = { [math]::Round($_.Free / 1GB, 1) } } |
    Format-Table -AutoSize

Write-Host "Target to free: $TargetGB GB`n" -ForegroundColor Yellow

# --- 1. Steam ---------------------------------------------------------------
Write-Host "=== Steam games, biggest first ===" -ForegroundColor Cyan

$steamRoot = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
$games = @()

if ($steamRoot) {
    $libs = @($steamRoot)
    $vdf = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        $libs += Select-String -Path $vdf -Pattern '"path"\s+"(.+?)"' -AllMatches |
                 ForEach-Object { $_.Matches } |
                 ForEach-Object { $_.Groups[1].Value -replace '\\\\', '\' }
    }

    foreach ($lib in ($libs | Sort-Object -Unique)) {
        $apps = Join-Path $lib 'steamapps'
        if (-not (Test-Path $apps)) { continue }

        Get-ChildItem "$apps\appmanifest_*.acf" -ErrorAction SilentlyContinue | ForEach-Object {
            $c = Get-Content $_.FullName -Raw
            $id = if ($c -match '"appid"\s+"(\d+)"') { $Matches[1] } else { $null }
            $nm = if ($c -match '"name"\s+"(.+?)"') { $Matches[1] } else { 'unknown' }
            $sz = if ($c -match '"SizeOnDisk"\s+"(\d+)"') { [long]$Matches[1] } else { 0 }
            $lp = if ($c -match '"LastPlayed"\s+"(\d+)"') { [long]$Matches[1] } else { 0 }

            $games += [PSCustomObject]@{
                Name       = $nm
                AppID      = $id
                Bytes      = $sz
                LastPlayed = if ($lp -gt 0) {
                                 [DateTimeOffset]::FromUnixTimeSeconds($lp).LocalDateTime
                             } else { $null }
            }
        }
    }
}

if ($games.Count) {
    $running = 0
    $rows = $games | Sort-Object Bytes -Descending | ForEach-Object {
        $running += $_.Bytes
        $days = if ($_.LastPlayed) {
                    [int]((Get-Date) - $_.LastPlayed).TotalDays
                } else { $null }

        [PSCustomObject]@{
            Size        = Format-GB $_.Bytes
            Cumulative  = Format-GB $running
            LastPlayed  = if ($_.LastPlayed) { $_.LastPlayed.ToString('yyyy-MM-dd') } else { 'never' }
            DaysAgo     = if ($null -ne $days) { $days } else { '-' }
            Name        = $_.Name
        }
    }

    $rows | Format-Table -AutoSize
    $rows | Export-Csv -NoTypeInformation -Encoding utf8 "$OutDir\steam-sizes.csv"

    $total = ($games | Measure-Object Bytes -Sum).Sum
    Write-Host ("Steam total: {0}" -f (Format-GB $total)) -ForegroundColor Green

    # The easy call: anything untouched in a year.
    $stale = $games | Where-Object {
        $_.LastPlayed -and ((Get-Date) - $_.LastPlayed).TotalDays -gt 365
    }
    $staleBytes = ($stale | Measure-Object Bytes -Sum).Sum
    Write-Host ("Not played in over a year: {0} games, {1}" -f $stale.Count, (Format-GB $staleBytes)) -ForegroundColor Yellow

    $never = $games | Where-Object { -not $_.LastPlayed }
    if ($never.Count) {
        $neverBytes = ($never | Measure-Object Bytes -Sum).Sum
        Write-Host ("Installed but never played: {0} games, {1}" -f $never.Count, (Format-GB $neverBytes)) -ForegroundColor Yellow
    }
    Write-Host ""
} else {
    Write-Host "  no Steam libraries found`n" -ForegroundColor DarkGray
}

# --- 2. Xbox / Game Pass ----------------------------------------------------
# These install to a hidden, ACL-protected folder per drive. Explorer lies
# about the size, so measure it directly.
Write-Host "=== Xbox / Game Pass installs ===" -ForegroundColor Cyan
$found = $false
foreach ($d in (Get-PSDrive -PSProvider FileSystem).Name) {
    foreach ($p in @("${d}:\XboxGames", "${d}:\WpSystem", "${d}:\Program Files\WindowsApps")) {
        if (Test-Path $p) {
            $found = $true
            $sz = (Get-ChildItem $p -Recurse -Force -File -ErrorAction SilentlyContinue |
                   Measure-Object Length -Sum).Sum
            Write-Host ("  {0,-45} {1}" -f $p, (Format-GB $sz))

            # Per-title breakdown where the layout allows it.
            if ($p -like '*XboxGames') {
                Get-ChildItem $p -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $g = (Get-ChildItem $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
                          Measure-Object Length -Sum).Sum
                    Write-Host ("      {0,-41} {1}" -f $_.Name, (Format-GB $g)) -ForegroundColor DarkGray
                }
            }
        }
    }
}
if (-not $found) { Write-Host "  none found" -ForegroundColor DarkGray }
Write-Host ""

# --- 3. Everything else -----------------------------------------------------
Write-Host "=== Biggest top-level directories ===" -ForegroundColor Cyan
foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used }).Name) {
    Write-Host "`n  ${d}:\" -ForegroundColor White
    Get-ChildItem "${d}:\" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $sz = (Get-ChildItem $_.FullName -Recurse -Force -File -ErrorAction SilentlyContinue |
               Measure-Object Length -Sum).Sum
        [PSCustomObject]@{ Dir = $_.Name; Bytes = $sz }
    } | Sort-Object Bytes -Descending | Select-Object -First 12 | ForEach-Object {
        Write-Host ("    {0,-40} {1}" -f $_.Dir, (Format-GB $_.Bytes))
    }
}

Write-Host @"

=== What to do with this ===

Read the Steam table top-down and stop when Cumulative passes $TargetGB GB.
Uninstall from Steam itself (Library > right-click > Manage > Uninstall) so it
cleans up properly — deleting the folder leaves the manifest behind and Steam
gets confused.

Nothing here is permanent. Steam re-downloads on demand, and your saves are in
Steam Cloud for most titles — check the cloud icon in the Library view before
removing anything with a lot of progress in it.

Report saved to $OutDir\steam-sizes.csv
"@ -ForegroundColor Cyan
