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
                8.0.x
                10.0.x
            verificationScript: '.github/scripts/Test-Integration.ps1'
        secrets: inherit
```

`dotNetVersion` supports the multi-line SDK list provided by `actions/setup-dotnet`.
Install every runtime needed by the tests rather than relying on the runner image.

Publish this workflow change to the referenced `v1.0` branch **before** adding the
new input to a caller. Until then, GitHub rejects the caller's unknown input.

## License
The Basilisque framework (including this repository) is licensed under the [Apache License, Version 2.0](LICENSE.txt).