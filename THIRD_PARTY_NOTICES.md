# Third-party notices

This file records external components currently included in the app. Package and asset revisions are pinned where available. Review and expand this notice whenever another library, native binary, emulator core, font, or artwork source is added.

## Readium Swift Toolkit

- Source: [readium/swift-toolkit](https://github.com/readium/swift-toolkit)
- Revision: `e20d5cfc847c2cfa02aaf7be409848b504bd46ca`
- License: BSD 3-Clause
- Copyright: Copyright (c) 2017, Readium

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the copyright notice, conditions, and disclaimer are retained. The Readium name and contributors may not be used to endorse derived products without prior written permission. The software is provided without warranty or liability. The full license is available in the upstream repository's `LICENSE` file.

## Fast-Font Fast Serif

- Source: [Born2Root/Fast-Font](https://github.com/Born2Root/Fast-Font)
- Asset: `fast-fonts/Fast_Serif.ttf`
- License: MIT
- Copyright: Copyright (c) 2023 Born2Root

Permission is granted, free of charge, to any person obtaining a copy of this software and associated documentation files, to deal in the software without restriction, including the rights to use, copy, modify, merge, publish, distribute, sublicense, and sell copies, subject to including this copyright notice and permission notice in substantial portions. The software is provided without warranty or liability. The complete license text is in the upstream repository's `LICENSE` file.

## Jellyfin Swift SDK

- Source: [jellyfin/jellyfin-sdk-swift](https://github.com/jellyfin/jellyfin-sdk-swift)
- Version: `2.0.0` (`185ef233c05bd889dbb9d9fa49ceb34b1dd16b43`)
- License: Mozilla Public License 2.0
- Copyright: Copyright (c) 2026 Jellyfin & Jellyfin Contributors

The SDK is included as the `JellyfinAPI` Swift package product. Version 3.4.0 from the inspected checkout fails to compile with the GitHub runner's Swift compiler because its WebSocket source uses an invalid optional existential spelling (`Error?`). Version 2.0.0 retains the sign-in and item-catalog API surface used by this app and avoids that source error. Reassess the pin when a newer compatible upstream release is available. The full MPL-2.0 text is bundled in `Sources/Resources/ThirdPartyLicenses/Jellyfin-Swift-SDK-MPL-2.0.txt`; retain source availability/notice obligations for covered modifications.

## Other checked-out projects

LocalMusic (MPL-2.0), MPVKit's LGPL/GPL product variants, and RetroArch (GPL-3.0) have been assessed but are not linked into this app target yet. Their licenses and all transitive dependencies must be reviewed before integration or distribution. RetroArch cores are separate projects with separate licenses.
