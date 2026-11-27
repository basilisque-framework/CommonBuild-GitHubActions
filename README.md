<!--
   Copyright 2026 Alexander Stärk

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-->
# Basilisque - Common Build - GitHub Actions

## Overview
[![License](https://img.shields.io/badge/License-Apache%20License%202.0-%23D22128.svg?logo=apache&logoColor=%23D22128)](LICENSE.txt)  

This project provides common GitHub Actions for projects that use the Basilisque framework.  

## GitVersion Warm-up
On Linux, the workflow runs GitVersion's `GetVersion` target once after restore
when the selected project has GitVersion enabled. This avoids the concurrent mutex initialization failure
reported in [GitTools/GitVersion#5367](https://github.com/GitTools/GitVersion/issues/5367).
It uses the supplied C# project, or `versioningProjectName` (the first C# project
when omitted) from the supplied solution. Project paths listed by the .NET CLI
are resolved relative to the solution directory. When `projectOrSolution` is a
wildcard, the first matching file in sorted order is used for the warm-up.
For multi-target projects, only the first target framework is warmed up.
The subsequent build remains parallel.

## Workflow Versioning
The workflow passes `basBuildType` to the build. The target projects determine
their versions, and pack reuses the build outputs. The workflow records the
checked-out commit and the built versions in the run summary.

Preview, RC and stable releases run on `main`, `master` or
`release/<major>.<minor>`. A stable release must match its release branch's line.
These runs tag the verified build. Alpha and CI runs publish their configured
artifacts without creating a Git tag.

The release version comes from the built NuGet packages. Set
`versioningPackageId` when packages have different versions. For a build without
packages, the workflow reads GitVersion's `SemVer`; use `versioningProjectName` to
select a project when needed. `releaseVersion` can assert the expected version
or supply it for a non-packable project without GitVersion.

### Migrating existing callers

- Upgrade CommonBuild and this reusable workflow together for release runs.
- Remove `basVersionMajor`, `basVersionMinor`, `basVersionBuild` and
  `basVersionRevision`. Configure the version in the target project.
- For a stable run whose commit is already tagged, reuse the original artifacts
  to retry publication.

Run the workflow versioning tests with:

```powershell
pwsh -NoProfile -File .\tests\Test-WorkflowVersioning.ps1
```

## Repository Verification
The reusable `Common-Build.yml` workflow accepts an optional `verificationScript` input.
It is a repository-relative path to a PowerShell script in the **calling repository**.
The default is empty, so existing callers do not run an additional step.

The script runs after the selected build/publish/pack steps, before NuGet artifact
upload, Git tagging, release creation, and package pushes. A script failure fails
the job and prevents those subsequent steps. Throw on failed checks or propagate
nonzero exit codes; do not catch failures and return success.

The script receives `BAS_CB_BUILD_TYPE` and `BAS_CB_ARTIFACTS_PATH` from the workflow
inputs and runs from the checked-out repository root. The existing `runDotnetTest`
switch remains independent and retains its original behavior. Verification runs
after Sonar analysis has ended; this hook does not import test coverage into Sonar.

For package integration tests that need the producer package first:

```yaml
jobs:
    build:
        uses: basilisque-framework/CommonBuild-GitHubActions/.github/workflows/Common-Build.yml@v1.0
        with:
            basBuildType: CI
            runDotnetPack: true
            runDotnetTest: false
            dotNetVersion: |
                10.0.x
                11.0.x
            verificationScript: '.github/scripts/Test-Integration.ps1'
        secrets: inherit
```

`dotNetVersion` supports the multi-line SDK list provided by `actions/setup-dotnet`.
Install every runtime needed by the tests rather than relying on the runner image.

Update the workflow reference in a caller when switching to a new workflow version.

## License
The Basilisque framework (including this repository) is licensed under the [Apache License, Version 2.0](LICENSE.txt).