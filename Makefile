.DEFAULT_GOAL := clean

PROJECT ?= MyAnimeList.xcodeproj
SCHEME ?= MyAnimeList
APP_NAME ?= MyAnimeList
CONFIGURATION ?= Debug
BUNDLE_ID ?= com.samuelhe.MyAnimeList
CONNECTED_IOS_DEVICE_ID := $(shell xcrun xcdevice list | /usr/bin/python3 -c 'import json, sys; devices = json.load(sys.stdin); print(next((device["identifier"] for device in devices if device.get("platform") == "com.apple.platform.iphoneos" and device.get("available") and not device.get("simulator")), ""))')
DEVICE_APP_PATH = $(shell xcodebuild -quiet -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(CONNECTED_IOS_DEVICE_ID)" -showBuildSettings -json | /usr/bin/python3 -c 'import json, sys; data = json.load(sys.stdin); item = next(entry for entry in data if entry.get("target") == "$(APP_NAME)"); settings = item["buildSettings"]; print(settings["TARGET_BUILD_DIR"] + "/" + settings["FULL_PRODUCT_NAME"])')
DEVICE_PROCESS_LAUNCH_ARGS ?=

.PHONY: build
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination 'generic/platform=iOS' build

.PHONY: test
test:
	@[ -n "$(CONNECTED_IOS_DEVICE_ID)" ] || { echo "No connected iPhone found."; exit 1; }
	@echo "Using device $(CONNECTED_IOS_DEVICE_ID)"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination "id=$(CONNECTED_IOS_DEVICE_ID)" test -only-testing:MyAnimeListTests

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
