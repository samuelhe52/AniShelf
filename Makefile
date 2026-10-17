.DEFAULT_GOAL := clean

# Configuration
PROJECT ?= MyAnimeList.xcodeproj
SCHEME ?= MyAnimeList
DEVICE_SCHEME ?= MyAnimeList-Release
APP_NAME ?= MyAnimeList
CONFIGURATION ?= Debug
DEVICE_CONFIGURATION ?= Release
RELEASE_TESTING_DIR ?= $(CURDIR)/.build/release-testing
RELEASE_TESTING_EXPORT_OPTIONS ?= scripts/ReleaseTestingExportOptions.plist
BUNDLE_ID ?= com.samuelhe.MyAnimeList
APP_TEST_ONLY ?= MyAnimeListTests
DATAPROVIDER_TEST_FILTER ?=
SKIP_APP_TESTS ?= MyAnimeListTests/InfoFetcherLiveFetchTests
# Prefer a USB-connected device, then one available over the network.
CONNECTED_IOS_DEVICE_ID := $(shell xcrun xcdevice list | /usr/bin/python3 -c 'import json, sys; priority = {"usb": 0, "network": 1}; devices = [device for device in json.load(sys.stdin) if device.get("platform") == "com.apple.platform.iphoneos" and device.get("available") and not device.get("simulator")]; devices.sort(key=lambda device: (priority.get(device.get("interface"), 2), device.get("identifier", ""))); print(devices[0]["identifier"] if devices else "")')
BOOTED_SIMULATOR_ID := $(shell xcrun simctl list devices booted -j | /usr/bin/python3 -c 'import json, sys; devices = json.load(sys.stdin).get("devices", {}); print(next((device["udid"] for runtime_name, runtime_devices in devices.items() if "iOS" in runtime_name for device in runtime_devices if device.get("isAvailable") and device.get("state") == "Booted"), ""))')
DEVICE_APP_PATH = $(shell xcodebuild -quiet -project $(PROJECT) -scheme $(DEVICE_SCHEME) -configuration $(DEVICE_CONFIGURATION) -destination "id=$(CONNECTED_IOS_DEVICE_ID)" -showBuildSettings -json | /usr/bin/python3 -c 'import json, sys; data = json.load(sys.stdin); item = next(entry for entry in data if entry.get("target") == "$(APP_NAME)"); settings = item["buildSettings"]; print(settings["TARGET_BUILD_DIR"] + "/" + settings["FULL_PRODUCT_NAME"])')
SIMULATOR_APP_PATH = $(shell if [ -n "$(BOOTED_SIMULATOR_ID)" ]; then xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(BOOTED_SIMULATOR_ID)" -showBuildSettings -json | /usr/bin/python3 -c 'import json, sys; data = json.load(sys.stdin); item = next(entry for entry in data if entry.get("target") == "$(APP_NAME)"); settings = item["buildSettings"]; print(settings["TARGET_BUILD_DIR"] + "/" + settings["FULL_PRODUCT_NAME"])'; fi)
MAC_DESTINATION ?= platform=macOS
MAC_APP_PATH = $(shell xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "$(MAC_DESTINATION)" -showBuildSettings -json | /usr/bin/python3 -c 'import json, sys; data = json.load(sys.stdin); item = next(entry for entry in data if entry.get("target") == "$(APP_NAME)"); settings = item["buildSettings"]; print(settings["TARGET_BUILD_DIR"] + "/" + settings["FULL_PRODUCT_NAME"])')
DEVICE_PROCESS_LAUNCH_ARGS ?=
MAC_LAUNCH_ARGS ?=
APP_ONLY_TESTING_ARGS = $(foreach test,$(APP_TEST_ONLY),-only-testing:$(test))
SKIP_ONLY_TESTING_ARGS = $(foreach test,$(SKIP_APP_TESTS),-skip-testing:$(test))
DATAPROVIDER_TEST_FILTER_ARG = $(if $(strip $(DATAPROVIDER_TEST_FILTER)),--filter "$(DATAPROVIDER_TEST_FILTER)",)
TEST_APP_MAKE_ARGS = APP_TEST_ONLY="$(APP_TEST_ONLY)"
TEST_DATAPROVIDER_MAKE_ARGS = DATAPROVIDER_TEST_FILTER="$(DATAPROVIDER_TEST_FILTER)"

# Testing
.PHONY: test-app
test-app:
	@[ -n "$(CONNECTED_IOS_DEVICE_ID)" ] || { echo "No connected iPhone found."; exit 1; }
	@echo "Using device $(CONNECTED_IOS_DEVICE_ID)"
	@echo "Running MyAnimeList tests..."
	@set -o pipefail; NSUnbufferedIO=YES xcodebuild -project $(PROJECT) -scheme $(DEVICE_SCHEME) -configuration $(DEVICE_CONFIGURATION) -destination "id=$(CONNECTED_IOS_DEVICE_ID)" test $(APP_ONLY_TESTING_ARGS) $(SKIP_ONLY_TESTING_ARGS) -collect-test-diagnostics never 2>&1 | xcbeautify --disable-logging && echo "** TEST SUCCEEDED **"
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
	@set -o pipefail; NSUnbufferedIO=YES xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(BOOTED_SIMULATOR_ID)" test $(APP_ONLY_TESTING_ARGS) $(SKIP_ONLY_TESTING_ARGS) -collect-test-diagnostics never 2>&1 | xcbeautify --disable-logging && echo "** TEST SUCCEEDED **"
	@echo "MyAnimeList tests completed."

.PHONY: test-app-mac
test-app-mac:
	@echo "Running MyAnimeList tests on native macOS..."
	@set -o pipefail; NSUnbufferedIO=YES xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "$(MAC_DESTINATION)" -allowProvisioningUpdates test $(APP_ONLY_TESTING_ARGS) $(SKIP_ONLY_TESTING_ARGS) -collect-test-diagnostics never 2>&1 | xcbeautify --disable-logging && echo "** TEST SUCCEEDED **"
	@echo "MyAnimeList tests completed."

.PHONY: test-app-live-fetch
test-app-live-fetch:
	@[ -n "$(CONNECTED_IOS_DEVICE_ID)" ] || { echo "No connected iPhone found."; exit 1; }
	@echo "Using device $(CONNECTED_IOS_DEVICE_ID)"
	@echo "Running InfoFetcher live-fetch tests..."
	@set -o pipefail; NSUnbufferedIO=YES xcodebuild -project $(PROJECT) -scheme $(DEVICE_SCHEME) -configuration $(DEVICE_CONFIGURATION) -destination "id=$(CONNECTED_IOS_DEVICE_ID)" test -only-testing:MyAnimeListTests/InfoFetcherLiveFetchTests -collect-test-diagnostics never 2>&1 | xcbeautify --disable-logging && echo "** TEST SUCCEEDED **"
	@echo "InfoFetcher live-fetch tests completed."

.PHONY: test-app-sim-live-fetch
test-app-sim-live-fetch:
	@[ -n "$(BOOTED_SIMULATOR_ID)" ] || { echo "No booted simulator found."; exit 1; }
	@echo "Using simulator $(BOOTED_SIMULATOR_ID)"
	@echo "Running InfoFetcher live-fetch tests..."
	@set -o pipefail; NSUnbufferedIO=YES xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(BOOTED_SIMULATOR_ID)" test -only-testing:MyAnimeListTests/InfoFetcherLiveFetchTests -collect-test-diagnostics never 2>&1 | xcbeautify --disable-logging && echo "** TEST SUCCEEDED **"
	@echo "InfoFetcher live-fetch tests completed."

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

.PHONY: test-mac
test-mac:
	@$(MAKE) --no-print-directory test-app-mac $(TEST_APP_MAKE_ARGS)
	@$(MAKE) --no-print-directory test-dataprovider $(TEST_DATAPROVIDER_MAKE_ARGS)
	@echo "All tests completed."

# Benchmarks (docs-ai 026): Release plus the fixture flag, in separate derived data.
# One size takes about 8.5 minutes. Check scaling with BENCH_SIZES='100 800 2000', or run
# part of the suite with BENCH_ONLY='testScrollList testCategorySwitchGrid'.
BENCH_SIZES ?= 800
BENCH_ONLY ?=
BENCH_DIR ?= $(CURDIR)/.build/benchmarks
BENCH_TESTS ?= $(if $(strip $(BENCH_ONLY)),$(foreach test,$(BENCH_ONLY),MyAnimeListUITests/LibraryBenchmarkTests/$(test)),MyAnimeListUITests/LibraryBenchmarkTests)
BENCH_SCHEME ?= MyAnimeList-Benchmarks
# `full` builds like the App Store (whole-module optimization) and runs 10 iterations.
# `quick` (`make bench-quick`) builds file by file for fast incremental rebuilds and runs 5,
# so its numbers go in their own baseline and are only compared with other quick runs.
BENCH_MODE ?= full
BENCH_ITERATIONS ?= $(if $(filter quick,$(BENCH_MODE)),5,10)
BENCH_SUFFIX = $(if $(filter quick,$(BENCH_MODE)),-quick)
BENCH_BASELINE = $(BENCH_DIR)/baseline$(BENCH_SUFFIX).json
BENCH_LATEST = $(BENCH_DIR)/latest$(BENCH_SUFFIX)
BENCH_XCODEBUILD_ARGS = -project $(PROJECT) -scheme $(BENCH_SCHEME) -configuration Release -destination "id=$(BOOTED_SIMULATOR_ID)" -derivedDataPath "$(BENCH_DIR)/DerivedData$(BENCH_SUFFIX)" 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$$(inherited) LIBRARY_FIXTURES' $(if $(filter quick,$(BENCH_MODE)),SWIFT_COMPILATION_MODE=singlefile)

.PHONY: bench-sim
bench-sim:
	@[ -n "$(BOOTED_SIMULATOR_ID)" ] || { echo "No booted simulator found."; exit 1; }
	@echo "Using simulator $(BOOTED_SIMULATOR_ID) ($(BENCH_MODE) mode, $(BENCH_ITERATIONS) iterations)"
	@set -o pipefail; \
	run_dir="$(BENCH_DIR)/runs/$$(date +%Y%m%d-%H%M%S)$(BENCH_SUFFIX)"; \
	mkdir -p "$$run_dir"; \
	NSUnbufferedIO=YES xcodebuild $(BENCH_XCODEBUILD_ARGS) build-for-testing 2>&1 | xcbeautify --disable-logging || exit 1; \
	for size in $(BENCH_SIZES); do \
		echo "Benchmarking a $$size-entry library..."; \
		TEST_RUNNER_LIBRARY_FIXTURE_SIZE=$$size TEST_RUNNER_LIBRARY_BENCH_ITERATIONS=$(BENCH_ITERATIONS) NSUnbufferedIO=YES xcodebuild $(BENCH_XCODEBUILD_ARGS) test-without-building $(foreach test,$(BENCH_TESTS),-only-testing:$(test)) -resultBundlePath "$$run_dir/$$size.xcresult" -collect-test-diagnostics never 2>&1 | xcbeautify --disable-logging || exit 1; \
	done; \
	python3 scripts/library_benchmarks.py summarize "$$run_dir" $(BENCH_MODE) $(BENCH_ITERATIONS) || exit 1; \
	ln -sfn "$$run_dir" "$(BENCH_LATEST)"; \
	echo; \
	python3 scripts/library_benchmarks.py compare "$(BENCH_BASELINE)" "$$run_dir/summary.json"

.PHONY: bench-baseline
bench-baseline:
	@[ -f "$(BENCH_LATEST)/summary.json" ] || { echo "No $(BENCH_MODE) benchmark run yet; run make bench-$(if $(filter quick,$(BENCH_MODE)),quick,sim) first."; exit 1; }
	@python3 scripts/library_benchmarks.py save-baseline "$(BENCH_BASELINE)" "$(BENCH_LATEST)/summary.json"

# Fast iteration loop: `make bench-quick BENCH_ONLY=testCategorySwitchGrid`, then
# `make bench-quick-baseline` to accept a result as the new reference.
.PHONY: bench-quick bench-quick-baseline
bench-quick:
	@$(MAKE) --no-print-directory bench-sim BENCH_MODE=quick

bench-quick-baseline:
	@$(MAKE) --no-print-directory bench-baseline BENCH_MODE=quick

# Build and Run
.PHONY: release-testing
release-testing:
	@mkdir -p "$(RELEASE_TESTING_DIR)"
	xcodebuild -quiet -project "$(PROJECT)" -scheme "$(DEVICE_SCHEME)" -configuration "$(DEVICE_CONFIGURATION)" -destination 'generic/platform=iOS' -archivePath "$(RELEASE_TESTING_DIR)/$(APP_NAME).xcarchive" -allowProvisioningUpdates archive
	xcodebuild -exportArchive -archivePath "$(RELEASE_TESTING_DIR)/$(APP_NAME).xcarchive" -exportOptionsPlist "$(RELEASE_TESTING_EXPORT_OPTIONS)" -exportPath "$(RELEASE_TESTING_DIR)/export" -allowProvisioningUpdates
	@echo "Release Testing IPA: $(RELEASE_TESTING_DIR)/export/$(APP_NAME).ipa"

.PHONY: build
build:
	@echo "Building $(SCHEME)..."
	@set -o pipefail; NSUnbufferedIO=YES xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination 'generic/platform=iOS' build 2>&1 | xcbeautify --disable-logging
	@echo "Build completed."

.PHONY: build-mac
build-mac:
	@echo "Building $(SCHEME) for native macOS..."
	@set -o pipefail; NSUnbufferedIO=YES xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "$(MAC_DESTINATION)" -allowProvisioningUpdates build 2>&1 | xcbeautify --disable-logging
	@echo "Build completed."

.PHONY: run-device
run-device:
	@[ -n "$(CONNECTED_IOS_DEVICE_ID)" ] || { echo "No connected iPhone found."; exit 1; }
	@echo "Using device $(CONNECTED_IOS_DEVICE_ID)"
	xcodebuild -project $(PROJECT) -scheme $(DEVICE_SCHEME) -configuration $(DEVICE_CONFIGURATION) -destination "id=$(CONNECTED_IOS_DEVICE_ID)" build
	xcrun devicectl device install app --device $(CONNECTED_IOS_DEVICE_ID) "$(DEVICE_APP_PATH)"
	xcrun devicectl device process launch --terminate-existing --device $(CONNECTED_IOS_DEVICE_ID) $(BUNDLE_ID) $(DEVICE_PROCESS_LAUNCH_ARGS)

.PHONY: run-sim
run-sim:
	@[ -n "$(BOOTED_SIMULATOR_ID)" ] || { echo "No booted simulator found."; exit 1; }
	@echo "Using simulator $(BOOTED_SIMULATOR_ID)"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(BOOTED_SIMULATOR_ID)" build
	xcrun simctl install "$(BOOTED_SIMULATOR_ID)" "$(SIMULATOR_APP_PATH)"
	xcrun simctl launch --terminate-running-process "$(BOOTED_SIMULATOR_ID)" $(BUNDLE_ID) $(DEVICE_PROCESS_LAUNCH_ARGS)

.PHONY: run-mac
run-mac:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "$(MAC_DESTINATION)" -allowProvisioningUpdates build
	@app_path="$(MAC_APP_PATH)"; \
	pkill -f "$$app_path/Contents/MacOS/" && sleep 1; \
	open -n "$$app_path" $(if $(strip $(MAC_LAUNCH_ARGS)),--args $(MAC_LAUNCH_ARGS),)

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
