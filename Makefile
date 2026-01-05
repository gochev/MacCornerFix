.PHONY: build run clean install

APP_NAME = MacCornerFix
BUNDLE_ID = com.maccornerfix.app
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

build:
	@echo "Building $(APP_NAME)..."
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	
	# Compile Swift code
	swiftc -O \
		-sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
		-target x86_64-apple-macosx13.0 \
		-framework Cocoa \
		-framework ApplicationServices \
		-framework ScreenCaptureKit \
		MacCornerFix.swift \
		-o $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	
	# Copy Info.plist
	cp Info.plist $(APP_BUNDLE)/Contents/Info.plist
	
	# Code sign the app with entitlements
	codesign --force --deep --sign - --entitlements MacCornerFix.entitlements $(APP_BUNDLE)
	
	@echo "Build complete: $(APP_BUNDLE)"

run: build
	@echo "Running $(APP_NAME)..."
	@open $(APP_BUNDLE)

clean:
	@echo "Cleaning build directory..."
	@rm -rf $(BUILD_DIR)

install: build
	@echo "Installing $(APP_NAME) to /Applications..."
	@killall MacCornerFix 2>/dev/null || true
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/
	@echo "Installation complete!"
	@echo ""
	@echo "IMPORTANT: You need to grant Accessibility permissions:"
	@echo "1. Open System Settings"
	@echo "2. Go to Privacy & Security > Accessibility"
	@echo "3. Add MacCornerFix and enable it"
	@echo ""
	@echo "Launching MacCornerFix from /Applications..."
	@open /Applications/$(APP_NAME).app

help:
	@echo "Available targets:"
	@echo "  build   - Build the application"
	@echo "  run     - Build and run the application"
	@echo "  clean   - Remove build directory"
	@echo "  install - Install to /Applications"
	@echo "  help    - Show this help message"
