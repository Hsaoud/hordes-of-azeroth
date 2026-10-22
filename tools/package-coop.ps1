param(
    [string]$GameFolder,
    [switch]$SkipBuild,
    [switch]$ReusePreparedGame
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = Join-Path $projectRoot 'release\coop'
$overlay = Join-Path $outputRoot 'overlay'
$serverBuild = Join-Path $projectRoot 'server\build-coop'
$localCargo = Join-Path $PSScriptRoot 'coop\.cargo\bin\cargo.exe'
if (Test-Path $localCargo) {
    $env:CARGO_HOME = Join-Path $PSScriptRoot 'coop\.cargo'
    $env:RUSTUP_HOME = Join-Path $PSScriptRoot 'coop\.rustup'
    $cargo = $localCargo
} else { $cargo = 'cargo' }

function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed ($LASTEXITCODE)." }
}

if (-not $SkipBuild) {
    Invoke-Checked $cargo @('build', '--release', '--locked', '--manifest-path', (Join-Path $PSScriptRoot 'coop\Cargo.toml'))
    Invoke-Checked 'dotnet' @('build', (Join-Path $PSScriptRoot 'launcher\HordesOfAzerothLauncher.csproj'), '-c', 'Release', '--nologo')
    if (-not (Test-Path (Join-Path $serverBuild 'CMakeCache.txt'))) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        $major = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion).Split('.')[0]
        $generator = if ([int]$major -ge 18) { 'Visual Studio 18 2026' } else { 'Visual Studio 17 2022' }
        Invoke-Checked 'cmake' @('-S', (Join-Path $projectRoot 'server\core'), '-B', $serverBuild, '-G', $generator, '-A', 'x64', '-DBUILD_FOR_HOST_CPU=OFF', '-DBUILD_EXTRACTORS=0', "-DCMAKE_INSTALL_PREFIX=$projectRoot\server\run")
    }
    Invoke-Checked 'cmake' @('--build', $serverBuild, '--config', 'Release', '--parallel', '4')
}
Invoke-Checked 'cmake' @('--install', $serverBuild, '--config', 'Release')
Invoke-Checked 'python' @((Join-Path $PSScriptRoot 'package-source.py'))

New-Item -ItemType Directory -Force $overlay, (Join-Path $overlay 'tools'), (Join-Path $overlay 'server\run'), (Join-Path $overlay 'HordesOfAzeroth'), (Join-Path $overlay 'Interface'), (Join-Path $overlay 'config') | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'coop\target\release\hoa-coop.exe') -Destination (Join-Path $overlay 'tools\hoa-coop.exe') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'launcher\bin\HoALauncher.exe') -Destination $overlay -Force
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsInstance = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$redist = Get-ChildItem (Join-Path $vsInstance 'VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT') -Directory | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $redist) { throw 'Visual C++ runtime files are missing from the Build Tools.' }
foreach ($name in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
    Copy-Item -LiteralPath (Join-Path $redist.FullName $name) -Destination (Join-Path $overlay 'server\run') -Force
    Copy-Item -LiteralPath (Join-Path $redist.FullName $name) -Destination (Join-Path $overlay 'tools') -Force
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $projectRoot 'server\run') -File | Where-Object { $_.Extension -eq '.exe' -or $_.Extension -eq '.dll' -or $_.Name.EndsWith('.conf.dist') }) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $overlay 'server\run') -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'Interface\AddOns') -Destination (Join-Path $overlay 'Interface') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'Interface\GlueXML') -Destination (Join-Path $overlay 'Interface') -Recurse -Force
foreach ($name in 'BonkAccount.lua', 'BonkStats.lua') {
    $generated = Join-Path $overlay "Interface\GlueXML\$name"
    if (Test-Path -LiteralPath $generated) { Remove-Item -LiteralPath $generated }
}
Copy-Item -Path (Join-Path $projectRoot 'config\*.overrides.conf') -Destination (Join-Path $overlay 'config') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'COOP.md') -Destination (Join-Path $overlay 'LIRE-MOI-COOP.md') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'coop\PLAY-TOGETHER.fr.txt') -Destination (Join-Path $overlay 'JOUER-ENSEMBLE.txt') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'LICENSE') -Destination $overlay -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'THIRD-PARTY-NOTICES.md') -Destination $overlay -Force
Copy-Item -LiteralPath (Join-Path $outputRoot 'HordesOfAzeroth-Coop-Sources.zip') -Destination $overlay -Force
Copy-Item -LiteralPath (Join-Path $outputRoot 'HordesOfAzeroth-Rust-Licenses.zip') -Destination $overlay -Force
$fingerprint = (Get-FileHash (Join-Path $overlay 'server\run\mangosd.exe') -Algorithm SHA256).Hash
[IO.File]::WriteAllText((Join-Path $overlay 'HordesOfAzeroth\coop-build.txt'), $fingerprint)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $outputRoot 'HordesOfAzeroth-Coop-Overlay.zip'
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
[IO.Compression.ZipFile]::CreateFromDirectory($overlay, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)

