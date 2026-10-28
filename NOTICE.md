# Notices and credits

This repository: build scripts, Kodi source changes (`native/kodi-22.0rc1-dexhub.patch`, `apply_kodi_patch.py`), DexHub artwork (`branding/`) and the Aether bridge (`DexAetherEmbedded.swift`).
© 2026 DexWorld. Licensed under GPL-2.0-or-later (see `LICENSE`).

The app this repository builds combines the parts below. Each keeps its own licence.

| Component | Use | Licence |
|---|---|---|
| [Kodi](https://github.com/xbmc/xbmc) 22.0 RC1 (Piers) | the app | GPL-2.0-or-later. Kodi® is a trademark of the XBMC Foundation; this is an unofficial build |
| [AetherEngine](https://github.com/superuser404notfound/AetherEngine) 7.40.1 | video player | LGPL-3.0 with an App Store / DRM exception (`licenses/AetherEngine-LICENSE.txt`) |
| [FFmpegBuild](https://github.com/superuser404notfound/FFmpegBuild) 3.7.1 | FFmpeg, dav1d, zimg, zvbi frameworks | LGPL-2.1 (`licenses/FFmpegBuild-LICENSE.txt`) |
| [LibDovi](https://github.com/superuser404notfound/LibDovi) 2.1.0 | Dolby Vision RPU | MIT (`licenses/LibDovi-LICENSE.txt`) |
| [LibTrueHD](https://github.com/superuser404notfound/LibTrueHD) 3.0.0 | TrueHD Atmos decoding | MIT (`licenses/LibTrueHD-LICENSE.txt`) |
| [LibDTSX](https://github.com/superuser404notfound/LibDTSX) 3.0.0 | DTS:X decoding (DTSX.framework, a dynamic framework you can replace) | LGPL-3.0-or-later, the `dca` crate being a port of FFmpeg's LGPL decoder (`licenses/LibDTSX-NOTICE.txt`, `licenses/LibDTSX-LGPL-3.0.txt`; also in the app's `Licenses/LibDTSX`) |
| [SMBClient](https://github.com/kishikawakatsumi/SMBClient) 0.3.1 | SMB | MIT |
| TMDb Helper, skinvariables, jurialmunkey module, infotagger (jurialmunkey) | add-ons in `assets/` | GPL-3.0 |
| requests, urllib3, certifi, chardet, idna, six, qrcode, addon.signals | Python modules in `assets/` | their own licences, inside each ZIP |
| Inter Arabic, IBM Plex Sans Arabic, Noto, League Spartan fonts | subtitle and UI fonts | SIL OFL 1.1, licences inside the ZIPs |
| Dex Hub add-on (`src/plugin.video.dexhub.tvos`) | the add-on | proprietary, source available; © DexWorld; see its `LICENSE.txt` and `THIRD-PARTY-NOTICES.txt` |
| Dex Hub skin (`src/skin.dexhub.tvos`) | the skin | built on Estuary (GPL-2.0, artwork CC BY-SA 4.0) and Arctic Fuse 3 by jurialmunkey (CC BY-NC-SA 4.0); see its licence files |

Dolby, Dolby Vision and Dolby Atmos are trademarks of Dolby Laboratories. Apple TV, tvOS and Xcode are trademarks of Apple Inc. Infuse and VidHub belong to their developers. No affiliation is implied.
