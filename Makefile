.DEFAULT_GOAL := clean

# Configuration
PROJECT ?= MyAnimeList.xcodeproj
SCHEME ?= MyAnimeList
APP_NAME ?= MyAnimeList
CONFIGURATION ?= Debug
BUNDLE_ID ?= com.samuelhe.MyAnimeList
APP_TEST_ONLY ?= MyAnimeListTests
DATAPROVIDER_TEST_FILTER ?=
CONNECTED_IOS_DEVICE_ID := $(shell xcrun xcdevice list | /usr/bin/python3 -c 'import json, sys; devices = json.load(sys.stdin); print(next((device["identifier"] for device in devices if device.get("platform") == "com.apple.platform.iphoneos" and device.get("available") and not device.get("simulator")), ""))')
BOOTED_SIMULATOR_ID := $(shell xcrun simctl list devices booted -j | /usr/bin/python3 -c 'import json, sys; devices = json.load(sys.stdin).get("devices", {}); print(next((device["udid"] for runtime_name, runtime_devices in devices.items() if "iOS" in runtime_name for device in runtime_devices if device.get("isAvailable") and device.get("state") == "Booted"), ""))')
DEVICE_APP_PATH = $(shell xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(CONNECTED_IOS_DEVICE_ID)" -showBuildSettings -json | /usr/bin/python3 -c 'import json, sys; data = json.load(sys.stdin); item = next(entry for entry in data if entry.get("target") == "$(APP_NAME)"); settings = item["buildSettings"]; print(settings["TARGET_BUILD_DIR"] + "/" + settings["FULL_PRODUCT_NAME"])')
SIMULATOR_APP_PATH = $(shell if [ -n "$(BOOTED_SIMULATOR_ID)" ]; then xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(BOOTED_SIMULATOR_ID)" -showBuildSettings -json | /usr/bin/python3 -c 'import json, sys; data = json.load(sys.stdin); item = next(entry for entry in data if entry.get("target") == "$(APP_NAME)"); settings = item["buildSettings"]; print(settings["TARGET_BUILD_DIR"] + "/" + settings["FULL_PRODUCT_NAME"])'; fi)
DEVICE_PROCESS_LAUNCH_ARGS ?=
APP_ONLY_TESTING_ARG = -only-testing:$(APP_TEST_ONLY)
DATAPROVIDER_TEST_FILTER_ARG = $(if $(strip $(DATAPROVIDER_TEST_FILTER)),--filter "$(DATAPROVIDER_TEST_FILTER)",)
TEST_APP_MAKE_ARGS = APP_TEST_ONLY="$(APP_TEST_ONLY)"
TEST_DATAPROVIDER_MAKE_ARGS = DATAPROVIDER_TEST_FILTER="$(DATAPROVIDER_TEST_FILTER)"

# Testing
.PHONY: test-app
test-app:
	@[ -n "$(CONNECTED_IOS_DEVICE_ID)" ] || { echo "No connected iPhone found."; exit 1; }
	@echo "Using device $(CONNECTED_IOS_DEVICE_ID)"
	@echo "Running MyAnimeList tests..."
	@set -o pipefail; NSUnbufferedIO=YES xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(CONNECTED_IOS_DEVICE_ID)" test $(APP_ONLY_TESTING_ARG) -collect-test-diagnostics never 2>&1 | xcbeautify --disable-logging && echo "** TEST SUCCEEDED **"
	@echo "MyAnimeList tests completed."

.PHONY: test-dataprovider
test-dataprovider:
	@echo "Running DataProvider tests..."
	@set -o pipefail; swift test --quiet --package-path DataProvider -Xswiftc -gnone $(DATAPROVIDER_TEST_FILTER_ARG) 2>&1 | awk '$$0 != "CoreData: warning: Migration was completed by another client"'
	@echo "DataProvider tests completed."

.PHONY: test-app-sim
test-app-sim:
	@[ -n "$(BOOTED_SIMULATOR_ID)" ] || { echo "No booted simulator found."; exit 1; }
	@echo "Using simulator $(BOOTED_SIMULATOR_ID)"
	@echo "Running MyAnimeList tests..."
	@set -o pipefail; NSUnbufferedIO=YES xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(BOOTED_SIMULATOR_ID)" test $(APP_ONLY_TESTING_ARG) -collect-test-diagnostics never 2>&1 | xcbeautify --disable-logging && echo "** TEST SUCCEEDED **"
	@echo "MyAnimeList tests completed."

.PHONY: test
test:
	@$(MAKE) --no-print-directory test-app $(TEST_APP_MAKE_ARGS)
	@$(MAKE) --no-print-directory test-dataprovider $(TEST_DATAPROVIDER_MAKE_ARGS)
	@echo "All tests completed."

.PHONY: test-sim
test-sim:
	@$(MAKE) --no-print-directory test-app-sim $(TEST_APP_MAKE_ARGS)
	@$(MAKE) --no-print-directory test-dataprovider $(TEST_DATAPROVIDER_MAKE_ARGS)
	@echo "All tests completed."

# Build and Run
.PHONY: build
build:
	@echo "Building $(SCHEME)..."
	@set -o pipefail; NSUnbufferedIO=YES xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination 'generic/platform=iOS' build 2>&1 | xcbeautify --disable-logging
	@echo "Build completed."

.PHONY: run-device
run-device:
	@[ -n "$(CONNECTED_IOS_DEVICE_ID)" ] || { echo "No connected iPhone found."; exit 1; }
	@echo "Using device $(CONNECTED_IOS_DEVICE_ID)"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(CONNECTED_IOS_DEVICE_ID)" build
	xcrun devicectl device install app --device $(CONNECTED_IOS_DEVICE_ID) "$(DEVICE_APP_PATH)"
	xcrun devicectl device process launch --terminate-existing --device $(CONNECTED_IOS_DEVICE_ID) $(BUNDLE_ID) $(DEVICE_PROCESS_LAUNCH_ARGS)

.PHONY: run-device-reset-tmdb-api-key
run-device-reset-tmdb-api-key: DEVICE_PROCESS_LAUNCH_ARGS = -- -reset-tmdb-api-key
run-device-reset-tmdb-api-key: run-device

.PHONY: run-sim
run-sim:
	@[ -n "$(BOOTED_SIMULATOR_ID)" ] || { echo "No booted simulator found."; exit 1; }
	@echo "Using simulator $(BOOTED_SIMULATOR_ID)"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(BOOTED_SIMULATOR_ID)" build
	xcrun simctl install "$(BOOTED_SIMULATOR_ID)" "$(SIMULATOR_APP_PATH)"
	xcrun simctl launch --terminate-running-process "$(BOOTED_SIMULATOR_ID)" $(BUNDLE_ID) $(DEVICE_PROCESS_LAUNCH_ARGS)

# Maintenance
.PHONY: clean
clean:
	xcodebuild clean -project MyAnimeList.xcodeproj -scheme MyAnimeList

.PHONY: refresh-packages
refresh-packages:
	rm MyAnimeList.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
	xcodebuild -resolvePackageDependencies

.PHONY: format
format:
	swift format -r -p -i .

.PHONY: lint
lint:
	swift format lint -r -p .
