# npm-scripts style development commands. Run `make help` (or just `make`) to list them.

# Display name comes from AppInfo.swift — same single source of truth as Scripts/make-app.sh.
APP_DISPLAY_NAME := $(shell sed -nE 's/^[[:space:]]*static let displayName[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' Sources/FileBrowser/AppInfo.swift)
APP_PATH := build/$(APP_DISPLAY_NAME).app

.DEFAULT_GOAL := help

help: ## List available commands
	@awk -F ':.*## ' '/^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

dev: ## Debug build and run the app
	swift run

build: ## Release build
	swift build -c release

app: ## Assemble the .app bundle
	./Scripts/make-app.sh

launch: ## Assemble the .app bundle and open it
	./Scripts/make-app.sh
	open $(APP_PATH)

clean: ## Remove build artifacts
	swift package clean
	rm -rf build/

.PHONY: help dev build app launch clean
