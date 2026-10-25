<div align="center">
  <img width="20%" height="20%" alt="AppStoreFix Icon" src="https://github.com/user-attachments/assets/9fd934cb-a20d-4b32-9552-f36ac0b199c6" />

  <h1>AppStoreFix</h1>
</div>

An iOS tweak that restores the App Store, iTunes Store, iBooks Store and Podcasts catalog on iOS 3, 5 and 6 by fixing connectivity, login, and storefront issues.

## What it fixes

- Redirects legacy iTunes Store session requests to the current Store session endpoint
- Fixes Store login by adding the trailing slash that Apple's `authenticate` endpoint now requires
- Repairs legacy search requests and the storefront identifier used by older clients
- Adds the missing form content type for older product purchase requests
- Relays older storefront bootstrap resources to their newer equivalents, including the pages Apple now serves from `music.apple.com`, `books.apple.com` and `podcasts.apple.com`
- Keeps the original buy button (`GET`) of each iOS version: the image slice button on iOS 5 and below, the gradient canvas button on iOS 6 and the flat button on iOS 7
- Draws the iOS 6 buy button in the colors of app pages with a custom color scheme, and falls back to the newer button if it cannot be drawn
- Shows a notice on Store pages that Apple no longer fills for older clients, instead of loading forever
- Patches storefront JavaScript that is incompatible with the older WebKit client
- Restores compatibility with the Store URL bag and its certificate data
- Enables TLS 1.0 through TLS 1.2 for the legacy Store connection path
- Works in the App Store, iTunes Store, iBooks and Podcasts, and restarts them after installation so an update takes effect without a reboot
- As a nice side effect, iCloud sync in iBooks and Podcasts works again

## Requirements

- iOS 3, 5 or 6 (iOS 4 is not working at the moment)
- A jailbroken device

## Installation

Download and install the latest package through Cydia using my repository:

<http://repo.victorlobe.me>

## Building from source

This project uses Theos. The package can be built with:

```sh
make package
```

The project targets armv7 and uses an iOS 6.0 SDK deployment target. Development builds are passed through the deployment pipeline defined in the `Makefile`; release builds can be created with `FINALPACKAGE=1`.

The `Makefile` pins Xcode 26.6 (ld 1267), because the linker in Xcode 27 produces armv7 binaries without lazy binding that crash on iOS 5 and 6. Install it at `/Applications/Xcode 26.6.app` or point `XCODE26_APP` to it.

## How it works

Older Store clients still request Store domains, paths, storefront resources, and TLS settings that no longer match Apple's current service layout. AppStoreFix intercepts those requests at the compatibility boundaries used by the legacy client and makes the smallest required change before the request is sent:

1. Legacy session and storefront URLs are rewritten to compatible endpoints.
2. The `authenticateAccount` URL from the Store URL bag gets the trailing slash that the `authenticate` endpoint now expects.
3. Store search and purchase requests receive the endpoint and header adjustments expected by the service.
4. Legacy storefront bootstrap scripts are redirected or patched before they are returned to the Store apps.
5. The Store URL bag is accepted and passed back to the client in a form the old Store apps understand.
6. SecureTransport is constrained to TLS 1.0 to 1.2 for the legacy connection path.

## Known limitations

- The Top Charts tab in Podcasts won’t work.
- Apple's servers no longer return content for some tabs to older clients. The Audio, Video and Charts tabs in the Podcasts Store show a notice, and the Top Authors tab in the iBooks Store stays empty.

## Changelog

### Version 3

- Added support for the iTunes Store, iBooks and Podcasts
- iCloud sync in iBooks and Podcasts works again
- Fixed Store login with the trailing slash on the `authenticate` endpoint, replacing the `auth.itunes.apple.com` redirect
- Fixed empty app pages
- Added a notice on Store pages Apple sends without content
- Store apps restart after installation so no reboot is needed
- Fixed builds crashing on iOS 5 and 6 when built with Xcode 27

### Version 2

* Fixed login.
* The „Get“ buttons now use the correct style instead of always using the iOS 7 style.
* Added a new Settings screen.
* The Genius tab can now be hidden.

### Version 1

- Initial release

## Credits

Special thanks to Requis, Bag.xml, and nekokawa. Their work on iTunesStoreX and AppStoreFix provided valuable technical reference during development.

Thanks to Pod for the login fix from [NewerStoreLoginFix](https://github.com/Epixx512/NewerStoreLoginFix).

## Author

Made with ❤️ by Victor Lobe

## License

MIT License. Free to use, share, and modify.
