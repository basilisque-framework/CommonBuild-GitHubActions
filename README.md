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

## Build jobs

The reusable workflow builds one project or solution in Release configuration.
Set `projectOrSolution` to a path or a glob matching one target. The workflow
uses `artifactsPath` as the .NET artifacts directory for all jobs.

- **Build** restores dependencies, compiles once and saves the build outputs,
  lockfiles and Git refs used for versioning.
- **Test, Pack and Publish** start in parallel when enabled. Each checks out the
  original commit, downloads the build outputs, restores in locked mode and runs
  with `--no-build`. When SonarCloud is enabled, the coverage test runs in the
  Build job between the scanner's begin and end steps.
- **Repository verification**, when configured, runs after the selected checks
  and can use both the original build and the packaged outputs.
- **Publication** waits for the enabled checks. The NuGet destinations run in
  parallel when both apply. GitHub Release creation waits for them.

Check in `packages.lock.json` where you want the same dependency graph across
workflow runs. The Build job fails if restore changes a checked-in lockfile.
Where a lockfile is missing, Build generates it and passes it to the other jobs.
All jobs that consume build outputs check that they selected the same .NET SDK.

The workflow exposes `sha`, `releaseVersion`, `nugetArtifactName` and
`publishArtifactName` as outputs. Artifact names are unique to a workflow
invocation, so a calling workflow can use this workflow more than once. Published
binaries are provided as `publish.tar` to preserve executable permissions.

## GitVersion Warm-up
On Linux, the workflow runs GitVersion's `GetVersion` target once after restore
when the selected project has GitVersion enabled. This avoids the concurrent mutex initialization failure
reported in [GitTools/GitVersion#5367](https://github.com/GitTools/GitVersion/issues/5367).
It uses `versioningProjectName` if set, otherwise the first project that has
GitVersion enabled. Project paths listed by the .NET CLI are resolved relative
to the solution directory.
For multi-target projects, only the first target framework is warmed up.
The subsequent build remains parallel.

## Workflow Versioning
The workflow passes `basBuildType` to the build. The target projects determine
their versions, and pack reuses the build outputs. The run summary records the
checked-out commit for every build and the selected version for Preview, RC
and stable releases.

Preview, RC and stable releases run on `main`, `master` or
`release/<major>.<minor>`. A stable release must match its release branch's line.
These runs tag the verified build. Alpha and CI runs publish their configured
artifacts without creating a Git tag.
If the release tag already points to the built commit, the tag step succeeds.
If it points elsewhere, publication stops.

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
- Use `release/1.0` for Preview, RC and stable builds from a maintenance branch
  named `release/v1.0` in an earlier setup.
- Update jobs that download artifacts by hard-coded name to use the reusable
  workflow outputs. Extract `publish.tar` to access published binaries.

Run the workflow versioning tests with:

```powershell
pwsh -NoProfile -File .\tests\Test-WorkflowVersioning.ps1
pwsh -NoProfile -File .\tests\Test-ParallelWorkflow.ps1
```

## Repository Verification
The reusable `Common-Build.yml` workflow accepts an optional `verificationScript` input.
It is a repository-relative path to a PowerShell script in the **calling repository**.
The default is empty, so existing callers do not run an additional step.

The script runs after the selected test, publish and pack jobs. It receives
their build and packaging outputs through workflow artifacts. A script failure
prevents tagging, package pushes and release creation. Throw on failed checks or
propagate nonzero exit codes.

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