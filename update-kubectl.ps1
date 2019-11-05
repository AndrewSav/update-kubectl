<#
.Synopsis
Run it as admin to make sure that you have the latest kubectl.exe (optionally with krew) on your PATH.
.Description
This script is designed to automate download of kubectl.exe on Windows and putting it on PATH.
It also helps to make sure that the downloaded version is earlier on the PATH 
than other instances of kubectl.exe, for example, docker installed kubectl.exe.
Additionally it can optionally downolad and install krew plugin manager for kubectl.

If there is already kubectl.exe present on the PATH, and it's not the version we would like,
there are three modes of fixing it:

- Replace existing kubectl.exe with the new one
- Rename all existing `kubectl.exe` instances on the PATH to `kubectl.bak`, 
  and install new one in a new location, added on the 
- Insert `Path` of `kubectl.exe` to the PATH in front of all other paths
  (that's what docker does)

You can choose which one you would like to use with command line switches.
.Parameter Version
Version of kubectl to download and install. Should be in 'v1.2.3' format.
.Parameter Path
Where to install kubectl. Ignored in ReplaceExisting mode, if another kubectl is already
present on the PATH.
.Parameter krewVersion
Version of krew to download and install. Should be in 'v1.2.3' format.
.Parameter Force
Forces re-downloading the desired version of kubectl and krew even if the versions are up-to-date
.Parameter NoConfirm
Automatically answers 'y' to all questions about overwritng files
.Parameter InfoOnly
Read-only mode, displays the current location of kubectl.exe and versions of both kubectl and krew and exits
.Parameter ReplaceExisting
Selects ReplaceExisting mode, see the description
.Parameter RenameOthers
Selects RenameOthers mode, see the description
.Parameter DominatePath
Selects DominatePath mode, see the description
.Parameter MaxChecks
It works in `RenameOthers` mode and indicates the maximum number of kubectl.exe instances to rename.
You rarely need to change that. This is a safety precaution for rare edge cases.
.Link
https://github.com/andrewsav-datacom/update-kubectl
#>
#Requires -RunAsAdministrator
#Requires -Version 5
[CmdletBinding(DefaultParameterSetName="ReplaceExisting",
    HelpURI="https://github.com/andrewsav-datacom/update-kubectl",
    PositionalBinding=$false)]
param(
    [ValidateScript({
        if ($_ -match "^(?i)v?(\d+).(\d+)(.(\d)+)?|latest$") {
            return $true
        }
        else {
            $er = Write-Error "Version should be either 'latest' or be in form of 'v1.2.3'" 2>&1
            throw ($er)
        }
    })]

    [string]$Version = "latest",

    [string]$Path = "$env:USERPROFILE\.kube\bin",

    [ValidateScript({
        if ($_ -match "^(?i)v?(\d+).(\d+)(.(\d)+)?|latest|skip$") {
            return $true
        }
        else {
            $er = Write-Error "Version should be either one of the 'latest','skip' or be in form of 'v1.2.3'" 2>&1
            throw ($er)
        }
    })]
    [string]$KrewVersion = "latest",

    [switch]$Force,

    [switch]$NoConfirm,

    [Parameter(Mandatory = $false, ParameterSetName = "ReplaceExisting")]
    [switch]$InfoOnly,

    [Parameter(ParameterSetName = "ReplaceExisting")]
    [switch]$ReplaceExisting,

    [Parameter(Mandatory = $true, ParameterSetName = "RenameOthers")]
    [switch]$RenameOthers,

    [Parameter(Mandatory = $true, ParameterSetName = "DominatePath")]
    [switch]$DominatePath,

    [Parameter(ParameterSetName = "RenameOthers")]
    [int]$MaxChecks = 10
)

## Todo: recosider output (colours)

$releaseVersion = "0.0.1"

# This script does not try to recover from errors. If a error happens it must stop
$ErrorActionPreference = "Stop"

# Script-global constants
$krewBinFolder = "$env:USERPROFILE\.krew\bin"
$krewLocation = "$env:USERPROFILE\.krew\bin\kubectl-krew.exe"
$yamlLocation = "$env:USERPROFILE\.krew\receipts\krew.yaml"

# Checks if passed $path is on PATH. $target specifies the Environment Variable location
function IsOnPath {
    param(
        [Parameter(Mandatory = $true)]
        [System.EnvironmentVariableTarget]$target,
        [Parameter(Mandatory = $true)]
        [string]$path
    )
    $pathVar = [Environment]::GetEnvironmentVariable("Path", $target)
    $path = $path.TrimEnd("\")
    $folders = $pathVar.Split(";").foreach( { $_.TrimEnd("\").TrimStart(" ") } )
    ($folders | Where-Object { $_ -eq $path }).Count -gt 0
}

# Checks if passed $path is on PATH for current process (powershell session)
function IsOnPathProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$path
    )
    IsOnPath Process $path
}

# Checks if passed $path is on PATH for system/user sections
function IsOnPathPersistent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$path
    )
    (IsOnPath Machine $path) -or (IsOnPath User $path)
}

# Adds $path to PATH both for current process (if not there already) and
# to user section (if not either on system or user secion already)
function EnsureOnPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$path
    )
    if (!(IsOnPathpersistent $path)) {
        $userPath = [Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User);
        if (!$userPath.EndsWith(";")) {
            $userPath = $userPath + ";"
        }
        $userPath = $userPath + $path
        [Environment]::SetEnvironmentVariable("Path", $userPath, [System.EnvironmentVariableTarget]::User);
    }
    if (!(IsOnPathProcess $path)) {
        $env:PATH = $env:PATH + ";" + $path
    }
}