if ($GameFolder) {
    $source = [IO.Path]::GetFullPath($GameFolder).TrimEnd('\')
    $destination = Join-Path $outputRoot 'HordesOfAzeroth-Coop'
    foreach ($required in 'WoW.exe', 'HordesOfAzeroth.exe', 'server\mariadb-data\mysql', 'server\data\maps', 'server\data\5875\dbc') {
        if (-not (Test-Path -LiteralPath (Join-Path $source $required))) { throw "The installed game is incomplete: $required is missing." }
    }
    foreach ($name in 'mangosd', 'realmd', 'mariadbd', 'HordesOfAzeroth') {
        foreach ($process in Get-Process -Name $name -ErrorAction SilentlyContinue) {
            try { $processPath = $process.Path } catch { throw 'Close the game and its launcher before preparing the copy.' }
            if ($processPath -and ($processPath.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase) -or $processPath.StartsWith($destination + '\', [StringComparison]::OrdinalIgnoreCase))) { throw 'Close the game and its launcher before copying the database.' }
        }
    }
    if ($destination.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Choose an installed game outside the build output.' }
    if (Test-Path -LiteralPath $destination) {
        if (-not $ReusePreparedGame -or -not (Test-Path -LiteralPath (Join-Path $destination 'HordesOfAzeroth\coop-build.txt'))) { throw 'The prepared game already exists. Choose another output folder before preparing a fresh copy.' }
    } else {
        New-Item -ItemType Directory -Path $destination | Out-Null
        & robocopy $source $destination /E /R:1 /W:1 /NFL /NDL /NJH /NJS /XD .git .codex .agents .aws build build-coop core .cargo .rustup target release backups (Join-Path $source 'Logs') (Join-Path $source 'server\logs') WDB
        if ($LASTEXITCODE -ge 8) { throw 'The game copy did not complete.' }
    }
    & robocopy $overlay $destination /E /R:1 /W:1 /NFL /NDL /NJH /NJS
    if ($LASTEXITCODE -ge 8) { throw 'The co-op overlay did not copy.' }
    $gameZip = Join-Path $outputRoot 'HordesOfAzeroth-Coop.zip'
    if (Test-Path -LiteralPath $gameZip) {
        if (-not $ReusePreparedGame) { throw 'A complete game archive already exists.' }
        Remove-Item -LiteralPath $gameZip
    }
    [IO.Compression.ZipFile]::CreateFromDirectory($destination, $gameZip, [IO.Compression.CompressionLevel]::Fastest, $true)
    Invoke-Checked 'python' @((Join-Path $PSScriptRoot 'verify-coop-package.py'), $gameZip)
    Write-Host "Prepared game: $gameZip"
}
Write-Host "Co-op overlay: $zip"
