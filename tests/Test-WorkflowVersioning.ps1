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
$artifacts = Join-Path $root 'artifacts'
$versionFile = Join-Path (Join-Path $artifacts 'obj') 'gitversion.json'
$outputFile = Join-Path $root 'github-output.txt'
$previousOutput = $env:GITHUB_OUTPUT

function Assert-WorkflowVersion {
    param([hashtable] $VersionData, [string] $Label, [string] $Expected)

    $VersionData | ConvertTo-Json -Compress | Set-Content -LiteralPath $versionFile -Encoding utf8
    if (Test-Path -LiteralPath $outputFile) {
        Remove-Item -LiteralPath $outputFile
    }

    $script = $versioningScript.
        Replace('${{ inputs.basBuildType }}', $Label).
        Replace('${{ inputs.artifactsPath }}', $artifacts.Replace("'", "''")).
        Replace('${{ inputs.versioningProjectName }}', '').
        Replace('${{ inputs.basVersionMajor }}', '').
        Replace('${{ inputs.basVersionMinor }}', '').
        Replace('${{ inputs.basVersionBuild }}', '').
        Replace('${{ inputs.basVersionRevision }}', '')
    & ([scriptblock]::Create($script))

    $actual = (Get-Content -LiteralPath $outputFile -Raw).Trim()
    if ($actual -ne "version=$Expected") {
        throw "Expected version=$Expected, got $actual."
    }
}

try {
    New-Item -ItemType Directory -Path (Split-Path $versionFile) -Force | Out-Null
    $env:GITHUB_OUTPUT = $outputFile

    Assert-WorkflowVersion @{ MajorMinorPatch = '2.3.4'; VersionSourceDistance = 17 } 'CI' '2.3.4-CI00017'
    # Backward compatibility with GitVersion versions that only emit CommitsSinceVersionSource.
    Assert-WorkflowVersion @{ MajorMinorPatch = '2.3.4'; CommitsSinceVersionSource = 42 } 'Preview' '2.3.4-Preview00042'
    Assert-WorkflowVersion @{ MajorMinorPatch = '2.3.4'; CommitsSinceVersionSource = 0 } 'CI' '2.3.4-CI00000'
    Assert-WorkflowVersion @{ MajorMinorPatch = '2.3.4'; VersionSourceDistance = 0; CommitsSinceVersionSource = 42 } 'RC' '2.3.4-RC00000'
    Assert-WorkflowVersion @{ MajorMinorPatch = '2.3.4' } 'Release' '2.3.4'

    foreach ($invalidVersionData in @(
        @{ MajorMinorPatch = '2.3.4' }
        @{ MajorMinorPatch = '2.3.4'; VersionSourceDistance = 'invalid'; CommitsSinceVersionSource = 42 }
    )) {
        try {
            Assert-WorkflowVersion $invalidVersionData 'CI' 'unused'
            throw 'An invalid version increment should have failed.'
        }
        catch {
            if ($_.Exception.Message -ne 'The version increment is missing or not numeric.') {
                throw
            }
        }
    }

    Write-Host 'Workflow versioning tests passed.'
}
finally {
    $env:GITHUB_OUTPUT = $previousOutput
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