# Being as bad as DockerDestop. Stuff our $path in front of everyone else on the system section
# Also add it for the current process
function DominatePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$path
    )
    $path = $path.TrimEnd("\")
    $systemPath = [Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine);
    $folders = ($systemPath).Split(";")
    $folders = $folders.where( { $_.TrimEnd("\").TrimStart(" ") -ne $path } );
    $systemPath = [string]::Join(";", $folders)
    $systemPath = $path + ";" + $systemPath
    [Environment]::SetEnvironmentVariable("Path", $systemPath, [System.EnvironmentVariableTarget]::Machine);
    # This is process scopped, so do not really care about a double up
    $env:PATH = $path + ";" + $env:PATH
}

# Process a semver string into a pscustomobject with Major/Minor/Patch properties
function ParseVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$version
    )
    [regex]$r = "^v(?'Major'\d+).(?'Minor'\d+).(?'Patch'\d)+`$"
    $m = $r.Match($version)
    if ($m.Success) { [pscustomobject]@{Major=$m.groups["Major"].Value;Minor=$m.groups["Minor"].Value;Patch=$m.groups["Patch"].Value} }
}

# Compare tow semver values returning -1 if the first is greater than the second, 
# 0 if equal and -1 otherwise.
function CompareVersions {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$first,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$second
    )

    if ($first.Major -gt $second.Major) {
        return 1
    }
    elseif ($first.Major -Lt $second.Major) {
        return -1
    }

    if ($first.Minor -gt $second.Minor) {
        return 1
    }
    elseif ($first.Minor -Lt $second.Minor) {
        return -1
    }

    if ($first.Patch -gt $second.Patch) {
        return 1
    }
    elseif ($first.Patch -Lt $second.Patch) {
        return -1
    }
    return 0
}


#-----------------------------------------------------
# Main body starts here

# Script's banner
Write-Output "*** $([IO.Path]::GetFilenameWithoutExtension($MyInvocation.MyCommand.Name)) v$releaseVersion"

# ReplaceExisting is the default mode, of neither of the other two are specified, then this is it
if (!$RenameOthers -and !$DominatePath) {
    $ReplaceExisting = $true
}

$kubectlVersion = $Version
$kubectlFolder = $Path

# Correct some common mistakes in versions:
# Accept 1.16 and v1.16 and convert to 1.16.0 and v1.16.0
if ($kubectlVersion -match "^v?(\d+).(\d+)`$") {
    $kubectlVersion = "$kubectlVersion.0"
}

# Accept 1.16.0 and convert to v1.16.0
if ($kubectlVersion -match "^(\d+).(\d+).(\d)+`$") {
    $kubectlVersion = "v$kubectlVersion"
}

if ($krewVersion -match "^(\d+).(\d+).(\d)+`$") {
    $krewVersion = "v$krewVersion"
}

if ($krewVersion -match "^v?(\d+).(\d+)`$") {
    $krewVersion = "$krewVersion.0"
}


# We need to be an admin because Docker Desktop requires Admin and puts it's stuff to System Environment variables
# that require admin to change, and Program Files folder that also requires admin to change
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script has to run elevated!"
    exit 1
}

