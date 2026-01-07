SHELL := /bin/sh

SCHEME ?= File City
CONFIG ?= Debug
TEAM_ID ?= 542GXYT5Z2
PROJECT_DIR := File City

BUILD_SETTINGS = xcodebuild -showBuildSettings -project "$(PROJECT_DIR)/File City.xcodeproj" -scheme "$(SCHEME)" -configuration $(CONFIG)
TARGET_BUILD_DIR := $(shell $(BUILD_SETTINGS) 2>/dev/null | awk -F ' = ' '/TARGET_BUILD_DIR/ {print $$2; exit}')
WRAPPER_NAME := $(shell $(BUILD_SETTINGS) 2>/dev/null | awk -F ' = ' '/WRAPPER_NAME/ {print $$2; exit}')
APP_PATH := $(TARGET_BUILD_DIR)/$(WRAPPER_NAME)
PROCESS_NAME := $(basename $(WRAPPER_NAME))

.PHONY: build install run clean app-path test

build:
	xcodebuild -project "$(PROJECT_DIR)/File City.xcodeproj" -scheme "$(SCHEME)" -configuration $(CONFIG) \
		DEVELOPMENT_TEAM=$(TEAM_ID) -allowProvisioningUpdates build

install: build
	-pkill -x "$(PROCESS_NAME)" || true
	/usr/bin/ditto "$(APP_PATH)" "/Applications/$(WRAPPER_NAME)"

run: build
	-pkill -x "$(PROCESS_NAME)" || true
	open "$(APP_PATH)"

clean:
	xcodebuild -project "$(PROJECT_DIR)/File City.xcodeproj" -scheme "$(SCHEME)" -configuration $(CONFIG) clean

app-path:
	@echo "$(APP_PATH)"

test:
	xcodebuild test -project "$(PROJECT_DIR)/File City.xcodeproj" -scheme "$(SCHEME)" -destination 'platform=macOS' -skip-testing:File_CityUITests
