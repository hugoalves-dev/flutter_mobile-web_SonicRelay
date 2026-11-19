/// Selects the LAN platform for the build (dotnet_SonicRelay#75): `dart:io`
/// and bonsoir on Android/iOS, an unsupported stub in the browser. Import this
/// barrel, never either implementation, so the web build carries no `dart:io`.
library;

export 'io_lan_platform.dart'
    if (dart.library.js_interop) 'web_lan_platform.dart'
    show createLanPlatform;
