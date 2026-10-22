param(
    [switch]$Publish,
    [string]$Version,
    [string]$Repository,
    [string]$PreviousManifest,
    [switch]$ReuseWorldDump,
    [string]$NotesFile
)
. "$PSScriptRoot\common.ps1"
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$releaseConfig = Get-Content (Join-Path $ConfigDir 'release.json') -Raw | ConvertFrom-Json
$repository = if ($Repository) { $Repository } else { $releaseConfig.repository }
$testChannel = $repository -ne $releaseConfig.repository
if ($Publish -and $Version -and -not $testChannel) { throw 'A -Version test release only goes to a test repository (-Repository): change VERSION and CHANGELOG.md for a real one.' }
$version = if ($Version) { $Version } else { (Get-Content (Join-Path $RepoRoot 'VERSION') -Raw).Trim() }
$tag = "v$version"
$packageTag = "packages-$tag"
$releaseRoot = Join-Path $RepoRoot 'release'
$buildDir = Join-Path $releaseRoot 'build'
$cacheDir = Join-Path $releaseRoot 'cache'
$outDir = Join-Path $releaseRoot $version
$assetsDir = Join-Path $outDir 'assets'
$serverSource = Join-Path $releaseRoot 'src\core'
$serverBuild = Join-Path $buildDir 'server'
$serverInstall = Join-Path $buildDir 'server-install'
$runtimeDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
$fixedZipTime = [DateTimeOffset]::new(2000, 1, 1, 0, 0, 0, [TimeSpan]::Zero)

