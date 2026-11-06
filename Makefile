VERSION ?= 0.0.0-dev
export VERSION

SWIFT_SOURCES := Package.swift Sources Tests Scripts/generate-icon.swift

# The Command Line Tools ship Swift Testing without its macro plugin on the default search path.
# A full Xcode install does not need this.
ifneq (,$(findstring CommandLineTools,$(shell xcode-select -p 2>/dev/null)))
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
endif

.DEFAULT_GOAL := help

.PHONY: help build test lint format app dmg run icon clean

help: ## List the available targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{ printf "  make %-8s %s\n", $$1, $$2 }'

build: ## Build the debug executable
	swift build

test: ## Run the unit tests
	swift test $(TEST_FLAGS)

lint: ## Check Swift formatting and shell scripts
	swift format lint --strict -r $(SWIFT_SOURCES)
	@if command -v shellcheck >/dev/null; then shellcheck Scripts/*.sh; else echo "shellcheck not installed, skipping the script check"; fi

format: ## Format the Swift sources in place
	swift format -i -r $(SWIFT_SOURCES)

app: ## Build a universal "dist/SplitDNS Manager.app" (VERSION=1.2.3 to set the version)
	Scripts/package-app.sh

dmg: app ## Build the .dmg and .zip next to the app
	Scripts/package-dmg.sh

run: app ## Build the app and open it
	open "dist/SplitDNS Manager.app"

icon: ## Regenerate Packaging/AppIcon.icns
	swift Scripts/generate-icon.swift Packaging/AppIcon.icns

clean: ## Remove build output
	rm -rf .build dist
