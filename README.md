# Golem Unlimited Provider UI for Mac

## Build from Command Line

### Install Dependencies

Install CocoaPods:
`# sudo gem install cocoapods`

To install dependencies, please run this in the main project directory:
`# pod install`

### Copy Server Binary

Before building the project, please replace empty "gu-provider-ui/gu-provider" file with the Golem Unlimited Provider server (macOS binary named "gu-provider"; it can be build from https://github.com/golemfactory/golem-unlimited).

### Build Project

`# xcodebuild -workspace gu-provider-ui.xcworkspace -scheme gu-provider-ui archive -archivePath gu-provider-ui`

The "Golem Unlimited Provider.app" directory will be located in "gu-provider-ui.xcarchive/Products/Applications/".
If you forgot to copy "gu-provider" file, you can still copy it to the "Resources" directory.

### Create DMG

Create a link to the /Applications folder, so that the user can drag the app there:

`# ln -s /Applications/ gu-provider-ui.xcarchive/Products/Applications/Applications`

Create DMG:

`# hdiutil create -volname "Golem Unlimited Provider" -srcfolder gu-provider-ui.xcarchive/Products/Applications/ -ov gu-provider.dmg`

## Open in Xcode

`# open gu-provider-ui.xcworkspace` (**not** xcodeproj)
