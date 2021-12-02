# Copyright 2019 - 2021 Alexander Grund
# Distributed under the Boost Software License, Version 1.0.
# (See accompanying file LICENSE or copy at http://boost.org/LICENSE_1_0.txt)

$ErrorActionPreference = "Stop"

$scriptPath = split-path $MyInvocation.MyCommand.Path

# Install coverage collector (Similar to LCov)
choco install opencppcoverage

# Install uploader
Invoke-WebRequest -Uri https://uploader.codecov.io/latest/windows/codecov.exe -Outfile codecov.exe

# Verify integrity
if (Get-Command "gpg.exe" -ErrorAction SilentlyContinue){
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri https://keybase.io/codecovsecurity/pgp_keys.asc -OutFile codecov.asc
    Invoke-WebRequest -Uri https://uploader.codecov.io/latest/windows/codecov.exe.SHA256SUM -Outfile codecov.exe.SHA256SUM
    Invoke-WebRequest -Uri https://uploader.codecov.io/latest/windows/codecov.exe.SHA256SUM.sig -Outfile codecov.exe.SHA256SUM.sig

    $ErrorActionPreference = "Continue"
    gpg.exe --import codecov.asc
    if ($LASTEXITCODE -ne 0) { Throw "Importing the key failed." }
    gpg.exe --verify codecov.exe.SHA256SUM.sig codecov.exe.SHA256SUM
    if ($LASTEXITCODE -ne 0) { Throw "Signature validation of the SHASUM failed." }
    If ($(Compare-Object -ReferenceObject  $(($(certUtil -hashfile codecov.exe SHA256)[1], "codecov.exe") -join "  ") -DifferenceObject $(Get-Content codecov.exe.SHA256SUM)).length -eq 0) { 
        echo "SHASUM verified"
    } Else {
        exit 1
    }
}
    
# Run build with coverage collection
$env:B2_VARIANT = "debug"

# Use a temporary folder to avoid codecov picking up wrong files
mkdir __out

$ErrorActionPreference = "Continue"
OpenCppCoverage.exe --export_type cobertura:__out/cobertura.xml `
    --sources "${env:BOOST_ROOT}\libs\${env:SELF}" --modules "${env:BOOST_ROOT}" `
    <# Lines marked with LCov or coverity exclusion comments #>`
    --excluded_line_regex '.*// LCOV_EXCL_LINE' `
    --excluded_line_regex '.*// coverity\[dead_error_line\]' `
    <# Lines containing only braces #>`
    --excluded_line_regex '\s*[{}]*\s*' `
    <# Lines containing only else (and opt. braces) #>`
    --excluded_line_regex '\s*(\} )?else( \{)?\s*' `
    --cover_children -- cmd.exe /c $scriptPath/build.bat

if ($LASTEXITCODE -ne 0) { Throw "Coverage collection failed." }

# Upload
./codecov.exe --name Appveyor --env APPVEYOR_BUILD_WORKER_IMAGE --verbose --nonZero --dir __out --rootDir "${env:BOOST_CI_SRC_FOLDER}"
if ($LASTEXITCODE -ne 0) { Throw "Upload of coverage data failed." }
