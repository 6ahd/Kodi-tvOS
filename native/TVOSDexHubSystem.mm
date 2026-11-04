// SPDX-License-Identifier: GPL-2.0-or-later
// DexHub v21.43: Picture in Picture, Top Shelf and Apple TV users for Kodi.
#include "TVOSDexHubSystem.h"

#include "ServiceBroker.h"
#include "TVOSAetherPlayer.h"
#include "dialogs/GUIDialogKaiToast.h"
#include "filesystem/SpecialProtocol.h"
#include "messaging/ApplicationMessenger.h"
#include "platform/darwin/ios-common/DarwinEmbedUtils.h"
#include "profiles/ProfileManager.h"
#include "settings/SettingsComponent.h"
#include "utils/StringUtils.h"
#include "utils/log.h"

#import "TVOSTopShelf.h"
#import "tvosShared.h"

#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>

#include <dlfcn.h>

namespace
{
NSString* const FeedKey = @"DexHubTopShelfFeed";       // main app: id -> path
NSString* const SharedKey = @"dexhubTopShelf";         // app group: what the shelf shows
NSString* const UsersKey = @"DexHubAppleTVUsers";      // Apple TV user -> Kodi profile
const NSUInteger MaxSections = 4;
const NSUInteger MaxItems = 12;

NSString* NS(const std::string& value) { return [NSString stringWithUTF8String:value.c_str()] ?: @""; }
std::string Str(NSString* value) { return value ? std::string(value.UTF8String) : std::string(); }

NSString* Digest(NSString* value)
{
  NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding];
  unsigned char hash[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, static_cast<CC_LONG>(data.length), hash);
  NSMutableString* text = [NSMutableString stringWithCapacity:24];
  for (int i = 0; i < 12; ++i)
    [text appendFormat:@"%02x", hash[i]];
  return text;
}

bool LoadTVServices()
{
  // The main app does not link TVServices; the Top Shelf extension does.
  static void* handle = dlopen("/System/Library/Frameworks/TVServices.framework/TVServices", RTLD_LAZY);
  return handle != nullptr;
}

bool AllowedPath(NSString* path)
{
  // Only items an add-on can list itself: no builtins, no arbitrary URLs.
  return [path hasPrefix:@"plugin://"] || [path hasPrefix:@"videodb://"];
}

NSString* Quote(NSString* path)
{
  return NS(StringUtils::Paramify(Str(path)));
}
} // namespace

int DexHubPictureInPicture(const std::vector<std::string>& params)
{
  if (!DexAetherTogglePictureInPicture())
    CLog::Log(LOGINFO, "DexHub: Picture in Picture needs an Aether playback");
  return 0;
}

