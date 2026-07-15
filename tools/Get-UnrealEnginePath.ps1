<#
.SYNOPSIS
    Resolve the installation directory of the Unreal Engine a project is bound to.

.DESCRIPTION
    Reads the 'EngineAssociation' field from a .uproject file and resolves it to an engine
    installation directory, checking both places Unreal registers engines:

        Launcher installs   HKLM:\SOFTWARE\EpicGames\Unreal Engine\<association>
                            association is a version ("5.6"), path is the InstalledDirectory value.

        Source builds       HKCU:\SOFTWARE\Epic Games\Unreal Engine\Builds
                            association is a GUID, matched against the value names; the value
                            data is the engine root. Note the space in 'Epic Games' here, absent
                            from the Launcher key above -- Unreal really is inconsistent.

    Writes the installation directory to the pipeline. Throws on any failure, so callers can
    decide between try/catch and letting the error bubble up.

.PARAMETER ProjectFile
    Path to the .uproject file.

.EXAMPLE
    .\Get-UnrealEnginePath.ps1 -ProjectFile C:\Dev\MyGame\MyGame.uproject

.EXAMPLE
    $engine = & .\Get-UnrealEnginePath.ps1 -ProjectFile $uproject
    & "$engine\Engine\Build\BatchFiles\Build.bat" -projectfiles -project="$uproject" -game -rocket
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ProjectFile
)

function Get-LauncherInstall([string] $Association) {
    $regPath = "HKLM:\SOFTWARE\EpicGames\Unreal Engine\$Association"
    Write-Verbose "Looking up Launcher install: $regPath"
    if (Test-Path $regPath) {
        (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstalledDirectory
    }
}

function Get-SourceBuild([string] $Association) {
    $buildsPath = 'HKCU:\SOFTWARE\Epic Games\Unreal Engine\Builds'
    Write-Verbose "Looking up source build: $buildsPath"
    if (-not (Test-Path $buildsPath)) { return }

    $builds = Get-Item $buildsPath
    # Registrations are values on the key itself: name = association GUID, data = engine root.
    # Braces and casing vary between the .uproject and the registry, so compare without them.
    $wanted = $Association.Trim('{', '}')
    foreach ($name in $builds.GetValueNames()) {
        if ($name.Trim('{', '}') -eq $wanted) {
            return $builds.GetValue($name)
        }
    }
}

Write-Verbose "Reading EngineAssociation from: $ProjectFile"
try {
    $engineKey = (Get-Content $ProjectFile -Raw -ErrorAction Stop | ConvertFrom-Json).EngineAssociation
}
catch {
    throw "Failed to read .uproject file: $ProjectFile`nEnsure the path is correct and the file is valid JSON."
}

if (-not $engineKey) {
    throw "Missing 'EngineAssociation' in .uproject: $ProjectFile`nOpen the project in the Unreal Editor, or set the field by hand, to bind it to an engine."
}

Write-Verbose "EngineAssociation: $engineKey"
$installedDir = Get-LauncherInstall $engineKey
if (-not $installedDir) {
    $installedDir = Get-SourceBuild $engineKey
}

if (-not $installedDir) {
    throw @"
Engine '$engineKey' is not registered on this machine.
Checked HKLM:\SOFTWARE\EpicGames\Unreal Engine\$engineKey (Launcher installs)
    and HKCU:\SOFTWARE\Epic Games\Unreal Engine\Builds (source builds).
A GUID association means a source build: register it by running Engine\Binaries\Win64\UnrealVersionSelector.exe,
or right-clicking the .uproject and picking 'Switch Unreal Engine version...'.
"@
}

# The registry is not consistent about separators: Launcher installs come back with
# backslashes, source builds with forward slashes. Normalise so callers get one format.
$installedDir = [System.IO.Path]::GetFullPath($installedDir).TrimEnd('\', '/')

Write-Verbose "Engine path: $installedDir"
return $installedDir
