# PGO + LTO build for Patricia-Next (no make on this machine, so this replaces
# `make pgo`). Profile workload = the standard bench, same as upstream.
param([string]$OutName = "patricia_pgo.exe")

$ErrorActionPreference = "Stop"
$gpp = "C:\msys64\ucrt64\bin\g++.exe"
if (Test-Path $gpp) {
  $env:PATH = "C:\msys64\ucrt64\bin;" + $env:PATH
} else {
  $gpp = "g++.exe"
}

$flags = @("-O3", "-march=native", "-std=c++20", "-ffast-math",
           "-static-libstdc++", "-static-libgcc")
$sources = @("src/patricia.cpp", "src/fathom/src/tbprobe.c")

# GCC names the .gcda profile files after the output binary, so BOTH stages
# must use the same -o name for -fprofile-use to find the data.
Write-Host "[1/3] building instrumented binary..."
& $gpp @flags -fprofile-generate $sources -o $OutName
if ($LASTEXITCODE -ne 0) { throw "instrumented build failed" }

Write-Host "[2/3] generating profile (3x bench)..."
1..3 | ForEach-Object { & ".\$OutName" bench > $null }

Write-Host "[3/3] rebuilding $OutName with -fprofile-use -flto..."
& $gpp @flags -flto=auto -fprofile-use -fprofile-correction $sources -o $OutName
if ($LASTEXITCODE -ne 0) { throw "final build failed" }

Remove-Item *.gcda -ErrorAction SilentlyContinue
Write-Host "done: $OutName"
