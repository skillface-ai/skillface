.PHONY: check run shots app dist notarize version help

check: ## build and test: the definition of done
	swift build
	swift test

run: ## open Skillface
	swift run skillface

shots: ## draw every screen offscreen into .build/shots/*.png, on sample data
	swift run shots .build/shots

APP = .build/app/Skillface.app
# Who signs. "-" is ad-hoc: it runs here, and Gatekeeper stops it on any other Mac. A release
# passes "Developer ID Application", which also needs the hardened runtime to be notarized.
SIGN ?= -
HARDENED = $(if $(filter -,$(SIGN)),,--options runtime --timestamp)

app: ## the release build as .build/app/Skillface.app, signed by SIGN (ad-hoc unless given)
	swift build -c release --product skillface
	rm -rf $(APP) && mkdir -p $(APP)/Contents/MacOS
	cp .build/release/skillface $(APP)/Contents/MacOS/
	cp App/Info.plist $(APP)/Contents/
	codesign --force $(HARDENED) --sign "$(SIGN)" $(APP)
	@echo "built $(CURDIR)/$(APP)"

# The one place the version lives. A release is this, tagged v$(VERSION).
VERSION = $(shell plutil -extract CFBundleShortVersionString raw App/Info.plist)
DIST = .build/dist
DMG = $(DIST)/Skillface-$(VERSION).dmg
SUM = cd $(DIST) && shasum -a 256 $(notdir $(DMG)) > $(notdir $(DMG)).sha256

version: ## the version in App/Info.plist
	@echo $(VERSION)

dist: app ## the app in .build/dist/Skillface-<version>.dmg, with its sha256
	rm -rf $(DIST) && mkdir -p $(DIST)/dmg
	cp -R $(APP) $(DIST)/dmg/ && ln -s /Applications $(DIST)/dmg/Applications
	hdiutil create -quiet -volname Skillface -srcfolder $(DIST)/dmg -format UDZO -ov $(DMG)
	rm -rf $(DIST)/dmg
	$(if $(filter -,$(SIGN)),,codesign --timestamp --sign "$(SIGN)" $(DMG))
	$(SUM)
	@echo "packed $(CURDIR)/$(DMG)"

notarize: ## have Apple check the dmg, so it opens without a warning: NOTARY_KEY (a .p8), NOTARY_KEY_ID, NOTARY_ISSUER
	xcrun notarytool submit $(DMG) --key "$(NOTARY_KEY)" --key-id "$(NOTARY_KEY_ID)" --issuer "$(NOTARY_ISSUER)" --wait
	xcrun stapler staple $(DMG)
	$(SUM)

help: ## every target
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-9s %s\n", $$1, $$2}'
