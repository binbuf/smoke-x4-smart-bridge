# Host suite for the symphony verify command.
#
# The ESP-IDF/msys toolchain is not on the default PATH: CMake finds
# C:\msys64\ucrt64\bin\cc.exe but its DLLs are not visible, so the compiler
# check fails with "The C compiler identification is unknown". Put the UCRT
# and usr-bin directories first for this child process only.
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$env:PATH = "C:\msys64\ucrt64\bin;C:\msys64\usr\bin;$env:PATH"
Push-Location $root
try {
    & make host-test
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
