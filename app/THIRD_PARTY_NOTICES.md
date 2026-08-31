# Third-party notices

## Humation engine and humation-1 assets

Keepers uses the Humation engine and the bundled `humation-1` asset pack for
deterministic local avatars. The official engine and artwork are licensed under
the MIT License. Source: https://github.com/humation-labs/humation

Copyright (c) Humation Labs

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Bluetooth Low Energy packages

Keepers uses [`flutter_ble_peripheral` 3.1.0](https://pub.dev/packages/flutter_ble_peripheral)
under the BSD 3-Clause License to advertise an ephemeral waiting-room service
UUID. The upstream 3.1.0 runtime is vendored in
`packages/flutter_ble_peripheral` with local Android and Darwin lifecycle,
failure-handling, and privacy hardening. Its original `LICENSE` is retained in
that directory, and upstream source is available from the
[`flutter_ble_peripheral` repository](https://github.com/juliansteenbakker/flutter_ble_peripheral).

Keepers uses [`flutter_blue_plus` 2.3.12](https://pub.dev/packages/flutter_blue_plus)
to scan for those UUIDs. Version 2.x is distributed under the
[FlutterBluePlus License 1.5](https://pub.dev/packages/flutter_blue_plus/license),
which requires a paid commercial license for development or use by or for a
for-profit organization. Commercial builds must not be distributed until the
appropriate license has been purchased and recorded. Its source is available
from the [`flutter_blue_plus` repository](https://github.com/chipweinberger/flutter_blue_plus).

## humation_flutter community Flutter port

Keepers uses `humation_flutter` 0.1.0, the community Flutter port by Hark
Singh. It is licensed under the MIT License. Source:
https://github.com/0xharkirat/humation_flutter

Copyright (c) 2026 Humation Flutter contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
