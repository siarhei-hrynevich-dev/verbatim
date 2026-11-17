SHELL := /bin/bash
.DEFAULT_GOAL := build
PROJECT := Verbatim.xcodeproj
SCHEME := Verbatim
DERIVED_DATA ?= DerivedData
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$(DERIVED_DATA)"
FORMATTER := $(shell xcrun --find swift-format 2>/dev/null || command -v swift-format)
# Release packaging defaults to the version in the release-please manifest; CI passes the tag's version.
RELEASE_VERSION ?= $(shell sed -n 's/^ *"\.": *"\([^"]*\)".*/\1/p' .release-please-manifest.json)
BUILD_NUMBER ?= 1

.PHONY: setup build test lint format format-check check package
setup:
	@bash Scripts/setup.sh
	$(XCODEBUILD) -resolvePackageDependencies

build:
	$(XCODEBUILD) -disableAutomaticPackageResolution build CODE_SIGNING_ALLOWED=NO

test:
	$(XCODEBUILD) -disableAutomaticPackageResolution test CODE_SIGNING_ALLOWED=NO

lint:
	swiftlint lint --strict --no-cache

format:
	"$(FORMATTER)" format --configuration .swift-format --in-place --recursive Verbatim VerbatimTests

format-check:
	"$(FORMATTER)" lint --configuration .swift-format --strict --recursive Verbatim VerbatimTests

check:
	$(MAKE) format-check
	$(MAKE) lint
	$(MAKE) build
	$(MAKE) test

package:
	DERIVED_DATA="$(DERIVED_DATA)" bash Scripts/package-release.sh "$(RELEASE_VERSION)" "$(BUILD_NUMBER)"
