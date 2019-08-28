# Golem Unlimited Provider UI for Mac

## Dependencies

Install CocoaPods:
`# sudo gem install cocoapods`

To install dependencies, please run this in the main project directory:
`# pod install`

## Copy Server Binary

Before building the project, please replace empty "gu-provider-ui/gu-provider" file with the Golem Unlimited Provider server (macOS binary named "gu-provider"; it can be build from https://github.com/golemfactory/golem-unlimited).

## Build from command line

`# xcodebuild -workspace gu-provider-ui.xcworkspace -scheme gu-provider-ui`

## Open in Xcode

`# open gu-provider-ui.xcworkspace` (**not** xcodeproj)
