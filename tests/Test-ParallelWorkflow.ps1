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
$PSNativeCommandUseErrorActionPreference = $true

$workflowPath = Join-Path $PSScriptRoot '../.github/workflows/Common-Build.yml'
$workflow = Get-Content -LiteralPath $workflowPath -Raw
function Invoke-WorkflowStep([string] $name) {
    $escaped = [regex]::Escape($name)
    $match = [regex]::Match($workflow,
        "(?ms)^ {4}(?:- | {2})name: $escaped\r?\n(?:(?!^    - |^  \w).)*?^      run: \|\r?\n(?<script>.*?)(?=^    - |^  \w|\z)")
    if (!$match.Success) { throw "Missing PowerShell step '$name'." }
    $script = $match.Groups['script'].Value.Replace('exit $LASTEXITCODE', 'if ($LASTEXITCODE -ne 0) { throw "Command failed: $LASTEXITCODE" }')
    & ([scriptblock]::Create($script))
}

$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root = Join-Path $temp ('Basilisque-parallel-workflow-' + [Guid]::NewGuid().ToString('N'))
$producer = Join-Path $root 'producer'
$consumer = Join-Path $root 'consumer checkout'
$previousLocation = Get-Location
$variables = @('GITHUB_WORKSPACE','GITHUB_OUTPUT','GITHUB_STEP_SUMMARY','ARTIFACTS_PATH','PROJECT_OR_SOLUTION',
    'BUILD_TARGET','BUILD_SDK','BUILT_SHA','BAS_CB_BuildType','RUN_TEST','RUN_PACK','RUN_PUBLISH','SONAR_ENABLED',
    'TRANSFER_PATH','TASK','PUBLISH_FRAMEWORK','DOTNET_CLI_TELEMETRY_OPTOUT','_EnableDefaultWindowsPlatform','NUGET_PACKAGES',
    'VERSIONING_PROJECT_NAME')
$previous = @{}
foreach ($variable in $variables) { $previous[$variable] = [Environment]::GetEnvironmentVariable($variable) }

