SCHEME      := Walkie
PROJECT     := Walkie.xcodeproj
SIM_DEST    ?= platform=iOS Simulator,name=iPhone 16

.PHONY: project generate open build test clean

project:
	scripts/generate.sh

generate:
	scripts/generate.sh --no-open

open:
	open $(PROJECT)

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIM_DEST)' \
		CODE_SIGNING_ALLOWED=NO build

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIM_DEST)' \
		CODE_SIGNING_ALLOWED=NO test

clean:
	rm -rf $(PROJECT) build DerivedData
