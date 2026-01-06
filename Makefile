.PHONY: test

test:
	xcodebuild test -project "File City/File City.xcodeproj" -scheme "File City" -destination 'platform=macOS'
