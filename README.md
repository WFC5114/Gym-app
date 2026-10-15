# GYM

A free, personal iPhone app for diet, body composition and training. It reads Apple Health and InBody scans, logs food MacroFactor-style, and shows everything through brutalist widgets and the Dynamic Island.

- **Plan:** [Gym App: Product & Team Plan](https://claude.ai/code/artifact/3f324c09-f9d2-4a6a-8f52-ff7a6d91a831)
- **Agents:** role files in [`.claude/agents/`](.claude/agents), workflow in [`docs/WORKFLOW.md`](docs/WORKFLOW.md)

## Install on your iPhone (from Windows)

Step by step, with what to expect: [`docs/INSTALL.md`](docs/INSTALL.md).

1. Open the latest run of the **CI** workflow (or the latest GitHub release) and download `GymApp.ipa`.
2. Install it with [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io) using your Apple ID.
3. On the phone: Settings > General > VPN & Device Management > trust your Apple ID. Turn on Developer Mode if asked.
4. Free Apple IDs need a reinstall or AltStore refresh every 7 days.

## Build

There's no Mac needed. GitHub Actions builds on a macOS runner:

```
brew install xcodegen ldid
xcodegen generate
scripts/test.sh
scripts/build-ipa.sh
```

The Xcode project is generated from `project.yml` and is not committed.