function Get-Sha256([string]$Path) { (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

function Get-TextSha256([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function Get-ReleaseNotes {
    $sections = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($line in Get-Content (Join-Path $RepoRoot 'CHANGELOG.md') -Encoding UTF8) {
        if ($line -match '^## (\S+)') {
            $current = [ordered]@{ version = $Matches[1]; notes = [System.Collections.Generic.List[string]]::new() }
            $sections.Add($current)
        } elseif ($current) {
            $current.notes.Add($line)
        }
    }
    foreach ($section in $sections) { $section.notes = ($section.notes -join "`n").Trim() }
    $sections
}

function Get-StagedTestNotes([string]$Version) {
    $file = Join-Path $RepoRoot "release\$Version\notes.md"
    if (-not (Test-Path $file)) { return $null }
    $text = [System.IO.File]::ReadAllText($file).Replace("`r`n", "`n")
    $footer = $text.IndexOf("`n---`n")
    if ($footer -ge 0) { $text = $text.Substring(0, $footer) }
    $text.Trim()
}

function Add-EarlierTestNotes($Notes, $Previous) {
    $byVersion = [ordered]@{}
    foreach ($section in $Notes) { $byVersion[$section.version] = $section }
    if ($Previous -and $Previous.releaseNotes) {
        foreach ($section in $Previous.releaseNotes) {
            if (-not $byVersion.Contains($section.version)) { $byVersion[$section.version] = [ordered]@{ version = $section.version; notes = $section.notes } }
        }
    }
    foreach ($folder in Get-ChildItem (Join-Path $RepoRoot 'release') -Directory -ErrorAction SilentlyContinue) {
        if ($folder.Name -notmatch '^\d+\.\d+\.\d+$' -or $byVersion.Contains($folder.Name)) { continue }
        $staged = Get-StagedTestNotes $folder.Name
        if ($staged) { $byVersion[$folder.Name] = [ordered]@{ version = $folder.Name; notes = $staged } }
    }
    $byVersion.Values | Sort-Object { [version]$_.version } -Descending
}

function Get-DiscordWebhook {
    if ($env:HOA_DISCORD_WEBHOOK) { return $env:HOA_DISCORD_WEBHOOK.Trim() }
    $file = Join-Path $env:LOCALAPPDATA 'HordesOfAzeroth\discord-webhook.txt'
    if (Test-Path $file) { return (Get-Content $file -Raw).Trim() }
    return $null
}

function ConvertTo-DiscordNotes([string]$Notes, [string]$ReleaseUrl) {
    $lines = $Notes -split "`r?`n" | ForEach-Object { if ($_ -match '^####\s+(.+)$') { "**$($Matches[1].Trim())**" } else { $_ } }
    $text = ($lines -join "`n").Trim()
    $more = "`n`n[Full patch notes and download]($ReleaseUrl)"
    $limit = 4000 - $more.Length
    if ($text.Length -gt $limit) {
        $cut = $text.LastIndexOf("`n", $limit)
        if ($cut -lt 1) { $cut = $limit }
        $text = $text.Substring(0, $cut) + "`n…"
    }
    $text + $more
}

function Send-DiscordAnnouncement([string]$Title, [string]$Notes, [string]$ReleaseUrl) {
    $webhook = Get-DiscordWebhook
    if (-not $webhook) {
        Write-Host 'No Discord webhook set up; skipping the #announcements post.'
        return
    }
    $payload = @{
        username = $releaseConfig.productName
        allowed_mentions = @{ parse = @() }
        embeds = @(@{
            title = $Title
            url = $ReleaseUrl
            description = ConvertTo-DiscordNotes $Notes $ReleaseUrl
            color = 0xB3261E
            footer = @{ text = 'Start the launcher and press Update. Your characters are backed up first.' }
        })
    }
    $body = [System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 6))
    try {
        Invoke-RestMethod -Method Post -Uri $webhook -ContentType 'application/json; charset=utf-8' -Body $body | Out-Null
        Write-Host 'Posted the patch notes to Discord.'
    } catch {
        Write-Warning "The release is published, but the Discord post failed: $($_.Exception.Message)"
    }
}

function Get-CMake {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'Visual Studio 2022 Build Tools with the C++ workload are needed (see README).' }
    $instance = & $vswhere -all -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath |
        Where-Object { Test-Path (Join-Path $_ 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe') } |
        Select-Object -First 1
    if (-not $instance) { throw 'Visual Studio 2022 Build Tools with the C++ workload are needed (see README).' }
    $generator = if ($instance -match '\\18\\') { 'Visual Studio 18 2026' } else { 'Visual Studio 17 2022' }
    [pscustomobject]@{ Exe = Join-Path $instance 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'; Instance = $instance; Generator = $generator }
}

function Invoke-Native([string]$What, [string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } | Select-String -Pattern ' error |error [A-Z]+[0-9]+|fatal' | Select-Object -First 20 | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE." }
}

function Invoke-Quiet([string]$What, [string]$Exe, [string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    & $Exe @Arguments 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE." }
}

function Copy-Runtime([string]$Instance, [string[]]$Targets) {
    $redist = Get-ChildItem (Join-Path $Instance 'VC\Redist\MSVC') -Directory | Sort-Object Name -Descending |
        ForEach-Object { Get-ChildItem (Join-Path $_.FullName 'x64\Microsoft.VC*.CRT') -Directory } | Select-Object -First 1
    if (-not $redist) { throw 'The Visual C++ redistributable files were not found in the Build Tools.' }
    foreach ($target in $Targets) {
        foreach ($dll in $runtimeDlls) { Copy-Item (Join-Path $redist.FullName $dll) $target -Force }
    }
}

function Invoke-ServerBuild {
    $commit = (git -C $RepoRoot rev-parse HEAD:server/core).Trim()
    $stamp = Join-Path $serverInstall 'commit.txt'
    if ((Test-Path $stamp) -and (Get-Content $stamp -Raw).Trim() -eq $commit) { return }

    $fork = Join-Path $ServerDir 'core'
    if (-not (Test-Path (Join-Path $serverSource '.git'))) {
        Invoke-Quiet 'git worktree add' 'git' @('-C', $fork, 'worktree', 'add', '--detach', $serverSource, $commit)
    } else {
        Invoke-Quiet 'git checkout' 'git' @('-C', $serverSource, 'checkout', '--quiet', '--force', '--detach', $commit)
    }

    Write-Host "Building the server from fork commit $($commit.Substring(0, 9)) (portable, not tuned to this CPU)..."
    $cmake = Get-CMake
    Invoke-Native 'CMake configure' $cmake.Exe @(
        '-S', $serverSource, '-B', $serverBuild, '-G', $cmake.Generator, '-A', 'x64',
        "-DCMAKE_GENERATOR_INSTANCE=$($cmake.Instance)",
        '-DBUILD_EXTRACTORS=1', '-DBUILD_FOR_HOST_CPU=OFF', "-DCMAKE_INSTALL_PREFIX=$serverInstall"
    )
    Invoke-Native 'Server build' $cmake.Exe @('--build', $serverBuild, '--config', 'Release', '--', '/m', '/v:minimal')
    if (Test-Path $serverInstall) { Remove-Item $serverInstall -Recurse -Force }
    Invoke-Native 'Server install' $cmake.Exe @('--install', $serverBuild, '--config', 'Release')
    Copy-Runtime $cmake.Instance @($serverInstall, (Join-Path $serverInstall 'Extractors'))
    [System.IO.File]::WriteAllText($stamp, $commit)
}

function Invoke-PackageBuild([string]$Name) {
    New-Item -ItemType Directory -Force $buildDir | Out-Null
    switch ($Name) {
        'telegraphkit' {
            $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
            $sources = Get-ChildItem (Join-Path (Get-CommittedTree) 'tools\telegraphs') -Filter '*.cs' | ForEach-Object FullName
            & $csc -nologo -optimize '-r:System.Drawing.dll' "-out:$(Join-Path $buildDir 'TelegraphKit.exe')" @sources | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'TelegraphKit did not compile.' }
        }
        'server' { Invoke-ServerBuild }
        'coop' {
            $source = Join-Path (Get-CommittedTree) 'tools\coop\Cargo.toml'
            Invoke-Native 'Co-op build' 'cargo' @('build', '--locked', '--release', '--manifest-path', $source)
            $coopOut = Join-Path $buildDir 'coop'
            New-Item -ItemType Directory -Force $coopOut | Out-Null
            Copy-Item (Join-Path (Split-Path $source) 'target\release\hoa-coop.exe') $coopOut
            Copy-Runtime (Get-CMake).Instance @($coopOut)
        }
        'version' { [System.IO.File]::WriteAllText((Join-Path $buildDir 'VERSION'), "$version`n") }
        'launcher' {
            $project = Join-Path (Get-CommittedTree) 'tools\launcher\HordesOfAzerothLauncher.csproj'
            Invoke-Native 'Launcher build' 'dotnet' @('build', $project, '-c', 'Release', '-nologo', "-p:Repository=$repository", "-p:OutputPath=$(Join-Path $buildDir 'launcher')/")
        }
        'world-dump' {
            $dump = Join-Path $buildDir 'world.sql'
            if ($ReuseWorldDump -and (Test-Path $dump)) { return }
            if (-not (Test-DbUp)) { throw 'MariaDB is not running. Start it with tools\start-server.ps1 -DatabaseOnly.' }
            & (Join-Path $MariaDir 'bin\mariadb-dump.exe') @DbRootArgs --skip-dump-date --order-by-primary --single-transaction --ignore-table-data=mangos.variables "--result-file=$dump" mangos
            if ($LASTEXITCODE -ne 0) { throw 'mariadb-dump of the world database failed.' }
        }
        default { throw "Unknown build step $Name." }
    }
}

function Assert-WorldDumpMatchesServer {
    $dump = Join-Path $buildDir 'world.sql'
    $migrations = Join-Path $serverSource 'sql\migrations'
    if (-not (Test-Path $dump) -or -not (Test-Path $migrations)) { return }
    $needed = Get-ChildItem $migrations -Filter '*_world.sql' | ForEach-Object { $_.BaseName.Substring(0, 14) }
    $text = [System.IO.File]::ReadAllText($dump)
    $start = $text.IndexOf('INSERT INTO `migrations` VALUES')
    if ($start -lt 0) { throw 'The world dump has no migrations table rows.' }
    $end = $text.IndexOf(";`n", $start)
    $rows = $text.Substring($start, $end - $start)
    $missing = @($needed | Where-Object { -not $rows.Contains("'$_'") })
    if ($missing.Count -gt 0) {
        throw "The world dump is missing $($missing.Count) migration(s) of the server it ships with (first: $($missing[0])). Apply them with tools\apply-migrations.ps1 and run the release again without -ReuseWorldDump."
    }
}

function Get-CommittedTree {
    $tree = Join-Path $buildDir 'head'
    if (-not $script:committedTreeReady) {
        if (Test-Path $tree) { Remove-Item $tree -Recurse -Force }
        $archive = Join-Path $buildDir 'head.zip'
        Invoke-Quiet 'git archive' 'git' @('-C', $RepoRoot, 'archive', '--format=zip', '-o', $archive, 'HEAD')
        [System.IO.Compression.ZipFile]::ExtractToDirectory($archive, $tree)
        Remove-Item $archive
        $script:committedTreeReady = $true
    }
    $tree
}

function Get-CommittedCopy([string]$Relative, [string]$WorkingCopy) {
    $path = $Relative -replace '\\', '/'
    $committed = git -C $RepoRoot ls-tree --name-only HEAD -- $path
    if (-not $committed) { return $WorkingCopy }
    Join-Path (Get-CommittedTree) $path
}

function Resolve-PackageFiles($Package) {
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($path in @($Package.git)) {
        if (-not $path) { continue }
        $tree = Get-CommittedTree
        foreach ($tracked in git -C $RepoRoot ls-tree -r --name-only HEAD -- $path) {
            $source = Join-Path $tree $tracked
            if (Test-Path $source -PathType Leaf) { $files.Add([pscustomobject]@{ Source = $source; Target = $tracked }) }
        }
    }
    foreach ($entry in @($Package.files)) {
        if (-not $entry) { continue }
        $pattern = Join-Path $RepoRoot $entry.from
        if ($entry.from -match '[*?]') {
            $matched = @(Get-ChildItem $pattern -File | Sort-Object Name)
            if (-not $matched) { return $null }
            $folder = if ($entry.to) { $entry.to } else { Split-Path $entry.from }
            foreach ($file in $matched) {
                $relative = $file.FullName.Substring($RepoRoot.TrimEnd('\').Length + 1)
                $files.Add([pscustomobject]@{ Source = (Get-CommittedCopy $relative $file.FullName); Target = "$folder/$($file.Name)" })
            }
        } else {
            if (-not (Test-Path $pattern -PathType Leaf)) { return $null }
            $target = if ($entry.to) { $entry.to } else { $entry.from }
            $files.Add([pscustomobject]@{ Source = (Get-CommittedCopy $entry.from $pattern); Target = $target })
        }
    }
    foreach ($file in $files) { $file.Target = $file.Target -replace '\\', '/' }
    $files
}

function New-PackageZip([string]$Name, $Files) {
    $zipPath = Join-Path $assetsDir "$Name.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $Files | Sort-Object Target) {
            $entry = $zip.CreateEntry($file.Target, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $fixedZipTime
            $writer = $entry.Open()
            $reader = [System.IO.File]::OpenRead($file.Source)
            try { $reader.CopyTo($writer) } finally { $reader.Dispose(); $writer.Dispose() }
        }
    } finally {
        $zip.Dispose()
    }
    Get-Item $zipPath
}

function Get-PreviousManifest {
    if ($PreviousManifest) { return Get-Content $PreviousManifest -Raw | ConvertFrom-Json }
    $previousDir = Join-Path $releaseRoot 'previous'
    New-Item -ItemType Directory -Force $previousDir | Out-Null
    $target = Join-Path $previousDir 'manifest.json'
    if (Test-Path $target) { Remove-Item $target -Force }
    $ErrorActionPreference = 'Continue'
    gh release download --repo $repository --pattern manifest.json --dir $previousDir 2>$null | Out-Null
    $ErrorActionPreference = 'Stop'
    if (Test-Path $target) { return Get-Content $target -Raw | ConvertFrom-Json }
    $null
}

function Get-ThirdPartyEntry($Item) {
    $file = $null
    if ($Item.localCopy) {
        $local = Join-Path $RepoRoot $Item.localCopy
        if (Test-Path $local) { $file = $local }
    }
    if (-not $file) {
        New-Item -ItemType Directory -Force $cacheDir | Out-Null
        $file = Join-Path $cacheDir ([System.IO.Path]::GetFileName(([Uri]$Item.url).AbsolutePath))
        if (-not (Test-Path $file)) { Invoke-WebRequest $Item.url -OutFile $file -UseBasicParsing }
    }
    [ordered]@{
        name = $Item.name
        version = $Item.version
        licence = $Item.licence
        url = $Item.url
        size = (Get-Item $file).Length
        sha256 = Get-Sha256 $file
        install = $Item.install
    }
}

function Get-NavGroupFiles($Group) {
    $mmaps = Join-Path $DataDir 'mmaps'
    foreach ($map in $Group.maps.PSObject.Properties) {
        $id = '{0:D3}' -f [int]$map.Name
        $header = Join-Path $mmaps "$id.mmap"
        if (Test-Path $header) { [pscustomobject]@{ Source = $header; Target = "$id.mmap" } }
        $tiles = if ($map.Value -eq 'all') {
            Get-ChildItem $mmaps -Filter "$id*.mmtile"
        } else {
            foreach ($tile in $map.Value) {
                $xy = $tile -split ','
                $path = Join-Path $mmaps ('{0}{1:D2}{2:D2}.mmtile' -f $id, [int]$xy[1], [int]$xy[0])
                if (Test-Path $path) { Get-Item $path }
            }
        }
        foreach ($tile in $tiles) { [pscustomobject]@{ Source = $tile.FullName; Target = $tile.Name } }
    }
}

function Get-NavFilesProblem($Group, $Files) {
    $headers = @($Files | Where-Object { $_.Target -like '*.mmap' }).Count
    if ($headers -lt @($Group.maps.PSObject.Properties).Count) { return "they aren't built in $(Join-Path $DataDir 'mmaps')" }
    $commit = (git -C $RepoRoot rev-parse HEAD:server/core).Trim()
    $generatorChanged = [DateTimeOffset]::Parse((git -C (Join-Path $ServerDir 'core') log -1 --format=%cI $commit -- contrib/mmap contrib/vmap_extractor contrib/vmap_assembler contrib/extractor).Trim())
    $stale = @($Files | Where-Object { (Get-Item $_.Source).LastWriteTimeUtc -lt $generatorChanged.UtcDateTime })
    if ($stale.Count) { return "$($stale.Count) files are older than the last map generator change in server/core ($($generatorChanged.ToString('yyyy-MM-dd')))" }
}

function Get-NavGroups($Previous) {
    $previousDownloads = @{}
    if ($Previous -and $Previous.navTiles) { foreach ($group in $Previous.navTiles) { if ($group.download) { $previousDownloads[$group.name] = $group.download } } }
    foreach ($group in (Get-Content (Join-Path $ConfigDir 'navtiles.json') -Raw | ConvertFrom-Json).groups) {
        $files = @(Get-NavGroupFiles $group)
        $problem = Get-NavFilesProblem $group $files
        if ($problem) {
            Write-Warning "Monster paths, $($group.name): $problem. The release has no download for them, so the launcher builds them on the player's processor. Build every tile with tools\extract-client-data.ps1 -MmapsOnly -AllTiles to ship them."
            [ordered]@{ name = $group.name; maps = $group.maps }
            continue
        }
        $contentHash = Get-TextSha256 (($files | Sort-Object Target | ForEach-Object { "$($_.Target):$(Get-Sha256 $_.Source)" }) -join "`n")
        $old = $previousDownloads[$group.name]
        $download = if ($old -and $old.contentHash -eq $contentHash) {
            Write-Host "monster paths, $($group.name): unchanged since $($old.release)"
            $old
        } else {
            $slug = ($group.name.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
            $zip = New-PackageZip "navmesh-$slug" $files
            $uploads.Add($zip.FullName)
            Write-Host ('monster paths, {0}: {1} files, {2:N1} MB zipped' -f $group.name, $files.Count, ($zip.Length / 1MB))
            [ordered]@{ release = $tag; url = "$baseUrl/$($zip.Name)"; size = $zip.Length; sha256 = Get-Sha256 $zip.FullName; contentHash = $contentHash }
        }
        [ordered]@{ name = $group.name; maps = $group.maps; download = $download }
    }
}

if (-not (Test-DbUp)) { throw 'MariaDB is not running. Start it with tools\start-server.ps1 -DatabaseOnly.' }
& (Join-Path $PSScriptRoot 'build-navtiles.ps1') | Out-Null
if (git -C $RepoRoot status --porcelain -- config/navtiles.json) { throw 'config/navtiles.json did not match the run zones and has been rebuilt: commit it, then release again.' }

if ($Publish -and -not $testChannel -and (git -C $RepoRoot status --porcelain)) { throw 'Commit or stash every change before publishing: the release is built from the working tree.' }

if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force $assetsDir | Out-Null

$previous = Get-PreviousManifest
$previousPackages = @{}
if ($previous) { foreach ($package in $previous.packages) { $previousPackages[$package.name] = $package } }
$baseUrl = "https://github.com/$repository/releases/download/$packageTag"

$packages = [System.Collections.Generic.List[object]]::new()
$uploads = [System.Collections.Generic.List[string]]::new()
$releaseUploads = [System.Collections.Generic.List[string]]::new()
foreach ($package in $releaseConfig.packages) {
    if ($package.build) { Invoke-PackageBuild $package.build }
    $files = Resolve-PackageFiles $package
    if ($null -eq $files) {
        if ($package.optional) { Write-Host "$($package.name): skipped (not built yet)"; continue }
        throw "Package $($package.name) is missing files: build them first."
    }
    $listed = @($files | Sort-Object Target | ForEach-Object {
        [ordered]@{ path = $_.Target; size = (Get-Item $_.Source).Length; sha256 = Get-Sha256 $_.Source }
    })
    $hashed = if ($package.changesWith) {
        Get-ChildItem (Join-Path $RepoRoot $package.changesWith) -File | Sort-Object Name |
            ForEach-Object { [ordered]@{ path = $_.Name; sha256 = Get-Sha256 $_.FullName } }
    } else { $listed }
    $contentHash = Get-TextSha256 (($hashed | ForEach-Object { "$($_.path):$($_.sha256)" }) -join "`n")
    $old = $previousPackages[$package.name]
    if ($old -and $old.contentHash -eq $contentHash) {
        $packages.Add($old)
        Write-Host "$($package.name): unchanged since $($old.release)"
        continue
    }
    $zip = New-PackageZip $package.name $files
    $uploads.Add($zip.FullName)
    $packages.Add([ordered]@{
        name = $package.name
        release = $tag
        url = "$baseUrl/$($zip.Name)"
        size = $zip.Length
        sha256 = Get-Sha256 $zip.FullName
        contentHash = $contentHash
        files = $listed
    })
    Write-Host ('{0}: {1} files, {2:N1} MB zipped' -f $package.name, $listed.Count, ($zip.Length / 1MB))
}

$navGroups = @(Get-NavGroups $previous)

Assert-WorldDumpMatchesServer

$notes = @(Get-ReleaseNotes)
if ($Version -and -not ($notes | Where-Object { $_.version -eq $version })) {
    $testNotes = if ($NotesFile) { ([System.IO.File]::ReadAllText((Resolve-Path $NotesFile))).Trim() } else { '- Test release built with release.ps1 -Version.' }
    $notes = @([ordered]@{ version = $version; notes = $testNotes }) + $notes
}
if ($testChannel) { $notes = @(Add-EarlierTestNotes $notes $previous) }
$currentNotes = $notes | Where-Object { $_.version -eq $version } | Select-Object -First 1
if (-not $currentNotes) { throw "CHANGELOG.md has no section for $version." }

$manifest = [ordered]@{
    product = $releaseConfig.productName
    version = $version
    tag = $tag
    published = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    minLauncherVersion = $releaseConfig.minLauncherVersion
    realmName = $releaseConfig.realmName
    coopProtocol = $releaseConfig.coopProtocol
    clientDlls = $releaseConfig.clientDlls
    releaseNotes = $notes
    navTiles = $navGroups
    thirdParty = @($releaseConfig.thirdParty | ForEach-Object { Get-ThirdPartyEntry $_ })
    packages = $packages
}
$launcherExe = Join-Path $buildDir 'launcher\HoALauncher.exe'
if (Test-Path $launcherExe) {
    Copy-Item $launcherExe (Join-Path $assetsDir 'HoALauncher.exe') -Force
    $releaseUploads.Add((Join-Path $assetsDir 'HoALauncher.exe'))
}
$manifestPath = Join-Path $assetsDir 'manifest.json'
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 8) + "`n")
$notesPath = Join-Path $outDir 'notes.md'
$releaseBody = $currentNotes.notes
$stagedLauncher = Join-Path $assetsDir 'HoALauncher.exe'
if (Test-Path $stagedLauncher) {
    $launcherHash = (Get-FileHash $stagedLauncher -Algorithm SHA256).Hash.ToLowerInvariant()
    $releaseBody += "`n`n---`n`nNew here? Download ``HoALauncher.exe`` below and put it in your World of Warcraft 1.12.1 folder. Already playing? The launcher updates itself.`n`n``HoALauncher.exe`` SHA-256: ``$launcherHash``"
}
[System.IO.File]::WriteAllText($notesPath, $releaseBody + "`n")
$releaseUploads.Add($manifestPath)

Write-Host "Release $tag staged in $outDir ($($uploads.Count) changed packages for $packageTag)"
if (-not $Publish) { return }

$title = if ($testChannel) { "$($releaseConfig.productName) $version (test build)" } else { "$($releaseConfig.productName) $version" }
if ($uploads.Count) {
    gh release create $packageTag @uploads --repo $repository --prerelease --title "$title update packages" --notes "Packages the launcher downloads for $tag. Players don't need anything here: get HoALauncher.exe from the $tag release."
    if ($LASTEXITCODE -ne 0) { throw "gh release create $packageTag failed with exit code $LASTEXITCODE." }
}
gh release create $tag @releaseUploads --repo $repository --title $title --notes-file $notesPath --latest
if ($LASTEXITCODE -ne 0) { throw "gh release create failed with exit code $LASTEXITCODE." }
Write-Host "Published $tag to $repository"
if (-not $testChannel) {
    Send-DiscordAnnouncement $title $currentNotes.notes "https://github.com/$repository/releases/tag/$tag"
}
