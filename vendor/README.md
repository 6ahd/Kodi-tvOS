# Prebuilt frameworks

`DexNavigationKit.framework` (arm64, tvOS) is the Swift remote-navigation module
that `LibInputTouch.mm` loads at run time through `DexRemoteNavigation.h`. It is
copied unchanged from the v21.61 app. Its source is not in this repository yet;
without the framework the app falls back to the built-in `DexRemotePan.h`
gesture handling.
