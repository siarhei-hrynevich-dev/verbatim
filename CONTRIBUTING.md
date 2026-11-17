# Contributing to Verbatim

Thank you for helping improve Verbatim. Bug reports, feature ideas and pull requests are welcome. By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). To report a security problem, follow the [Security Policy](SECURITY.md) instead of opening an issue.

## Prerequisites

- An Apple Silicon Mac running macOS 15 or later.
- Full Xcode 26 or later with Swift 6.2, the macOS SDK and the Metal Toolchain component.
- Homebrew, for SwiftLint (and swift-format if your toolchain lacks it).

The [Development guide](Docs/DEVELOPMENT.md#requirements-and-toolchain) has the details.

## Getting started

```sh
make setup   # checks Xcode, installs missing tools, resolves packages
make check   # format-check, lint, Xcode build and tests
```

`make check` must pass before you open a pull request. Use `make format` to fix formatting and `make lint` to see lint findings; the [Development guide](Docs/DEVELOPMENT.md#make-targets) lists every target. Builds and tests run with `xcodebuild` and signing disabled; to run the app signed, select your own development team in Xcode locally and do not commit it.

## Read before writing code

[AGENTS.md](AGENTS.md) is the canonical rule set for this repository, for people and coding agents alike. Before changing code, read it and the documents it lists:

- [Development](Docs/DEVELOPMENT.md): toolchain, make targets, signing, dependencies, project organization and end-to-end tests.
- [Software Architecture Guidelines](Docs/SOFTWARE_ARCHITECTURE_GUIDELINES.md): Lightweight Clean Architecture with MVVM.
- [Project Architecture](Docs/ARCHITECTURE.md): how the guidelines apply here, recording constraints, model lifecycle and permissions.
- [Implementation Status](Docs/IMPLEMENTATION.md): what is actually built.
- [Swift Code Style](Docs/CODE_STYLE.md): file organization, naming, control flow and comments.

Update these documents when your change alters behavior or an architectural decision, and keep planned and implemented behavior distinct.

## Tests

Tests use [Swift Testing](https://developer.apple.com/documentation/testing) and live in `VerbatimTests`. Every test must run without AI models, network access, screen or audio capture permissions, microphones, or personal files; use temporary databases, files and media that the test creates. Tests run inside the app, so guard any work that would otherwise start at launch.

Optional end-to-end tests run real models on your Mac and are off unless you turn them on with environment variables. See [End-to-end tests with real models](Docs/DEVELOPMENT.md#end-to-end-tests-with-real-models) for the environment variables. Do not make them required.

## Commit messages

This repository uses [Conventional Commits](https://www.conventionalcommits.org/) with a short, lowercase, imperative summary:

```text
feat: add LLM record renaming
fix: language detection algorithm
docs: update documentation, split implementation and architecture files
chore: rename app to Verbatim and clean up repository for open source
```

Use `feat` for new behavior, `fix` for bug fixes, `docs` for documentation only, `test` for tests only, `refactor` for changes that keep behavior, and `chore` for tooling, dependencies and housekeeping.

## Pull requests

- Keep each pull request focused on one change, and describe what changed and why. Link the issue it addresses.
- Make sure `make check` passes.
- Add or update tests for the behavior you change.
- Update the documentation listed above, [CHANGELOG.md](CHANGELOG.md) under Unreleased for user-visible changes, and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) with the in-app license list (`ThirdPartyLicense.shipped`) when you add, remove or update a package.
- Manage dependencies through Xcode's Swift Package Manager references, link only the products you need, and commit `Package.resolved`. Prefer no new dependency when a small amount of code will do.
- For UI changes, include a screenshot or short recording that contains no personal data.

## What never to commit

- Signing team identifiers, certificates, provisioning profiles, tokens, API keys or other secrets.
- Recordings, transcripts, summaries, runtime databases, or anything else from your own library.
- AI model weights or converted models.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
