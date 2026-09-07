<div align="center">
  <img width="120" height="120" alt="AppStoreFixIcon" src="https://github.com/user-attachments/assets/02ddd78d-0fcd-441d-aede-1d468010853e" />
  <h1>AppStoreFix</h1>
</div>

An iOS tweak that restores App Store functionality on iOS 6 by fixing connectivity, login, and storefront issues.

## What it fixes

- Redirects legacy iTunes Store session requests to the current Store session endpoint
- Rewrites the old authentication request to Apple's native authentication endpoint
- Repairs legacy search requests and the storefront identifier used by older clients
- Adds the missing form content type for older product purchase requests
- Relays older storefront bootstrap resources to their newer equivalents
- Patches storefront JavaScript that is incompatible with the older WebKit client
- Restores compatibility with the Store URL bag and its certificate data
- Enables TLS 1.0 through TLS 1.2 for the legacy Store connection path

## Requirements

- iOS 6.0 through 6.1.6
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

## How it works

Older App Store clients still request Store domains, paths, storefront resources, and TLS settings that no longer match Apple's current service layout. AppStoreFix intercepts those requests at the compatibility boundaries used by the legacy client and makes the smallest required change before the request is sent:

1. Legacy session and storefront URLs are rewritten to compatible endpoints.
2. Authentication query parameters are converted into the property list body expected by the native authentication endpoint.
3. Store search and purchase requests receive the endpoint and header adjustments expected by the service.
4. Legacy storefront bootstrap scripts are redirected or patched before they are returned to the App Store.
5. The Store URL bag is accepted and passed back to the client in a form the old App Store understands.
6. SecureTransport is constrained to TLS 1.0 - 1.2 for the legacy connection path.

## Changelog

### v1.0.0

- Initial release

## Credits

Special thanks to Requis, Bag.xml, and nekokawa. Their work on iTunesStoreX and AppStoreFix provided valuable technical reference during development.

## Author

Made with ❤️ by Victor Lobe

## License

MIT License - Free to use, share, and modify.
