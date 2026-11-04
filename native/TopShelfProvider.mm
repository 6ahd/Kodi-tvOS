// SPDX-License-Identifier: GPL-2.0-or-later
// DexHub v21.43: the Top Shelf above Kodi's icon, as in Apple's TV app.
//
// Rows come from the app group (written by the DexHub.TopShelf builtin):
//   dexhubTopShelf       Dex Hub rows (Continue Watching), wide cards with progress
//   topshelfCategories   Kodi's own library rows (CTVOSTopShelf), kept as before
// Selecting a card opens kodi://display/dexhub/<id>, Play opens kodi://play/dexhub/<id>;
// the app looks the id up in its own feed, so the shelf carries no paths.
#import "ServiceProvider.h"

#import "../tvosShared.h"

#include "platform/darwin/ios-common/DarwinEmbedUtils.h"

namespace
{
NSString* KodiScheme()
{
  NSBundle* app = [tvosShared mainAppBundle];
  for (NSDictionary* type in [app objectForInfoDictionaryKey:@"CFBundleURLTypes"])
    if ([type[@"CFBundleURLName"] isEqualToString:app.bundleIdentifier] &&
        [type[@"CFBundleURLSchemes"] count] > 0)
      return type[@"CFBundleURLSchemes"][0];
  return @"kodi";
}

TVTopShelfSectionedItemImageShape Shape(NSString* name)
{
  if ([name isEqualToString:@"poster"])
    return TVTopShelfSectionedItemImageShapePoster;
  if ([name isEqualToString:@"square"])
    return TVTopShelfSectionedItemImageShapeSquare;
  return TVTopShelfSectionedItemImageShapeHDTV;
}

TVTopShelfAction* Action(NSString* scheme, NSString* kind, NSString* path)
{
  NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/%@", scheme, kind, path]];
  return url ? [[TVTopShelfAction alloc] initWithURL:url] : nil;
}

NSDictionary* SharedValue(NSString* key, NSURL* root, NSString* file)
{
  if (CDarwinEmbedUtils::IsIosSandboxed())
    return [[[NSUserDefaults alloc] initWithSuiteName:[tvosShared getSharedID]] dictionaryForKey:key];
  return [NSDictionary dictionaryWithContentsOfURL:[root URLByAppendingPathComponent:file]];
}
} // namespace

@implementation ServiceProvider

- (void)loadTopShelfContentWithCompletionHandler:(void (^)(id<TVTopShelfContent> _Nullable))completionHandler
{
  NSString* scheme = KodiScheme();
  NSURL* root = [tvosShared getSharedURL];
  NSMutableArray<TVTopShelfItemCollection<TVTopShelfSectionedItem*>*>* sections = [NSMutableArray array];

  // Dex Hub rows first.
  NSURL* dexRoot = [root URLByAppendingPathComponent:@"DexHub" isDirectory:YES];
  NSDictionary* dex = SharedValue(@"dexhubTopShelf", dexRoot, @"topshelf.plist");
  for (NSDictionary* section in dex[@"sections"])
  {
    NSMutableArray<TVTopShelfSectionedItem*>* items = [NSMutableArray array];
    for (NSDictionary* row in section[@"items"])
    {
      NSString* identifier = row[@"id"];
      if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0)
        continue;
      TVTopShelfSectionedItem* item = [[TVTopShelfSectionedItem alloc] initWithIdentifier:identifier];
      item.title = row[@"title"];
      item.imageShape = Shape(row[@"shape"]);
      NSURL* image = nil;
      if ([row[@"image"] isKindOfClass:[NSString class]] && dexRoot)
        image = [dexRoot URLByAppendingPathComponent:row[@"image"] isDirectory:NO];
      else if ([row[@"image_url"] isKindOfClass:[NSString class]])
        image = [NSURL URLWithString:row[@"image_url"]];
      if (image)
      {
        [item setImageURL:image forTraits:TVTopShelfItemImageTraitScreenScale1x];
        [item setImageURL:image forTraits:TVTopShelfItemImageTraitScreenScale2x];
      }
      if ([row[@"progress"] isKindOfClass:[NSNumber class]])
        item.playbackProgress = [row[@"progress"] doubleValue];
      item.displayAction = Action(scheme, @"display/dexhub", identifier);
      item.playAction = Action(scheme, @"play/dexhub", identifier);
      [items addObject:item];
    }
    if (items.count == 0)
      continue;
    TVTopShelfItemCollection<TVTopShelfSectionedItem*>* collection =
        [[TVTopShelfItemCollection alloc] initWithItems:items];
    collection.title = section[@"title"];
    [sections addObject:collection];
  }

  // Kodi's own library rows (recently added films and episodes), unchanged data.
  NSURL* kodiRoot = [root URLByAppendingPathComponent:@"RA" isDirectory:YES];
  NSDictionary* categories = SharedValue(@"topshelfCategories", kodiRoot, @"topshelf.dict");
  for (NSString* key in [categories.allKeys sortedArrayUsingSelector:@selector(compare:)])
  {
    NSDictionary* category = categories[key];
    NSURL* thumbs = [kodiRoot URLByAppendingPathComponent:key isDirectory:YES];
    NSMutableArray<TVTopShelfSectionedItem*>* items = [NSMutableArray array];
    NSUInteger index = 0;
    for (NSDictionary* row in category[@"categoryItems"])
    {
      NSString* url = row[@"url"];
      if (![url isKindOfClass:[NSString class]])
        continue;
      NSString* identifier = [NSString stringWithFormat:@"kodi-%@-%lu", key, (unsigned long)index++];
      TVTopShelfSectionedItem* item = [[TVTopShelfSectionedItem alloc] initWithIdentifier:identifier];
      item.title = row[@"title"];
      item.imageShape = TVTopShelfSectionedItemImageShapePoster;
      if ([row[@"thumb"] isKindOfClass:[NSString class]])
        [item setImageURL:[thumbs URLByAppendingPathComponent:row[@"thumb"] isDirectory:NO]
                forTraits:TVTopShelfItemImageTraitScreenScale1x];
      // Kodi's format: base64 of the library path (CTVOSTopShelf::RunTopShelf).
      NSString* encoded = [url stringByAddingPercentEncodingWithAllowedCharacters:
                                   NSCharacterSet.URLPathAllowedCharacterSet];
      item.displayAction = Action(scheme, @"display/movie", encoded);
      item.playAction = Action(scheme, @"play/movie", encoded);
      [items addObject:item];
    }
    if (items.count == 0)
      continue;
    TVTopShelfItemCollection<TVTopShelfSectionedItem*>* collection =
        [[TVTopShelfItemCollection alloc] initWithItems:items];
    collection.title = category[@"categoryTitle"];
    [sections addObject:collection];
  }

  completionHandler(sections.count ? [[TVTopShelfSectionedContent alloc] initWithSections:sections] : nil);
}

@end
