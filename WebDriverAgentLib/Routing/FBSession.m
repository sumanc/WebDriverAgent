/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSession.h"
#import "FBSession-Private.h"

#import <objc/runtime.h>

#import "FBAlertsMonitor.h"
#import "FBAlert.h"
#import "FBLogger.h"
#import "FBApplication.h"
#import "FBElementCache.h"
#import "FBMacros.h"
#import "FBSpringboardApplication.h"
#import "XCAccessibilityElement.h"
#import "XCAXClient_iOS.h"
#import "XCUIElement.h"

NSString *const FBApplicationCrashedException = @"FBApplicationCrashedException";

@interface FBSession ()
@property (nonatomic, strong, readwrite) FBApplication *testedApplication;
@end

@interface FBSession (FBAlertsMonitorDelegate)

- (void)didDetectAlert:(FBAlert *)alert;

@end

@implementation FBSession (FBAlertsMonitorDelegate)

- (void)didDetectAlert:(FBAlert *)alert
{
  if (nil == self.defaultAlertAction) {
    return;
  }
  
  NSError *error;
  if ([self.defaultAlertAction isEqualToString:@"accept"]) {
    if (![alert acceptWithError:&error]) {
      [FBLogger logFmt:@"Cannot accept the alert. Original error: %@", error.description];
    }
  } else if ([self.defaultAlertAction isEqualToString:@"dismiss"]) {
    if (![alert dismissWithError:&error]) {
      [FBLogger logFmt:@"Cannot dismiss the alert. Original error: %@", error.description];
    }
  } else {
    [FBLogger logFmt:@"'%@' default alert action is unsupported", self.defaultAlertAction];
  }
}

@end

@implementation FBSession

static FBSession *_activeSession;
+ (instancetype)activeSession
{
  return _activeSession ?: [FBSession sessionWithApplication:nil];
}

+ (void)markSessionActive:(FBSession *)session
{
  if (_activeSession && _activeSession.testedApplication.bundleID != session.testedApplication.bundleID) {
    [_activeSession kill];
  }
  _activeSession = session;
}

+ (instancetype)sessionWithIdentifier:(NSString *)identifier
{
  if (!identifier) {
    return nil;
  }
  if (![identifier isEqualToString:_activeSession.identifier]) {
    return nil;
  }
  return _activeSession;
}

+ (instancetype)sessionWithApplication:(FBApplication *)application
{
  FBSession *session = [FBSession new];
  session.identifier = [[NSUUID UUID] UUIDString];
  session.testedApplication = application;
  session.elementCache = [FBElementCache new];
  [FBSession markSessionActive:session];
  return session;
}

+ (instancetype)sessionWithApplication:(nullable FBApplication *)application defaultAlertAction:(NSString *)defaultAlertAction
{
  FBSession *session = [self.class sessionWithApplication:application];
  session.alertsMonitor = [[FBAlertsMonitor alloc] init];
  session.alertsMonitor.delegate = (id<FBAlertsMonitorDelegate>)session;
  session.alertsMonitor.application = FBApplication.fb_activeApplication;
  session.defaultAlertAction = [defaultAlertAction lowercaseString];
  [session.alertsMonitor enable];
  return session;
}

- (void)kill
{
  [self.testedApplication terminate];
  _activeSession = nil;
}

- (FBApplication *)application
{
  if (self.testedApplication && !self.testedApplication.running) {
    [[NSException exceptionWithName:FBApplicationCrashedException reason:@"Application is not running, possibly crashed" userInfo:nil] raise];
  }
  return [FBApplication fb_activeApplication] ?: self.testedApplication;
}

@end
