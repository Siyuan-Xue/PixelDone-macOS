# Mac Handoff

## Prerequisites

- macOS host with Xcode 26.6 selected.
- XcodeGen 2.46.0.
- `PixelDoneAppleCore` cloned beside this repository at `../PixelDoneAppleCore`.

Confirm the pinned AppleCore foundation in `APPLECORE_PIN.json`.

## Local Configuration

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Edit only the ignored local file. Use a publishable or legacy anon key, never a service-role key.

## Generate

```sh
chmod +x script/generate_project.sh script/build_and_run.sh
./script/generate_project.sh
open PixelDone-macOS.xcodeproj
```

The committed `project.yml` is authoritative. Do not make durable project-setting changes only inside the generated project.

## Run

```sh
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

The script generates the project when it is missing, builds to a deterministic local DerivedData path, and launches the `.app` bundle.

## First Mac Tasks

1. Confirm Xcode resolves all three local AppleCore products.
2. Run the foundation app through `script/build_and_run.sh`.
3. Fix project/toolchain issues without changing product contracts.
4. Replace the foundation views with the Phase A composition described by AppleCore.
5. Select a Personal Team only if required for local signing; keep team identifiers out of Git.

The Windows host did not run these commands.
