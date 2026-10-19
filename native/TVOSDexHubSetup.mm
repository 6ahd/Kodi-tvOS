// SPDX-License-Identifier: GPL-2.0-or-later
#include "TVOSDexHubSetup.h"
#include "ServiceBroker.h"
#include "addons/AddonManager.h"
#include "addons/AddonVersion.h"
#include "addons/IAddon.h"
#include "platform/darwin/tvos/filesystem/TVOSFileUtils.h"
#include "settings/Settings.h"
#include "settings/SettingsComponent.h"
#include "utils/log.h"
#import <Foundation/Foundation.h>

namespace
{
bool bundleReady = false;
NSString* Home()
{
  return [NSString stringWithUTF8String:CTVOSFileUtils::GetUserHomeDirectory()];
}
NSDictionary* Manifest()
{
  NSString* path = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"AppData/DexHubBundle.json"];
  NSData* data = [NSData dataWithContentsOfFile:path];
  id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
NSString* Pending() { return [Home() stringByAppendingPathComponent:@"dexhub-restore-pending"]; }
NSMutableDictionary* RestoreManifest()
{
  NSData* data = [NSData dataWithContentsOfFile:[Pending() stringByAppendingPathComponent:@"manifest.json"]];
  id value = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
  if (![value isKindOfClass:NSMutableDictionary.class] || ![value[@"format"] isEqual:@"dexhub_full_backup"] || [value[@"version"] intValue] != 1) return nil;
  NSSet* allowed = [NSSet setWithArray:@[@"plugin.video.dexhub.tvos", @"skin.dexhub.tvos", @"script.dexhub.tvos.players", @"plugin.video.themoviedb.helper", @"script.skinvariables"]];
  if (![value[@"roots"] isKindOfClass:NSArray.class]) return nil;
  for (NSString* identifier in value[@"roots"]) if (![allowed containsObject:identifier]) return nil;
  return value;
}
void PrepareRestore()
{
  NSMutableDictionary* manifest = RestoreManifest();
  if (!manifest || [manifest[@"prepared"] boolValue]) return;
  NSFileManager* files = NSFileManager.defaultManager;
  NSString* dataRoot = [Home() stringByAppendingPathComponent:@"userdata/addon_data"];
  NSString* backups = [Home() stringByAppendingPathComponent:[@"dexhub-restore-backups/" stringByAppendingString:NSUUID.UUID.UUIDString]];
  [files createDirectoryAtPath:dataRoot withIntermediateDirectories:YES attributes:nil error:nil];
  [files createDirectoryAtPath:backups withIntermediateDirectories:YES attributes:nil error:nil];
  NSMutableArray* changed = [NSMutableArray array];
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  NSMutableDictionary* oldDefaults = [NSMutableDictionary dictionary];
  NSMutableArray* prefixes = [NSMutableArray array];
  for (NSString* identifier in manifest[@"roots"])
    [prefixes addObject:[NSString stringWithFormat:@"/userdata/addon_data/%@/", identifier]];
  for (NSString* key in defaults.dictionaryRepresentation)
    for (NSString* prefix in prefixes)
      if ([key hasPrefix:prefix]) oldDefaults[key] = [defaults objectForKey:key];
  NSData* oldData = [NSPropertyListSerialization dataWithPropertyList:oldDefaults format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
  if (!oldData || ![oldData writeToFile:[backups stringByAppendingPathComponent:@"NSUserDefaults.plist"] options:NSDataWritingAtomic error:nil])
  { CLog::Log(LOGERROR, "DexHub restore: unable to back up persistent XML"); return; }
  bool success = true;
  for (NSString* identifier in manifest[@"roots"])
  {
    NSString* source = [[Pending() stringByAppendingPathComponent:@"profiles"] stringByAppendingPathComponent:identifier];
    NSString* destination = [dataRoot stringByAppendingPathComponent:identifier];
    NSString* previous = [backups stringByAppendingPathComponent:identifier];
    NSString* temporary = [dataRoot stringByAppendingPathComponent:[@".restore-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    BOOL hadPrevious = [files fileExistsAtPath:destination];
    if (![files copyItemAtPath:source toPath:temporary error:nil]) { success = false; break; }
    if (hadPrevious && ![files moveItemAtPath:destination toPath:previous error:nil])
    { [files removeItemAtPath:temporary error:nil]; success = false; break; }
    if (![files moveItemAtPath:temporary toPath:destination error:nil])
    {
      if (hadPrevious) [files moveItemAtPath:previous toPath:destination error:nil];
      [files removeItemAtPath:temporary error:nil]; success = false; break;
    }
    [changed addObject:@{@"destination":destination, @"previous":previous, @"hadPrevious":@(hadPrevious)}];
  }
  if (success)
  {
    for (NSString* key in oldDefaults) [defaults removeObjectForKey:key];
    for (NSString* name in manifest[@"files"])
    {
      if (![name hasPrefix:@"profiles/"] || ![name.pathExtension.lowercaseString isEqual:@"xml"]) continue;
      NSString* relative = [name substringFromIndex:9];
      NSData* xml = [NSData dataWithContentsOfFile:[Pending() stringByAppendingPathComponent:name]];
      if (!xml) { success = false; break; }
      [defaults setObject:xml forKey:[@"/userdata/addon_data/" stringByAppendingString:relative]];
    }
    success = success && [defaults synchronize];
  }
  if (success)
  {
    manifest[@"prepared"] = @YES;
    NSData* data = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil];
    success = data && [data writeToFile:[Pending() stringByAppendingPathComponent:@"manifest.json"] options:NSDataWritingAtomic error:nil];
  }
  if (!success)
  {
    for (NSString* key in defaults.dictionaryRepresentation)
      for (NSString* prefix in prefixes)
        if ([key hasPrefix:prefix]) [defaults removeObjectForKey:key];
    for (NSString* key in oldDefaults) [defaults setObject:oldDefaults[key] forKey:key];
    [defaults synchronize];
    for (NSDictionary* item in changed.reverseObjectEnumerator)
    {
      [files removeItemAtPath:item[@"destination"] error:nil];
      if ([item[@"hadPrevious"] boolValue]) [files moveItemAtPath:item[@"previous"] toPath:item[@"destination"] error:nil];
    }
    CLog::Log(LOGERROR, "DexHub restore: preparation failed; previous profiles restored");
  }
}
void FinishRestore(ADDON::CAddonMgr& manager)
{
  NSDictionary* manifest = RestoreManifest();
  if (!manifest || ![manifest[@"prepared"] boolValue]) return;
  bool success = true;
  for (NSString* identifier in manifest[@"roots"])
  {
    ADDON::AddonPtr addon;
    if (!manager.GetAddon(identifier.UTF8String, addon, ADDON::OnlyEnabled::CHOICE_NO)) { success = false; continue; }
    NSDictionary* values = manifest[@"settings"][identifier];
    // Skin strings/bools have their own XML schema, already restored before loading.
    if ([identifier isEqual:@"skin.dexhub.tvos"]) continue;
    for (NSString* key in values)
      addon->UpdateSetting(key.UTF8String, [values[key] UTF8String]);
    if (values.count && !addon->SaveSettings()) success = false;
  }
  NSFileManager* files = NSFileManager.defaultManager;
  NSString* fonts = [Home() stringByAppendingPathComponent:@"media/Fonts"];
  NSString* source = [Pending() stringByAppendingPathComponent:@"fonts"];
  [files createDirectoryAtPath:fonts withIntermediateDirectories:YES attributes:nil error:nil];
  for (NSString* name in [files contentsOfDirectoryAtPath:source error:nil])
  {
    NSString* destination = [fonts stringByAppendingPathComponent:name];
    if (![files fileExistsAtPath:destination] && ![files copyItemAtPath:[source stringByAppendingPathComponent:name] toPath:destination error:nil]) success = false;
  }
  NSData* core = [NSJSONSerialization dataWithJSONObject:manifest[@"core"] ?: @{} options:0 error:nil];
  if (!core || ![core writeToFile:[Home() stringByAppendingPathComponent:@"dexhub-restored-core.json"] options:NSDataWritingAtomic error:nil]) success = false;
  if (success)
  {
    [files removeItemAtPath:Pending() error:nil];
    CLog::Log(LOGINFO, "DexHub restore: addon profiles and settings restored");
  }
  else CLog::Log(LOGERROR, "DexHub restore: settings incomplete; will retry at next startup");
}
NSString* Version(NSString* path)
{
  NSString* xml = [NSString stringWithContentsOfFile:[path stringByAppendingPathComponent:@"addon.xml"] encoding:NSUTF8StringEncoding error:nil];
  if (!xml) return nil;
  NSRegularExpression* pattern = [NSRegularExpression regularExpressionWithPattern:@"<addon\\s[^>]*\\bversion=[\"']([^\"']+)[\"']" options:0 error:nil];
  NSTextCheckingResult* match = [pattern firstMatchInString:xml options:0 range:NSMakeRange(0, xml.length)];
  return match ? [xml substringWithRange:[match rangeAtIndex:1]] : nil;
}
}

void PrepareDexHubBundle()
{
  @autoreleasepool
  {
    PrepareRestore();
    NSDictionary* manifest = Manifest();
    NSFileManager* files = NSFileManager.defaultManager;
    NSString* bundled = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"AppData/AppHome/addons"];
    NSString* addons = [Home() stringByAppendingPathComponent:@"addons"];
    [files createDirectoryAtPath:addons withIntermediateDirectories:YES attributes:nil error:nil];
    NSString* backups = [Home() stringByAppendingPathComponent:@"dexhub-addon-backups"];
    for (NSDictionary* entry in manifest[@"addons"])
    {
      NSString* identifier = entry[@"id"];
      NSString* version = entry[@"version"];
      if (![identifier isKindOfClass:NSString.class] || [identifier containsString:@"/"] || ![version isKindOfClass:NSString.class]) continue;
      NSString* source = [bundled stringByAppendingPathComponent:identifier];
      NSString* destination = [addons stringByAppendingPathComponent:identifier];
      NSString* installed = Version(destination);
      if (installed && ADDON::CAddonVersion(installed.UTF8String) >= ADDON::CAddonVersion(version.UTF8String)) continue;
      NSString* temporary = [addons stringByAppendingPathComponent:[@".dexhub-" stringByAppendingString:NSUUID.UUID.UUIDString]];
      NSError* error = nil;
      if (![files copyItemAtPath:source toPath:temporary error:&error])
      {
        CLog::Log(LOGERROR, "DexHub setup: unable to stage {} (error {})", identifier.UTF8String, error.code);
        continue;
      }
      NSString* previous = nil;
      if ([files fileExistsAtPath:destination])
      {
        [files createDirectoryAtPath:backups withIntermediateDirectories:YES attributes:nil error:nil];
        previous = [backups stringByAppendingPathComponent:[identifier stringByAppendingFormat:@"-%@", NSUUID.UUID.UUIDString]];
        if (![files moveItemAtPath:destination toPath:previous error:&error])
        {
          [files removeItemAtPath:temporary error:nil];
          CLog::Log(LOGERROR, "DexHub setup: unable to back up {}", identifier.UTF8String);
          continue;
        }
      }
      if (![files moveItemAtPath:temporary toPath:destination error:&error])
      {
        if (previous) [files moveItemAtPath:previous toPath:destination error:nil];
        [files removeItemAtPath:temporary error:nil];
        CLog::Log(LOGERROR, "DexHub setup: unable to install {}", identifier.UTF8String);
      }
      else CLog::Log(LOGINFO, "DexHub setup: installed {} {}", identifier.UTF8String, version.UTF8String);
    }
    NSString* fonts = [Home() stringByAppendingPathComponent:@"media/Fonts"];
    NSString* fontSource = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"AppData/DexHubFonts"];
    [files createDirectoryAtPath:fonts withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString* name in [files contentsOfDirectoryAtPath:fontSource error:nil])
    {
      NSString* destination = [fonts stringByAppendingPathComponent:name];
      if (![files fileExistsAtPath:destination])
      {
        NSError* error = nil;
        if (![files copyItemAtPath:[fontSource stringByAppendingPathComponent:name] toPath:destination error:&error])
          CLog::Log(LOGERROR, "DexHub setup: unable to copy font {}", name.UTF8String);
      }
    }
  }
}