# If you are on Windows 10 with latest updates you already have curl
if ($null -eq (Get-Command "curl.exe" -ErrorAction SilentlyContinue)) {
    Write-Error "curl.exe is missing! Install from https://curl.haxx.se/windows/, put it on path"
}

# First let's find out current kubectl location if any
$kubectlLocation = Get-Command "kubectl.exe" -ea SilentlyContinue
$installedKubectlVersion = ""
if ($kubectlLocation) {
    $installedKubectlVersion = kubectl.exe version --client -ojson | ConvertFrom-Json | Select-Object -Expand clientVersion | Select-Object -Expand gitVersion
    Write-Output "Current kubectl.exe location is $($kubectlLocation.Source)"
    Write-Output "Current kubectl.exe version is $installedKubectlVersion"
} else {
    Write-Output "kubectl.exe is not found on Path"
}

# Get the latest kubectl version number from Google
$latestKubectlVersion = curl.exe -fsSL https://storage.googleapis.com/kubernetes-release/release/stable.txt

# If user requested latest, update version to the numberic number now
if ($kubectlVersion -eq "latest") {
    $kubectlVersion = $latestKubectlVersion
}

Write-Output "Requested kubectl.exe version is $kubectlVersion"

# Highlight if user requested not latest version
if ($latestKubectlVersion -ne $kubectlVersion) {
    Write-Warning "Latest kubectl.exe version is $latestKubectlVersion"
} else {
    Write-Output "Latest kubectl.exe version is $latestKubectlVersion"
}


# Similar to the above but for krew instead of  kubectl
# The difference is that one cannot specify target location for krew
$installedKrewVersion = ""
if ($krewVersion -ne "skip") {
    # Get installsed krew version
    if (!(Test-Path $krewLocation)) {
        Write-Output "krew does not exist at $krewLocation"
    } else {
        $installedKrewVersion = (& $krewLocation version | Select-String "GitTag\s*(v.*)").Matches.Groups[1].Value
        Write-Output "Current krew version is $installedKrewVersion"
    }

    # Get latest krew version from GitHub
    $latestKrewVersion = curl.exe -fsSL https://api.github.com/repos/kubernetes-sigs/krew/releases/latest | ConvertFrom-Json | Select-Object -Expand tag_name

    # If user requested latest, update version to the numberic number now
    if ($krewVersion -eq "latest") {
        $krewVersion = $latestKrewVersion
    }

    Write-Output "Requested krew version is $krewVersion"

    # Highlight if user requested not latest version
    if ($latestKrewVersion -ne $krewVersion) {
        Write-Warning "Latest krew version is $latestKrewVersion"
    } else {
        Write-Output "Latest krew version is $latestKrewVersion"
    }

    # Warn if krew is not likely to work with selected kubectl version
    $semver = ParseVersion $kubectlVersion
    if (!$semver) {
        Write-Error "Could not parse kubectlVersion $kubectlVersion. Make sure it's in 'vx.y.z' format, e.g. 'v1.2.3'"
    }
    if ((CompareVersions $semver (ParseVersion "v1.16.0")) -lt 0) {
        Write-Warning "Due to bug in kubect version prior to v1.16.0, krew does not work properly on Windows"
    }
}

if ($InfoOnly) {
    exit
}

