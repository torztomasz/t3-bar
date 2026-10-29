APP_BUNDLE := dist/T3 Bar.app

.PHONY: build test app run install

build:
	swift build

test:
	swift test

# Assembled by hand rather than via Xcode so the whole project stays a plain Swift package.
app:
	swift build -c release --product T3Bar
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp "$$(swift build -c release --show-bin-path)/T3Bar" "$(APP_BUNDLE)/Contents/MacOS/T3Bar"
	cp Support/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"

run: app
	open "$(APP_BUNDLE)"

# Installs into /Applications, or updates an existing install: pull, rebuild, quit the old copy, relaunch.
install:
	scripts/install.sh
