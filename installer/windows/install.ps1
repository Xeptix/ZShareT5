<#
    ZShare -- install, or remove, for every game and every route.

        install.bat                 show what it will do, ask once, copy
        install.bat -Yes            copy without asking
        install.bat -Game t6,t7     only these games, from a download with several
        install.bat -Uninstall      remove what an install put there
        install.bat -Find           show what it detects, change nothing

    One installer for every download: a single game's, or the Treyarch
    Bundle, which carries all five. It maps each folder in the download to
    the place its game reads it from:

        Plutonium\storage\t6   Black Ops II -- the loose scripts and the mod
        Plutonium\storage\t5   Black Ops
        Plutonium\storage\t4   World at War
        Black Ops III          BOIII's and Ezz BOIII's own custom_scripts
        AppData                BOIII per user -- not Ezz BOIII, which clears
                               it every time it launches
        t7x                    T7x, which reads the compiled script
        zshare                 Black Ops 4, as a Shield mod folder

    A download carrying more than one game asks which of them to install,
    offering every one it finds on this machine; -Game answers that without
    asking, and -Yes takes every game found.

    A route installs only when the client it is for is there. Each one names
    an anchor -- a folder that has to exist already -- and the installer
    creates what is missing below it and nothing above it, so it never
    invents a T7x folder for somebody who does not play T7x, or a Black Ops
    folder for somebody who has only ever launched Black Ops II.

    Two routes it leaves alone on purpose. The t7-compiler project lives
    wherever you keep it, so there is nothing to find. And the Steam Workshop
    version of Black Ops III installs through Steam: subscribe to it there.

    Nothing leaves this machine, and uninstalling removes files only --
    never a folder, and never anything ZShare did not put there.
#>

param(
    [switch]$Yes,
    [switch]$Uninstall,
    [switch]$Find,
    [string]$Game = ''
)

$ErrorActionPreference = 'Stop'

function Say($t, $c = 'Gray') { Write-Host "  $t" -ForegroundColor $c }

<#
    Join-Path checks that the drive exists, and throws when it does not --
    which Steam's own library list happily contains, for a drive that has
    since been unplugged. A plain combine never looks.
#>
function Path-Join($a, $b) {
    if (-not $b) { return $a }
    return [System.IO.Path]::Combine($a, $b)
}

function Test-Here($p) {
    if (-not $p) { return $false }
    try { return Test-Path -LiteralPath $p -ErrorAction Stop } catch { return $false }
}

# ------------------------------------------------------------ the download

<#
    The download root is wherever zshare.release is. From a download the
    installer sits two folders down, under installer\windows\; run from the
    source tree it sits beside it. Walk up until it turns up.
#>
function Find-Download {
    $dir = Split-Path -Parent $MyInvocation.ScriptName
    if (-not $dir) { $dir = $PSScriptRoot }
    for ($i = 0; $i -lt 4 -and $dir; $i++) {
        if (Test-Here (Path-Join $dir 'zshare.release')) { return $dir }
        $dir = Split-Path -Parent $dir
    }
    return $null
}

function Read-Release($root) {
    $out = @{}
    foreach ($line in Get-Content -LiteralPath (Path-Join $root 'zshare.release')) {
        if ($line -match '^\s*([a-z]+)\s*=\s*(.*)$') { $out[$Matches[1]] = $Matches[2].Trim() }
    }
    return $out
}

# ------------------------------------------------------------ finding games

<#
    Steam's own list of libraries beats guessing at drive letters: it names
    every library, including one on a drive nobody would look at.
#>
function Steam-Roots {
    $out = @()
    foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $base = $null
        try {
            $v = Get-ItemProperty -Path $k -ErrorAction Stop
            if ($v.SteamPath) { $base = $v.SteamPath -replace '/', '\' }
            elseif ($v.InstallPath) { $base = $v.InstallPath }
        } catch {}
        if (-not $base) { continue }
        $out += $base
        $vdf = Path-Join $base 'steamapps\libraryfolders.vdf'
        if (-not (Test-Here $vdf)) { continue }
        try { $raw = Get-Content -LiteralPath $vdf -Raw -ErrorAction Stop } catch { continue }
        foreach ($m in [regex]::Matches($raw, '"path"\s*"([^"]+)"')) {
            $out += ($m.Groups[1].Value -replace '\\\\', '\')
        }
    }
    return @($out | Select-Object -Unique)
}

<#
    Every folder that could hold a game, whether Steam knows about it or
    not: each Steam library's common folder, and the usual places on every
    fixed drive.
#>
function Candidate-Parents {
    $out = @()
    foreach ($s in (Steam-Roots)) { $out += (Path-Join $s 'steamapps\common') }
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
        foreach ($sub in @('Steam\steamapps\common', 'SteamLibrary\steamapps\common',
                           'Program Files (x86)\Steam\steamapps\common',
                           'Games', 'COD', 'Call of Duty')) {
            $out += (Path-Join $d.RootDirectory.FullName $sub)
        }
    }
    return @($out | Where-Object { Test-Here $_ } | Select-Object -Unique)
}