// ---------------------------------------------------------------- Top Shelf
// The feed (written by plugin.video.dexhub.tvos):
// {"sections": [{"title": "...", "items": [{"title": "...", "path": "plugin://...",
//   "folder": false, "image": "/local/file.jpg", "image_url": "https://...",
//   "shape": "hdtv|poster|square", "progress": 0.42}]}]}
int DexHubTopShelf(const std::vector<std::string>& params)
{
  @autoreleasepool
  {
    if (!params.empty() && !params[0].empty())
    {
      NSString* file = NS(CSpecialProtocol::TranslatePath(params[0]));
      NSData* data = [NSData dataWithContentsOfFile:file];
      id feed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
      if (![feed isKindOfClass:[NSDictionary class]] || ![feed[@"sections"] isKindOfClass:[NSArray class]])
      {
        CLog::Log(LOGWARNING, "DexHub Top Shelf: unreadable feed {}", Str(file));
        return -1;
      }

      const bool sandboxed = CDarwinEmbedUtils::IsIosSandboxed();
      NSURL* sharedRoot = [tvosShared getSharedURL];
      NSURL* imageRoot = sharedRoot ? [sharedRoot URLByAppendingPathComponent:@"DexHub" isDirectory:YES] : nil;
      NSFileManager* files = NSFileManager.defaultManager;
      if (imageRoot)
        [files createDirectoryAtURL:imageRoot withIntermediateDirectories:YES attributes:nil error:nil];
      else
        CLog::Log(LOGWARNING, "DexHub Top Shelf: no app group container ({}); the signed app needs "
                              "the application group entitlement for the Top Shelf",
                  Str([tvosShared getSharedID]));

      NSMutableDictionary* paths = [NSMutableDictionary dictionary];
      NSMutableSet* keepImages = [NSMutableSet set];
      NSMutableArray* sections = [NSMutableArray array];
      for (NSDictionary* section in feed[@"sections"])
      {
        if (![section isKindOfClass:[NSDictionary class]] || ![section[@"items"] isKindOfClass:[NSArray class]])
          continue;
        NSMutableArray* items = [NSMutableArray array];
        for (NSDictionary* row in section[@"items"])
        {
          if (![row isKindOfClass:[NSDictionary class]] || ![row[@"path"] isKindOfClass:[NSString class]])
            continue;
          NSString* path = row[@"path"];
          if (!AllowedPath(path))
            continue;
          NSString* identifier = Digest(path);
          paths[identifier] = @{@"path": path, @"folder": @([row[@"folder"] boolValue])};
          NSMutableDictionary* item = [NSMutableDictionary dictionary];
          item[@"id"] = identifier;
          item[@"title"] = [row[@"title"] isKindOfClass:[NSString class]] ? row[@"title"] : @"";
          item[@"shape"] = [row[@"shape"] isKindOfClass:[NSString class]] ? row[@"shape"] : @"hdtv";
          const double progress = [row[@"progress"] isKindOfClass:[NSNumber class]] ? [row[@"progress"] doubleValue] : 0;
          if (progress > 0 && progress < 1)
            item[@"progress"] = @(progress);
          // A local copy in the app group; the extension cannot read Kodi's folders.
          NSString* image = [row[@"image"] isKindOfClass:[NSString class]] ? row[@"image"] : nil;
          if (image.length && imageRoot)
          {
            NSString* source = NS(CSpecialProtocol::TranslatePath(Str(image)));
            NSString* extension = source.pathExtension.length ? source.pathExtension.lowercaseString : @"jpg";
            NSString* name = [Digest(source) stringByAppendingPathExtension:extension];
            NSURL* target = [imageRoot URLByAppendingPathComponent:name isDirectory:NO];
            if ([files fileExistsAtPath:source] &&
                ([files fileExistsAtPath:target.path] ||
                 [files copyItemAtPath:source toPath:target.path error:nil]))
            {
              item[@"image"] = name;
              [keepImages addObject:name];
            }
          }
          NSString* remote = [row[@"image_url"] isKindOfClass:[NSString class]] ? row[@"image_url"] : nil;
          if (!item[@"image"] && [remote hasPrefix:@"https://"])
            item[@"image_url"] = remote;
          [items addObject:item];
          if (items.count >= MaxItems)
            break;
        }
        if (items.count == 0)
          continue;
        NSString* title = [section[@"title"] isKindOfClass:[NSString class]] ? section[@"title"] : @"";
        [sections addObject:@{@"title": title, @"items": items}];
        if (sections.count >= MaxSections)
          break;
      }

      // Images no longer on the shelf.
      if (imageRoot)
        for (NSString* name in [files contentsOfDirectoryAtPath:imageRoot.path error:nil])
          if (![keepImages containsObject:name])
            [files removeItemAtURL:[imageRoot URLByAppendingPathComponent:name] error:nil];

      [NSUserDefaults.standardUserDefaults setObject:paths forKey:FeedKey];
      NSDictionary* shared = @{@"sections": sections, @"updated": @(NSDate.date.timeIntervalSince1970)};
      if (sandboxed)
      {
        NSUserDefaults* group = [[NSUserDefaults alloc] initWithSuiteName:[tvosShared getSharedID]];
        [group setObject:shared forKey:SharedKey];
      }
      else if (imageRoot)
        [shared writeToURL:[imageRoot URLByAppendingPathComponent:@"topshelf.plist"] atomically:YES];

      if (LoadTVServices())
      {
        Class provider = NSClassFromString(@"TVTopShelfContentProvider");
        SEL changed = NSSelectorFromString(@"topShelfContentDidChange");
        if ([provider respondsToSelector:changed])
          ((void (*)(id, SEL))[provider methodForSelector:changed])(provider, changed);
      }
      CLog::Log(LOGINFO, "DexHub Top Shelf: {} rows published", static_cast<int>(sections.count));
    }
    // A Top Shelf item that launched the app before Kodi was ready: the add-on
    // service calls this once it runs, so the request is not lost on a cold start.
    CTVOSTopShelf::GetInstance().RunTopShelf();
  }
  return 0;
}