try {
    New-Item -ItemType Directory -Path $producer | Out-Null
    Set-Location -LiteralPath $producer
    git init -q -b main
    '<configuration><packageSources><clear /></packageSources></configuration>' | Set-Content NuGet.Config
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $sdk = dotnet --version
    $tfm = 'net{0}.0' -f ($sdk -split '[.-]')[0]
    New-Item -ItemType Directory -Path 'src/App' -Force | Out-Null
    @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>$tfm</TargetFramework>
    <OutputType>Exe</OutputType>
    <Version>2.3.4</Version>
  </PropertyGroup>
</Project>
"@ | Set-Content 'src/App/App.csproj'
    'System.Console.WriteLine("built once");' | Set-Content 'src/App/Program.cs'
    git add .
    git -c user.name=Probe -c user.email=probe@example.invalid commit -qm initial
    git tag v2.3.3

    $env:GITHUB_WORKSPACE = $producer
    $env:GITHUB_OUTPUT = Join-Path $root 'outputs'
    $env:GITHUB_STEP_SUMMARY = Join-Path $root 'summary'
    $env:ARTIFACTS_PATH = 'src/artifacts folder'
    $env:PROJECT_OR_SOLUTION = 'src/App/*.csproj'
    $env:BAS_CB_BuildType = 'ci'
    $env:RUN_TEST = 'true'
    $env:RUN_PACK = 'true'
    $env:RUN_PUBLISH = 'true'
    $env:SONAR_ENABLED = 'false'
    $env:_EnableDefaultWindowsPlatform = 'false'
    $env:NUGET_PACKAGES = Join-Path $root 'producer-packages'
    $env:TRANSFER_PATH = Join-Path $root 'transfer'

    Invoke-WorkflowStep 'Plan build'
    $outputs = Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw | ConvertFrom-StringData
    if ($outputs.tasks -cne '["test","pack","publish"]') { throw "Unexpected tasks: $($outputs.tasks)" }
    $env:BUILD_TARGET = $outputs.target
    $env:BUILD_SDK = $outputs.sdk
    $env:BUILT_SHA = $outputs.sha

    Invoke-WorkflowStep 'Dotnet Restore and lock dependencies'
    $env:VERSIONING_PROJECT_NAME = 'App'
    Invoke-WorkflowStep 'Warm up GitVersion serially'
    $lock = 'src/App/packages.lock.json'
    if (!(Test-Path -LiteralPath $lock)) { throw 'No NuGet lockfile was generated.' }
    $sourceLock = (Get-FileHash -LiteralPath $lock).Hash
    dotnet build $env:BUILD_TARGET -c Release --no-restore -p:UseArtifactsOutput=true "-p:ArtifactsPath=$producer/$env:ARTIFACTS_PATH" -p:UseSharedCompilation=false
    $builtAssembly = Get-ChildItem -LiteralPath (Join-Path $env:ARTIFACTS_PATH 'bin') -Recurse -Filter 'App.dll' | Select-Object -First 1
    $builtHash = (Get-FileHash -LiteralPath $builtAssembly.FullName).Hash
    Invoke-WorkflowStep 'Archive build state'

    git tag v9.0.0
    New-Item -ItemType Directory -Path $consumer | Out-Null
    Copy-Item -LiteralPath (Join-Path $producer '.git') -Destination $consumer -Recurse -Force
    Set-Location -LiteralPath $consumer
    git restore --worktree --source HEAD -- .
    git switch -q --detach $env:BUILT_SHA
    $env:GITHUB_WORKSPACE = $consumer
    $env:NUGET_PACKAGES = Join-Path $root 'consumer-packages'
    Invoke-WorkflowStep 'Unpack build state'
    Invoke-WorkflowStep 'Reuse Git context and locked dependencies'
    if ((Get-FileHash -LiteralPath $lock).Hash -ne $sourceLock) { throw 'The locked restore changed the lockfile.' }
    if ((git tag) -contains 'v9.0.0') { throw 'The downstream job retained a tag created after the build.' }
    if ((git symbolic-ref HEAD) -cne 'refs/heads/main') { throw 'The downstream job lost the original named HEAD.' }

    # A rebuild would fail, so pack and publish must use the transferred binaries.
    'this is not valid C#' | Set-Content 'src/App/Program.cs'
    $env:TASK = 'pack'
    Invoke-WorkflowStep 'Run ${{ matrix.task }}'
    $package = Get-ChildItem -LiteralPath (Join-Path $env:ARTIFACTS_PATH 'package') -Recurse -Filter 'App.2.3.4.nupkg'
    if (!$package) { throw 'Pack did not produce the expected package.' }
    $env:TASK = 'publish'
    Invoke-WorkflowStep 'Run ${{ matrix.task }}'
    $published = Get-ChildItem -LiteralPath (Join-Path $env:ARTIFACTS_PATH 'publish') -Recurse -Filter 'App.dll' | Select-Object -First 1
    if ((Get-FileHash -LiteralPath $published.FullName).Hash -ne $builtHash) { throw 'Publish did not reuse the original build.' }
    Invoke-WorkflowStep 'Archive published binaries'
    if (!(Test-Path -LiteralPath (Join-Path $env:TRANSFER_PATH 'publish.tar'))) { throw 'Missing published binary archive.' }

    $outdatedLock = Get-Content -LiteralPath $lock -Raw | ConvertFrom-Json -AsHashtable
    $outdatedLock.dependencies[$tfm]['Unused.Package'] = @{
        type = 'Direct'
        requested = '[1.0.0, )'
        resolved = '1.0.0'
        contentHash = 'AAAA'
    }
    $outdatedLock | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $lock
    git add -- $lock
    git -c user.name=Probe -c user.email=probe@example.invalid commit -qm 'Stale lockfile'
    $restoreRejected = $false
    try { Invoke-WorkflowStep 'Dotnet Restore and lock dependencies' }
    catch {
        if ($_.Exception.Message -notmatch 'git') { throw }
        $restoreRejected = $true
    }
    if (!$restoreRejected) { throw 'The build accepted a changed, checked-in lockfile.' }

    'Parallel workflow smoke tests passed.'
}
finally {
    Set-Location $previousLocation
    foreach ($variable in $variables) { [Environment]::SetEnvironmentVariable($variable, $previous[$variable]) }
    if (Test-Path -LiteralPath $root) {
        $resolved = (Resolve-Path -LiteralPath $root).Path
        if ([IO.Path]::GetDirectoryName($resolved) -eq $temp.TrimEnd([IO.Path]::DirectorySeparatorChar)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
