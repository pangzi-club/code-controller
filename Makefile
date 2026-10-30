# npm-scripts style development commands. Run `make help` (or just `make`) to list them.

# Paths are discovered, not hardcoded, so Scripts/rename.sh can rename the
# target freely. App identity comes from AppInfo.swift — the single source of
# truth shared with Scripts/make-app.sh.
APPINFO := $(firstword $(wildcard Sources/*/AppInfo.swift))
APP_DISPLAY_NAME := $(shell sed -nE 's/^[[:space:]]*static let displayName[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' $(APPINFO))
APP_PATH := build/$(APP_DISPLAY_NAME).app
DEV_APP_PATH := build/$(APP_DISPLAY_NAME)-Dev.app

.DEFAULT_GOAL := help

help: ## List available commands
	@awk -F ':.*## ' '/^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

dev: ## Debug build and run the app
	swift run

build: ## Release build
	swift build -c release

test: ## Run tests (Swift Testing + XCTest)
	swift test

check-l10n: ## Verify Localizable.strings key parity across languages
	python3 Scripts/check-l10n.py

app: ## Assemble the distribution .app bundle (Developer ID or ad-hoc)
	./Scripts/make-app.sh

mas: ## Assemble the App Store build and .pkg (Apple Distribution)
	MAS=1 ./Scripts/make-app.sh

launch: ## Assemble and open the dev .app (dev identity, separate TCC/container)
	DEV=1 ./Scripts/make-app.sh
	open "$(DEV_APP_PATH)"

rename: ## Rename the app template: make rename NEW=MyApp ID=com.me.MyApp
	@if [ -z "$(NEW)" ]; then echo "usage: make rename NEW=MyApp [ID=com.me.MyApp]"; exit 1; fi
	@if [ -n "$(ID)" ]; then ./Scripts/rename.sh $(NEW) $(ID); else ./Scripts/rename.sh $(NEW); fi

template-diff: ## Diff template-managed files against a starter checkout (SOURCE=...)
	@if [ -z "$(SOURCE)" ]; then echo "usage: make template-diff SOURCE=/path/to/swiftui-starter"; exit 1; fi
	./Scripts/template-diff.sh "$(SOURCE)"

clean: ## Remove build artifacts
	swift package clean
	rm -rf build/

.PHONY: help dev build test check-l10n app mas launch rename template-diff clean