<#
    The folder a game lives in, found by the executable only it has.

    Several can match, because a player can keep one folder per client --
    "... BOIII", "... T7x" beside the plain one, with their folders
    junctioned back to it. The plainly named one is preferred: it holds the
    real folders, and a per-client copy only ever adds a suffix. The mod
    tools, app 455130, are not a game.
#>
function Find-Game($exe, $like) {
    $hits = @()
    foreach ($parent in (Candidate-Parents)) {
        try {
            $dirs = Get-ChildItem -LiteralPath $parent -Directory -ErrorAction Stop
        } catch { continue }
        foreach ($d in $dirs) {
            if ($d.Name -notlike $like -or $d.Name -like '*455130*') { continue }
            if (Test-Here (Path-Join $d.FullName $exe)) { $hits += $d.FullName }
        }
    }
    $hits = @($hits | Select-Object -Unique | Sort-Object { (Split-Path -Leaf $_).Length }, { $_ })
    if ($hits.Count -gt 0) { return $hits[0] }
    return $null
}

$script:found = @{}

function Root-Of($family) {
    if ($script:found.ContainsKey($family)) { return $script:found[$family] }

    $root = switch ($family) {
        'pluto'   { Path-Join $env:LOCALAPPDATA 'Plutonium' }
        'appdata' { $env:LOCALAPPDATA }
        'bo3'     { Find-Game 'BlackOps3.exe' '*Black Ops III*' }
        'bo4'     { Find-Game 'BlackOps4.exe' '*' }
    }

    if ($root -and -not (Test-Here $root)) { $root = $null }
    $script:found[$family] = $root
    return $root
}

# ------------------------------------------------------------ the games

# Every game, in the order they are offered, with the words a player might
# type for one.
$GAMES = @(
    @{ Key = 't6'; Name = 'Black Ops II';  Also = @('bo2') }
    @{ Key = 't5'; Name = 'Black Ops';     Also = @('bo1', 'bo') }
    @{ Key = 't4'; Name = 'World at War';  Also = @('waw') }
    @{ Key = 't7'; Name = 'Black Ops III'; Also = @('bo3') }
    @{ Key = 't8'; Name = 'Black Ops 4';   Also = @('bo4') }
)

function Game-Name($key) {
    foreach ($g in $GAMES) { if ($g.Key -eq $key) { return $g.Name } }
    return $key
}

function Game-Key($word) {
    $w = $word.Trim().ToLower()
    foreach ($g in $GAMES) {
        if ($g.Key -eq $w -or $g.Also -contains $w) { return $g.Key }
    }
    return $null
}

# ------------------------------------------------------------ the routes

<#
    Each folder in a download, and where it goes.

        Game     which game it belongs to
        Top      the folder in the download
        Family   which root it installs under
        Into     where under that root the folder's contents land
        Anchor   what has to exist already -- below it, missing folders are
                 created; if it is not there, the client is not installed
                 and the route is skipped

    Plutonium makes a game's storage folder the first time that game is
    launched, which is what makes it the anchor for each of the three.
#>
$ROUTES = @(
    @{ Game = 't6'; Top = 'Plutonium\storage\t6'; Family = 'pluto';   Into = 'storage\t6';
       Anchor = 'storage\t6';       Label = 'Black Ops II' }
    @{ Game = 't5'; Top = 'Plutonium\storage\t5'; Family = 'pluto';   Into = 'storage\t5';
       Anchor = 'storage\t5';       Label = 'Black Ops' }
    @{ Game = 't4'; Top = 'Plutonium\storage\t4'; Family = 'pluto';   Into = 'storage\t4';
       Anchor = 'storage\t4';       Label = 'World at War' }
    @{ Game = 't7'; Top = 'Black Ops III';        Family = 'bo3';     Into = '';
       Anchor = 'boiii';            Label = 'Black Ops III -- BOIII / Ezz BOIII' }
    @{ Game = 't7'; Top = 'AppData';              Family = 'appdata'; Into = '';
       Anchor = 'boiii\data';       Label = 'Black Ops III -- BOIII per user' }
    @{ Game = 't7'; Top = 't7x';                  Family = 'bo3';     Into = 't7x';
       Anchor = 't7x';              Label = 'Black Ops III -- T7x' }
    @{ Game = 't8'; Top = 'zshare';               Family = 'bo4';     Into = 'project-bo4\mods\zshare';
       Anchor = 'project-bo4\mods'; Label = 'Black Ops 4 -- Shield' }
)

