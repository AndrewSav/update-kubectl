# update-kubectl

TLDR: run it as admin on Windows 10 / Windows Server 2019 to make sure that you have the latest [kubectl.exe](https://kubernetes.io/docs/reference/kubectl/overview/) (optionally with [krew](https://krew.dev/)) on your PATH.
Get it with `curl.exe -LO https://raw.githubusercontent.com/andrewsav-datacom/update-kubectl/master/update-kubectl.ps1`

# Requirements

- Windows 10 with curl.exe (Or Windows Server 2019)

## What does it do?

This script is designed to automate download of kubectl.exe on Windows and putting it on PATH.
It also helps to make sure that the downloaded version is earlier on the PATH 
than other instances of kubectl.exe, for example, docker installed kubectl.exe - a common problem.
Additionally it can optionally downolad and install krew plugin manager for kubectl.

## How does it do it?

If there is already kubectl.exe present on the PATH, and it's not the version we would like,
there are three strategies of fixing it:

- Replace existing kubectl.exe with the new one
- Rename all existing `kubectl.exe` instances on the PATH to `kubectl.bak`, 
  and install new one in a new location, added on the 
- Insert `Path` of `kubectl.exe` to the PATH in front of all other paths
  (that's what docker does)

You can choose which one you would like to use with command line switches.

## Command line parameters

The strategies above correspond to the following mutually exclusive command line switches:

- ReplaceExisting
- RenameOthers
- DominatePath

`ReplaceExisting` is used by default if none of the three specified.

The `Version` switch passes the desired kubectl GitHub version, e.g. v1.16.3. Default is "latest".

If there is no `kubectl.exe` on the path, then the latest version or one specified in the `Version` parameter
will be downloaded to folder specified by the `Path` parameter (default `"$env:USERPROFILE\.kube\bin"`).

If there is already `kubectl.exe` on the path, the version will be checked, and if it does not match 
the desired version the selected strategy will be used to bring the kubectl version up to date.

The `Path` parameter is ignored in `ReplaceExisting` mode.

The `KrewVersion` parameter specifies the desired krew version. Pass `skip` to skip installing krew. The default is `latest`.

The `Force` switch modifies behavior described above, to force re-downloading the desired version even if the versions match.
This applies both to `kubectl` and `krew`.

The `InfoOnly` switch suppresses the update and only display the current location of kubectl.exe and version of both kubectl and krew and exits.

The `NoConfirm` switch:

- In `ReplaceExisting` mode suppresses confirmation to download the new version overwriting the existing one
- In `RenameOthers` mode suppresses confirmation for each existing kubectl.exe on the path renamed to `kubectl.bak`
- In `RenameOthers` and `DominatePath` modes suppresses confirmation to overwrite existing kubectl.exe in `kubectlFolder` with downloaded one

It also suppress confirmation to delete and re-install krew.

The `MaxChecks` parameter defaults to 10. It works in `RenameOthers` mode and indicates the maximum number of kubectl.exe instances to rename.
You rarely need to change that. This is a safety precaution for rare edge cases.
