/*
 *  Copyright (C) 2026 Team Kodi
 *  This file is part of Kodi - https://kodi.tv
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 *  See LICENSES/README.md for more information.
 */

#import "TVOSExternalApp.h"

#import "utils/log.h"
#include "ServiceBroker.h"
#include "messaging/ApplicationMessenger.h"

#import <UIKit/UIKit.h>

bool CTVOSExternalApp::OpenURL(const std::string& url)
{
  if (url.empty())
    return false;

  NSString* urlString = [NSString stringWithUTF8String:url.c_str()];
  NSURL* nsUrl = [NSURL URLWithString:urlString];
  if (nsUrl == nil)
  {
    CLog::Log(LOGERROR, "CTVOSExternalApp::OpenURL - invalid url");
    return false;
  }

  // DexAetherBridge managed handoff v2.
  // DexHub external handoff: stop Kodi only after successful system launch.
  if ([[nsUrl scheme] isEqualToString:@"dex-external"])
  {
    NSURLComponents* components = [NSURLComponents componentsWithURL:nsUrl resolvingAgainstBaseURL:NO];
    NSURL* target = nil;
    for (NSURLQueryItem* item in components.queryItems)
      if ([item.name isEqualToString:@"target"] && item.value)
        target = [NSURL URLWithString:item.value];
    // v21.3: every external player DexHub can hand a video to
    NSSet* allowed = [NSSet setWithArray:@[@"infuse", @"open-vidhub", @"senplayer", @"vlc-x-callback",
        @"outplayer", @"nplayer-http", @"nplayer-https", @"nativeplayer"]];
    if (!target || ![allowed containsObject:[[target scheme] lowercaseString]])
      return false;
    dispatch_async(dispatch_get_main_queue(), ^{
      [[UIApplication sharedApplication] openURL:target options:@{} completionHandler:^(BOOL success) {
        if (success)
          CServiceBroker::GetAppMessenger()->PostMsg(TMSG_MEDIA_STOP);
        else
        {
          UIViewController* root = [UIApplication sharedApplication].keyWindow.rootViewController;
          while (root.presentedViewController)
            root = root.presentedViewController;
          UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"External player"
              message:@"Unable to open the selected app. Check that it is installed."
              preferredStyle:UIAlertControllerStyleAlert];
          [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
          [root presentViewController:alert animated:YES completion:nil];
        }
      }];
    });
    return true;
  }

  // openURL must run on the main thread
  dispatch_async(dispatch_get_main_queue(), ^{
    UIApplication* application = [UIApplication sharedApplication];
    [application openURL:nsUrl
                    options:@{}
          completionHandler:^(BOOL success) {
            if (success)
              CLog::Log(LOGINFO, "CTVOSExternalApp::OpenURL - launched external app");
            else
              CLog::Log(LOGERROR, "CTVOSExternalApp::OpenURL - open failed (target app not "
                                  "installed or scheme not supported)");
          }];
  });

  return true;
}
