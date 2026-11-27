# Copyright 2026 Alexander Stärk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

$ErrorActionPreference = 'Stop'
$workflowPath = [System.IO.Path]::Combine((Split-Path $PSScriptRoot), '.github', 'workflows', 'Common-Build.yml')
$workflow = Get-Content -LiteralPath $workflowPath -Raw
$match = [regex]::Match($workflow, '(?ms)^    - name: Versioning\r?\n.*?^      run: \|\r?\n(?<script>.*?)(?=^    - name: )')
if (-not $match.Success) {
    throw 'Could not find the workflow versioning step.'
}
$versioningScript = $match.Groups['script'].Value
$root = Join-Path ([System.IO.Path]::GetTempPath()) "CommonBuild-WorkflowVersioning-$([guid]::NewGuid().ToString('N'))"
$env:ARTIFACTS_PATH = Join-Path $root 'artifacts'
$env:VERSIONING_PROJECT_NAME = ''
$env:VERSIONING_PACKAGE_ID = ''
$env:RELEASE_VERSION = ''
$env:GITHUB_OUTPUT = Join-Path $root 'output.txt'
$env:GITHUB_STEP_SUMMARY = Join-Path $root 'summary.md'
$versionFile = Join-Path $env:ARTIFACTS_PATH 'obj/gitversion.json'

function Assert-WorkflowVersion {
    param([string] $SemVer, [string] $Channel, [string] $Ref, [string] $Expected, [string] $ErrorMessage)

    @{ SemVer = $SemVer; MajorMinorPatch = '9.9.9'; VersionSourceDistance = 999 } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $versionFile -Encoding utf8
    Set-Content -LiteralPath $env:GITHUB_OUTPUT -Value ''
    $env:BAS_CB_BuildType = $Channel
    $env:GITHUB_REF = $Ref

    try {
        & ([scriptblock]::Create($versioningScript))
    }
    catch {
        if ($ErrorMessage -and $_.Exception.Message -like "*$ErrorMessage*") { return }
        throw
    }

    if ($ErrorMessage) { throw "Expected workflow failure." }
    $actual = Get-Content -LiteralPath $env:GITHUB_OUTPUT
    if (@($actual -match '^sha=[0-9a-f]+$').Count -ne 1) { throw 'The output must include the checkout SHA.' }
    $versionOutput = @($actual -match '^version=')
    if (($Expected -and ($versionOutput -join '') -cne "version=$Expected") -or (!$Expected -and $versionOutput.Count -gt 0)) {
        throw "Unexpected version output: $versionOutput"
    }
}

try {
    New-Item -ItemType Directory -Path (Split-Path $versionFile) -Force | Out-Null
    Assert-WorkflowVersion '2.3.4-ci.feature.3-new.17' CI 'refs/heads/feature/3-new'
    Assert-WorkflowVersion '2.3.4-preview.42' Preview 'refs/heads/main' '2.3.4-preview.42'
    Assert-WorkflowVersion '2.3.4-rc.0' RC 'refs/heads/release/2.3' '2.3.4-rc.0'
    Assert-WorkflowVersion '2.3.4' Release 'refs/heads/release/2.3' '2.3.4'
    Assert-WorkflowVersion '2.4.0' Release 'refs/heads/release/2.3' -ErrorMessage 'does not belong to release line'
    Assert-WorkflowVersion '2.3.4-ci.1' Release 'refs/heads/main' -ErrorMessage 'requires a stable version'
    Assert-WorkflowVersion '2.3.4-CI00001' Preview 'refs/heads/main' -ErrorMessage 'requires a matching prerelease'
    Assert-WorkflowVersion '' Release 'refs/heads/main' -ErrorMessage 'needs exactly one artifact version'

    $packagePath = Join-Path $env:ARTIFACTS_PATH 'package'
    $manifestPath = Join-Path $root 'manifest'
    New-Item -ItemType Directory -Path $packagePath, $manifestPath | Out-Null
    '<package><metadata><id>Test</id><version>2.3.5</version></metadata></package>' |
        Set-Content -LiteralPath (Join-Path $manifestPath 'Test.nuspec')
    [IO.Compression.ZipFile]::CreateFromDirectory($manifestPath, (Join-Path $packagePath 'Test.2.3.5.nupkg'))
    Assert-WorkflowVersion '9.9.9' Release 'refs/heads/release/2.3' '2.3.5'
    '<package><metadata><id>Second</id><version>3.0.0</version></metadata></package>' |
        Set-Content -LiteralPath (Join-Path $manifestPath 'Test.nuspec')
    [IO.Compression.ZipFile]::CreateFromDirectory($manifestPath, (Join-Path $packagePath 'Second.3.0.0.nupkg'))
    Assert-WorkflowVersion '9.9.9' Release 'refs/heads/main' -ErrorMessage 'needs exactly one artifact version'
    $env:VERSIONING_PACKAGE_ID = 'Test'
    Assert-WorkflowVersion '9.9.9' Release 'refs/heads/release/2.3' '2.3.5'

    Write-Host 'Workflow versioning tests passed.'
}
finally {
    if (Test-Path -LiteralPath $root) {
        $resolved = (Resolve-Path -LiteralPath $root).Path
        $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolved.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
