// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include <string>
#include <vector>

// DexHub v21.43: Apple TV system integration, exposed to the skin and add-ons as
// Kodi builtins (registered in SystemBuiltins.cpp).
//
//   DexHub.PictureInPicture          toggle the Aether Picture in Picture window
//   DexHub.TopShelf(<feed.json>)     publish Dex Hub rows to the Top Shelf and run
//                                    a Top Shelf request that launched the app
//   DexHub.AppleTVUser(sync|link|unlink)
//                                    open the Kodi profile linked to the Apple TV
//                                    user who is watching; link or unlink it
int DexHubPictureInPicture(const std::vector<std::string>& params);
int DexHubTopShelf(const std::vector<std::string>& params);
int DexHubAppleTVUser(const std::vector<std::string>& params);

// Top Shelf requests for Dex Hub items: kodi://play/dexhub/<id> and
// kodi://display/dexhub/<id>. Returns false for any other request.
bool DexHubRunTopShelfItem(const std::string& action, const std::string& identifier);
