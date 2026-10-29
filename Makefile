SIMULATOR ?= iPhone 17
DATE ?= $(shell date +%Y-%m-%d)
SPECIES ?= boletus_edulis

.PHONY: setup generate open build test cli golden clean

setup:
	@command -v xcodegen >/dev/null || brew install xcodegen
	@test -f Config/Local.xcconfig || cp Config/Local.xcconfig.example Config/Local.xcconfig
	@$(MAKE) generate

generate:
	xcodegen generate

open: generate
	open Grzyby.xcodeproj

build: generate
	xcodebuild -project Grzyby.xcodeproj -scheme Grzyby -destination 'platform=iOS Simulator,name=$(SIMULATOR)' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build

test:
	cd Engine && swift test

cli:
	cd Engine && swift run score-cli --region Tests/GrzybEngineTests/Fixtures --date $(DATE) --species $(SPECIES)

golden:
	cd Engine && UPDATE_GOLDEN=1 swift test --filter GoldenRankingTests

clean:
	rm -rf build Engine/.build