if ($Force -or ($kubectlVersion -ne $installedKubectlVersion)) {
    # User could have specified an invalid version, so let's see if there is one available
    $url = "https://storage.googleapis.com/kubernetes-release/release/$kubectlVersion/bin/windows/amd64/kubectl.exe"
    Write-Output "Probbing $url"
    curl.exe --output NUL --silent --head --fail $url
    if (!$?) {
        Write-Error "Could not download kubeclt $kubectlVersion"
    }

    # Determine where new kubectl download is to go to
    if ($ReplaceExisting -and $kubectlLocation) {
        $newKubectlLocation = $kubectlLocation.Source
    } else {
        mkdir $kubectlFolder -Force | Out-Null
        $newKubectlLocation = (Join-Path $kubectlFolder "kubectl.exe")
    }

    # Confirm overwrite
    if (!$NoConfirm -and (Test-Path $newKubectlLocation)) {
        $response = Read-Host "Replace file at $newKubectlLocation ? [y/n]"
        if ($response.Trim() -ne "y") {
            exit
        }
    }

    # Backup before overwriting
    $bak = [io.path]::ChangeExtension($newKubectlLocation, "bak")
    if (Test-Path $bak) { Remove-Item $bak }
    if (Test-Path $newKubectlLocation) { Move-Item $newKubectlLocation $bak }

    # Download to the specified location
    Write-Output "Downloading kubectl.exe to $newKubectlLocation"
    curl.exe -fsSL $url -o $newKubectlLocation
    if (!$?) {
        Write-Error "Could not download kubeclt $kubectlVersion"
    }

    # if there was no kubectl to start with, we need to put $kubectlFolder on the PATH
    if ($ReplaceExisting -and !$kubectlLocation) {
        EnsureOnPath $kubectlFolder
    }

    if ($RenameOthers) {
        EnsureOnPath $kubectlFolder
        $c = 0
        while (($c -lt $MaxChecks) -and ($kubectlLocation) -and ($kubectlLocation.Source -ne $newKubectlLocation)) {
            $dest = [io.path]::ChangeExtension($kubectlLocation.Source, "bak")
            if (!$NoConfirm) {
                Write-Warning "$($kubectlLocation.source) is on the path before $newKubectlLocation"
                $response = Read-Host "Change file extension at $($kubectlLocation.source) to .bak? [y/n]"
                if ($response.Trim() -ne "y") {
                    exit
                }
                if (!$NoConfirm -and (Test-Path $dest)) {
                    $response = Read-Host "There is already $dest there. Overwrite? [y/n]"
                    if ($response.Trim() -ne "y") {
                        exit
                    }
                }
                Move-Item $kubectlLocation.source $dest -Force
            } else {
                Write-Output "$($kubectlLocation.source) is on the path before $newKubectlLocation"
            }
            $c++
            $kubectlLocation = Get-Command "kubectl.exe" -ea SilentlyContinue
        }
        if ($c -eq $MaxChecks) {
            Write-Error "More than configured maxChecks number ($MaxChecks) instances of kubectl.exe found on the path"
        }
    }

    if ($DominatePath) {
        DominatePath $kubectlFolder
    }
}


if ($krewVersion -ne "skip" -and($Force -or ($krewVersion -ne $installedKrewVersion))) {

    if ((Test-Path $krewLocation) -or (Test-Path $yamlLocation)) {
        if (!$NoConfirm) {
            $response = Read-Host "$krewLocation will be detelted and re-installed. Proceed? [y/n]"
            if ($response.Trim() -ne "y") {
               exit
           }
        }
        Remove-Item $krewLocation
        Remove-Item $yamlLocation
    }

    $assets = curl.exe -fsSL https://api.github.com/repos/kubernetes-sigs/krew/releases | ConvertFrom-Json | ForEach-Object { $_ } |Where-Object { $_.tag_name -eq $krewVersion } | Select-Object -Expand assets
    if (!$?) {
        Write-Error "Could not download krew $krewVersion"
    }
    if (!$assets) {
        Write-Error "Could not find krew version $krewVersion"
    }
    $urlExe = $assets.Where( { @("krew.exe","krew-windows.exe") -contains $_.name } ).browser_download_url
    if (!$urlExe) {
        Write-Error "krew version $krewVersion does not have an assest with windows krew executable"
    }
    $urlYaml = $assets.Where( { @("krew.yml","krew.yaml") -contains $_.name } ).browser_download_url
    if (!$urlYaml) {
        Write-Error "krew version $krewVersion does not have an assest with krew yaml"
    }
    $tempDir = New-TemporaryFile | %{ Remove-Item $_; mkdir "$_-d" }
    $krewExe = Join-Path $tempDir "krew.exe"
    Write-Output "Downloading krew.exe to $krewExe"
    curl.exe -fsSL $urlExe -o $krewExe
    if (!$?) {
        Write-Error "Could not download krew executable from $urlExe"
    }
    $krewYaml = Join-Path $tempDir "krew.yaml"
    Write-Output "Downloading krew.yaml to $krewYaml"
    curl.exe -fsSL $urlYaml -o $krewYaml
    if (!$?) {
        Write-Error "Could not download krew yaml from $urlExe"
    }

    Write-Output "Running krew install"
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $global:krewInstalled = & $krewExe install "--manifest=$krewYaml" 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction

    Remove-Item $krewExe
    Remove-Item $krewYaml
    Remove-Item $tempDir

    if ($LASTEXITCODE) {
        Write-Error "Could not install krew`n$krewInstalled"
    }
    EnsureOnPath $krewBinFolder
}

if ($krewVersion -ne "skip") {
    EnsureOnPath $krewBinFolder
}

Write-Output "All done"