bool DexHubRunTopShelfItem(const std::string& action, const std::string& identifier)
{
  @autoreleasepool
  {
    NSDictionary* paths = [NSUserDefaults.standardUserDefaults dictionaryForKey:FeedKey];
    NSDictionary* item = paths[NS(identifier)];
    if (![item isKindOfClass:[NSDictionary class]] || ![item[@"path"] isKindOfClass:[NSString class]] ||
        !AllowedPath(item[@"path"]))
    {
      CLog::Log(LOGINFO, "DexHub Top Shelf: item {} is no longer on the shelf", identifier);
      return false;
    }
    NSString* path = item[@"path"];
    // Both select and Play open the card the way Dex Hub's Continue Watching does.
    NSString* command = [item[@"folder"] boolValue]
        ? [NSString stringWithFormat:@"ActivateWindow(Videos,%@,return)", Quote(path)]
        : [NSString stringWithFormat:@"PlayMedia(%@)", Quote(path)];
    CLog::Log(LOGINFO, "DexHub Top Shelf: {} {}", action, Str(command));
    CServiceBroker::GetAppMessenger()->PostMsg(TMSG_EXECUTE_BUILT_IN, -1, -1, nullptr, Str(command));
    return true;
  }
}

// ---------------------------------------------------------------- Apple TV users
namespace
{
NSString* CurrentAppleTVUser()
{
  // TVUserManager answers only when the signed app carries the
  // com.apple.developer.user-management entitlement (get-current-user).
  if (!LoadTVServices())
    return nil;
  Class manager = NSClassFromString(@"TVUserManager");
  SEL current = NSSelectorFromString(@"currentUserIdentifier");
  id instance = manager ? [[manager alloc] init] : nil;
  if (![instance respondsToSelector:current])
    return nil;
  id value = ((id (*)(id, SEL))[instance methodForSelector:current])(instance, current);
  return [value isKindOfClass:[NSString class]] && [value length] ? value : nil;
}

void Toast(const std::string& text)
{
  CGUIDialogKaiToast::QueueNotification(CGUIDialogKaiToast::Info, "Apple TV", text);
}
} // namespace

int DexHubAppleTVUser(const std::vector<std::string>& params)
{
  @autoreleasepool
  {
    const std::string mode = params.empty() ? "sync" : StringUtils::ToLower(params[0]);
    auto profiles = CServiceBroker::GetSettingsComponent()->GetProfileManager();
    if (!profiles)
      return -1;
    const std::string currentProfile = profiles->GetCurrentProfile().getName();
    NSString* user = CurrentAppleTVUser();
    NSMutableDictionary* links =
        [[NSUserDefaults.standardUserDefaults dictionaryForKey:UsersKey] mutableCopy] ?: [NSMutableDictionary dictionary];

    if (mode == "link" || mode == "unlink")
    {
      if (!user)
      {
        Toast("Apple TV did not say who is watching. The app needs the user-management "
              "entitlement in its signature.");
        return -1;
      }
      if (mode == "link")
        links[user] = NS(currentProfile);
      else
        [links removeObjectForKey:user];
      [NSUserDefaults.standardUserDefaults setObject:links forKey:UsersKey];
      Toast(mode == "link" ? "This Apple TV user now opens the profile " + currentProfile
                           : "This Apple TV user is no longer linked to a profile");
      return 0;
    }

    // sync: open the profile linked to whoever is watching.
    if (!user)
      return 0;
    NSString* linked = links[user];
    if (![linked isKindOfClass:[NSString class]] || Str(linked) == currentProfile)
      return 0;
    if (profiles->GetProfileIndex(Str(linked)) < 0)
    {
      CLog::Log(LOGWARNING, "DexHub: profile {} linked to this Apple TV user is gone", Str(linked));
      return 0;
    }
    CLog::Log(LOGINFO, "DexHub: Apple TV user switch opens profile {}", Str(linked));
    CServiceBroker::GetAppMessenger()->PostMsg(
        TMSG_EXECUTE_BUILT_IN, -1, -1, nullptr,
        "LoadProfile(" + StringUtils::Paramify(Str(linked)) + ",prompt)");
    return 0;
  }
}
