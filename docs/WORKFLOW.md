# Workflow

1. **Wei** drops an idea or bug (project thread or a GitHub issue).
2. **PM** turns it into a user story issue with acceptance criteria and a milestone (M0–M3). Wei approves the story.
3. **Design** produces a mockup for anything with UI. Wei approves the mockup.
4. **R&D** (iOS engineer, with the data/AI engineer for algorithms) opens a PR that links the issue and includes tests.
5. **QA** reviews the PR against the acceptance criteria, design and privacy rules. A failure goes back to R&D.
6. **Release** merges, tags a version, and CI attaches `GymApp.ipa` to the GitHub release.
7. **Wei** installs and tests on the phone. Feedback goes back to PM.

## Gates
| Gate | Criteria |
| --- | --- |
| M0 → M1 | App runs on Wei's phone, widget shows app data, mockups approved |
| M1 → M2 | 2 weeks of daily use without blockers |
| M2 → M3 | v1.1 stable for 4 weeks |

## Labels
`story`, `bug`, `design`, `algorithm`, `qa`, `release`, plus `M0`…`M3`.
