.PHONY: check run shots app help

check: ## build and test: the definition of done
	swift build
	swift test

run: ## open Yokan
	swift run yokan

shots: ## draw every screen offscreen into .build/shots/*.png, on sample data
	swift run shots .build/shots

APP = .build/app/Yokan.app

app: ## the release build as .build/app/Yokan.app, signed ad-hoc
	swift build -c release --product yokan
	rm -rf $(APP) && mkdir -p $(APP)/Contents/MacOS
	cp .build/release/yokan $(APP)/Contents/MacOS/
	cp App/Info.plist $(APP)/Contents/
	codesign --force --sign - $(APP)
	@echo "built $(CURDIR)/$(APP)"

help: ## every target
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-8s %s\n", $$1, $$2}'
