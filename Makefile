SHELL := /bin/bash
.DEFAULT_GOAL := build
PROJECT := Verbatim.xcodeproj
SCHEME := Verbatim
DERIVED_DATA ?= DerivedData
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$(DERIVED_DATA)"
FORMATTER := $(shell xcrun --find swift-format 2>/dev/null || command -v swift-format)

.PHONY: setup build test lint format format-check check
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