<#
    Every file this download would put somewhere, and whether its route's
    client is installed. A route whose anchor is missing is kept in the
    plan, marked, so -Find and the prompt can say why it was skipped.
#>
function Build-Plan($download) {
    $plan = @()
    foreach ($r in $ROUTES) {
        $src = Path-Join $download $r.Top
        if (-not (Test-Here $src)) { continue }

        $root = Root-Of $r.Family
        $ready = $false
        $dest = $null

        if ($root) {
            $anchor = if ($r.Anchor) { Path-Join $root $r.Anchor } else { $root }
            $ready = Test-Here $anchor
            $dest = if ($r.Into) { Path-Join $root $r.Into } else { $root }
        }

        foreach ($f in Get-ChildItem -LiteralPath $src -Recurse -File) {
            $rel = $f.FullName.Substring($src.Length).TrimStart('\')

            # Never the installer itself, wherever a download keeps it.
            if ($rel -match '(^|\\)installer(\\|$)') { continue }
            $plan += [pscustomobject]@{
                Game  = $r.Game
                Label = $r.Label
                From  = $f.FullName
                To    = if ($dest) { Path-Join $dest $rel } else { $null }
                Ready = $ready
            }
        }
    }
    return $plan
}

# ------------------------------------------------------------ asking

<#
    One line from the player, or $null when there is nobody to answer --
    no console, or -NonInteractive. Every question goes through here, so
    none of them can hang or guess.
#>
function Ask-Line($prompt) {
    try {
        return Read-Host "  $prompt"
    } catch {
        return $null
    }
}

function Confirm($question, $flag) {
    if ($Yes) { return $true }
    $a = Ask-Line "$question [y/N]"
    if ($null -eq $a) {
        Write-Host ''
        Say "Nothing to answer with. Run it again with $flag." Yellow
        return $false
    }
    return $a -match '^\s*y'
}

<#
    Which games to act on, out of the ones this download carries.

    A download with one game has nothing to choose. With several, -Game
    names them, -Yes and -Find take every one, and otherwise the player
    picks from a numbered list -- Enter for every game found here.
#>
function Pick-Games($present, $plan) {
    if ($Game) {
        $want = @()
        foreach ($w in ($Game -split '[,\s]+' | Where-Object { $_ })) {
            $k = Game-Key $w
            if (-not $k -or $present -notcontains $k) {
                Write-Host ''
                Say ("'{0}' is not a game in this download. It carries: {1}." -f $w,
                     (($present | ForEach-Object { "$_ ($(Game-Name $_))" }) -join ', ')) Red
                exit 1
            }
            $want += $k
        }
        return @($present | Where-Object { $want -contains $_ })
    }

    if ($present.Count -le 1) { return @($present) }

    $here = @($present | Where-Object { $g = $_; @($plan | Where-Object { $_.Game -eq $g -and $_.Ready }).Count -gt 0 })
    if ($Find) { return @($present) }
    if ($Yes) { return $here }

    Write-Host ''
    Say 'This download carries more than one game. Which do you want?'
    Write-Host ''
    for ($i = 0; $i -lt $present.Count; $i++) {
        $k = $present[$i]
        Write-Host ("    {0}. {1,-16}" -f ($i + 1), (Game-Name $k)) -NoNewline
        if ($here -contains $k) { Write-Host 'found' -ForegroundColor Green }
        else { Write-Host 'not found on this machine' -ForegroundColor DarkYellow }
    }

    for (;;) {
        Write-Host ''
        $a = Ask-Line 'Numbers, like 1 4 -- or Enter for every game found'
        if ($null -eq $a) {
            Write-Host ''
            Say 'Nothing to answer with. Run it again with -Game t6,t7 or with -Yes.' Yellow
            exit 0
        }
        if (-not $a.Trim()) { return $here }

        $want = @()
        $bad = @()
        foreach ($w in ($a -split '[,\s]+' | Where-Object { $_ })) {
            $n = 0
            if ([int]::TryParse($w, [ref]$n) -and $n -ge 1 -and $n -le $present.Count) {
                $want += $present[$n - 1]
            } elseif ((Game-Key $w) -and $present -contains (Game-Key $w)) {
                $want += (Game-Key $w)
            } else {
                $bad += $w
            }
        }
        if ($bad.Count -eq 0 -and $want.Count -gt 0) {
            return @($present | Where-Object { $want -contains $_ })
        }
        Say ("Not in the list: {0}" -f ($bad -join ' ')) Red
    }
}

# ------------------------------------------------------------ main

Write-Host ''
Write-Host '  ZShare' -ForegroundColor Cyan
Write-Host '  ------' -ForegroundColor DarkCyan

$download = Find-Download
if (-not $download) {
    Write-Host ''
    Say 'This is not a ZShare download: there is no zshare.release beside it.' Red
    Say 'Extract the whole download and run the installer from inside it.' Red
    exit 1
}

$release = Read-Release $download
Say ("{0} v{1}" -f $release['name'], $release['version']) DarkGray

$all = @(Build-Plan $download)

if ($all.Count -eq 0) {
    Write-Host ''
    Say 'This download has nothing an installer can place.' Yellow
    exit 1
}

$present = @($GAMES | ForEach-Object { $_.Key } | Where-Object { $k = $_; @($all | Where-Object { $_.Game -eq $k }).Count -gt 0 })
$picked = @(Pick-Games $present $all)
$plan = @($all | Where-Object { $picked -contains $_.Game })

Write-Host ''
foreach ($group in ($plan | Group-Object Label)) {
    $first = $group.Group[0]
    if ($first.Ready) {
        Write-Host ("    {0}" -f $group.Name) -ForegroundColor Green
        foreach ($p in $group.Group) { Write-Host ("      {0}" -f $p.To) }
    } else {
        Write-Host ("    {0}" -f $group.Name) -NoNewline
        Write-Host '   not installed here -- skipped' -ForegroundColor DarkYellow
    }
}

if ($picked -contains 't7') {
    Write-Host ''
    Say 'The Steam Workshop version installs through Steam -- subscribe to it there.' DarkGray
}

$ready = @($plan | Where-Object { $_.Ready })

if ($Find) {
    Write-Host ''
    Say ("{0} file(s) would be {1}." -f $ready.Count, $(if ($Uninstall) { 'removed' } else { 'written' })) DarkGray
    exit 0
}

if ($ready.Count -eq 0) {
    Write-Host ''
    Say 'None of the games picked were found on this machine.' Red
    Say 'Run the game once so it creates its folders, then run this again.' Red
    exit 1
}

# ---- remove
if ($Uninstall) {
    $here = @($ready | Where-Object { Test-Here $_.To })
    Write-Host ''
    if ($here.Count -eq 0) {
        Say 'ZShare is not installed in any of those places.' DarkGray
        exit 0
    }
    Say ("{0} file(s) will be removed. Folders are left alone." -f $here.Count) DarkGray
    if (-not (Confirm 'remove?' '-Uninstall -Yes')) { Say 'Cancelled.' Red; exit 0 }

    $n = 0
    foreach ($p in $here) {
        try {
            Remove-Item -LiteralPath $p.To -Force -ErrorAction Stop
            $n++
        } catch {
            Say ("could not remove {0}: {1}" -f $p.To, $_.Exception.Message) Red
        }
    }
    Write-Host ''
    Say "$n removed." Green
    exit 0
}

# ---- install
Write-Host ''
Say 'Only ZShare''s own files are written. Nothing is deleted.' DarkGray
if (-not (Confirm 'install?' '-Yes')) { Say 'Cancelled.' Red; exit 0 }

$n = 0
$failed = 0
foreach ($p in $ready) {
    try {
        $dir = Split-Path -Parent $p.To
        if (-not (Test-Here $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $p.From -Destination $p.To -Force -ErrorAction Stop
        $n++
    } catch {
        Say ("could not write {0}: {1}" -f $p.To, $_.Exception.Message) Red
        $failed++
    }
}

Write-Host ''
if ($failed -gt 0) {
    Say "$n installed, $failed failed. Is the game running?" Yellow
    exit 1
}
Say "$n installed." Green
Say 'End the current match and start a new one -- no game restart needed.' DarkGray
Write-Host ''
exit 0