void ActivateDexHubBundle(ADDON::CAddonMgr& manager)
{
  @autoreleasepool
  {
    FinishRestore(manager);
    NSDictionary* manifest = Manifest();
    bool success = manifest != nil;
    for (NSDictionary* entry in manifest[@"addons"])
    {
      NSString* identifier = entry[@"id"];
      const std::string id = identifier.UTF8String;
      if (!manager.EnableAddon(id) || manager.IsAddonDisabled(id))
      {
        success = false;
        CLog::Log(LOGERROR, "DexHub setup: {} could not be enabled", id);
      }
    }
    ADDON::AddonPtr repository;
    const std::string repositoryId = "repository.dexworld.appletv";
    if (manager.GetAddon(repositoryId, repository, ADDON::OnlyEnabled::CHOICE_YES))
    {
      for (const std::string id : {"plugin.video.dexhub.tvos", "skin.dexhub.tvos",
                                   "script.dexhub.tvos.players"})
      {
        ADDON::AddonPtr addon;
        if (!manager.GetAddon(id, addon, ADDON::OnlyEnabled::CHOICE_NO))
          continue;
        const std::string origin = addon->Origin();
        if (origin.empty() || origin == "repository.dexhub" || origin == ADDON::ORIGIN_SYSTEM)
          manager.SetAddonOrigin(id, repositoryId, false);
      }
    }
    bundleReady = success;
  }
}

void ConfigureDexHubSkin()
{
  @autoreleasepool
  {
    if (!bundleReady || !CServiceBroker::GetGUI())
      return;
    NSString* key = @"DexHubDefaultSkinConfigured-v13";
    if (![NSUserDefaults.standardUserDefaults boolForKey:key])
    {
      auto settings = CServiceBroker::GetSettingsComponent()->GetSettings();
      if (settings->SetString("lookandfeel.skin", "skin.dexhub.tvos"))
      {
        settings->SetInt("general.addonupdates", 0);
        if (settings->Save())
        {
          [NSUserDefaults.standardUserDefaults setBool:YES forKey:key];
          CLog::Log(LOGINFO, "DexHub startup fix v16: default skin configured after GUI initialization");
        }
      }
    }
  }
}
