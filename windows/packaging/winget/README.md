# WinGet manifest draft

A draft of the `Tabbi.Tabbi` manifests (version, installer and en-US locale) for the Windows Package Manager.
Nothing here has been submitted.

Before submitting, update `PackageVersion` and the release URLs in all three files, and set `InstallerSha256` to the published `Tabbi-Setup.exe`'s hash (`(Get-FileHash Tabbi-Setup.exe).Hash`).

To submit: run `winget validate --manifest windows/packaging/winget`, then copy the three files to `manifests/t/Tabbi/Tabbi/<version>/` in a fork of [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) and open a pull request there (or use `wingetcreate submit`).
