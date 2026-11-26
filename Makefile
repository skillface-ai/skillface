.PHONY: check run shots app dist version help

check: ## build and test: the definition of done
	swift build
	swift test

run: ## open Skillface
	swift run skillface

shots: ## draw every screen offscreen into .build/shots/*.png, on sample data
	swift run shots .build/shots

APP = .build/app/Skillface.app

app: ## the release build as .build/app/Skillface.app, signed ad-hoc
	swift build -c release --product skillface
	rm -rf $(APP) && mkdir -p $(APP)/Contents/MacOS
	cp .build/release/skillface $(APP)/Contents/MacOS/
	cp App/Info.plist $(APP)/Contents/
	codesign --force --sign - $(APP)
	@echo "built $(CURDIR)/$(APP)"

# The one place the version lives. A release is this, tagged v$(VERSION).
VERSION = $(shell plutil -extract CFBundleShortVersionString raw App/Info.plist)
ZIP = .build/dist/Skillface-$(VERSION).zip

version: ## the version in App/Info.plist
	@echo $(VERSION)

dist: app ## the app zipped as .build/dist/Skillface-<version>.zip, with its sha256
	rm -rf .build/dist && mkdir -p .build/dist
	ditto -c -k --keepParent $(APP) $(ZIP)
	cd .build/dist && shasum -a 256 $(notdir $(ZIP)) > $(notdir $(ZIP)).sha256
	@echo "packed $(CURDIR)/$(ZIP)"

help: ## every target
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-8s %s\n", $$1, $$2}'
