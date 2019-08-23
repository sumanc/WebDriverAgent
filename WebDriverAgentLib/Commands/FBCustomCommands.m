/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCustomCommands.h"

#import <XCTest/XCUIDevice.h>

#import "FBApplication.h"
#import "FBConfiguration.h"
#import "FBFindElementCommands.h"
#import "FBExceptionHandler.h"
#import "FBKeyboard.h"
#import "FBResponsePayload.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "FBRunLoopSpinner.h"
#import "FBSession.h"
#import "FBXCodeCompatibility.h"
#import "FBSpringboardApplication.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIDevice+FBHelpers.h"
#import "XCUIElement.h"
#import "XCUIElement+FBIsVisible.h"
#import "XCUIElementQuery.h"
#import "SocketRocket.h"

@implementation FBCustomCommands

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute POST:@"/timeouts"] respondWithTarget:self action:@selector(handleTimeouts:)],
    [[FBRoute GET:@"/bundleid/:bundleId/appState"].withoutSession respondWithTarget:self action:@selector(handleAppState:)],
    [[FBRoute POST:@"/wda/homescreen"].withoutSession respondWithTarget:self action:@selector(handleHomescreenCommand:)],
    [[FBRoute POST:@"/wda/deactivateApp"] respondWithTarget:self action:@selector(handleDeactivateAppCommand:)],
    [[FBRoute POST:@"/wda/keyboard/dismiss"] respondWithTarget:self action:@selector(handleDismissKeyboardCommand:)],
    [[FBRoute GET:@"/wda/keyboard/present"] respondWithTarget:self action:@selector(handleKeyboardPresent:)],
    [[FBRoute GET:@"/wda/elementCache/size"] respondWithTarget:self action:@selector(handleGetElementCacheSizeCommand:)],
    [[FBRoute POST:@"/wda/elementCache/clear"] respondWithTarget:self action:@selector(handleClearElementCacheCommand:)],
    [[FBRoute POST:@"/wda/quiescence"] respondWithTarget:self action:@selector(handleQuiescence:)],
    [[FBRoute POST:@"/wda/resetLocation"].withoutSession respondWithTarget:self action:@selector(handleResetLocationCommand:)],
    [[FBRoute POST:@"/screenCast"].withoutSession respondWithTarget:self action:@selector(handleScreenCast:)],
    [[FBRoute POST:@"/stopScreenCast"].withoutSession respondWithTarget:self action:@selector(handleStopScreenCast:)],
  ];
}


#pragma mark - Commands

+ (id<FBResponsePayload>)handleHomescreenCommand:(FBRouteRequest *)request
{
  NSError *error;
  if (![[XCUIDevice sharedDevice] fb_goToHomescreenWithError:&error]) {
    return FBResponseWithError(error);
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleDeactivateAppCommand:(FBRouteRequest *)request
{
  NSNumber *requestedDuration = request.arguments[@"duration"];
  NSTimeInterval duration = (requestedDuration ? requestedDuration.doubleValue : 3.);
  NSError *error;
  if (![request.session.application fb_deactivateWithDuration:duration error:&error]) {
    return FBResponseWithError(error);
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleTimeouts:(FBRouteRequest *)request
{
  // This method is intentionally not supported.
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleAppState:(FBRouteRequest *)request
{
  NSString *bundleId = request.parameters[@"bundleId"];
  XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:bundleId];
  XCUIApplicationState state = app.state;
  return FBResponseWithStatus(FBCommandStatusNoError, @(state));
}

+ (id<FBResponsePayload>)handleDismissKeyboardCommand:(FBRouteRequest *)request
{
  [request.session.application dismissKeyboard];
  NSError *error;
  NSString *errorDescription = @"The keyboard cannot be dismissed. Try to dismiss it in the way supported by your application under test.";
  if ([UIDevice.currentDevice userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
    errorDescription = @"The keyboard on iPhone cannot be dismissed because of a known XCTest issue. Try to dismiss it in the way supported by your application under test.";
  }
  BOOL isKeyboardNotPresent =
  [[[[FBRunLoopSpinner new]
     timeout:5]
    timeoutErrorMessage:errorDescription]
   spinUntilTrue:^BOOL{
     XCUIElement *foundKeyboard = [[FBApplication fb_activeApplication].query descendantsMatchingType:XCUIElementTypeKeyboard].fb_firstMatch;
     return !(foundKeyboard && foundKeyboard.fb_isVisible);
   }
   error:&error];
  if (!isKeyboardNotPresent) {
    return FBResponseWithError(error);
  }
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleKeyboardPresent:(FBRouteRequest *)request
{
  XCUIElementQuery *keyboards = [request.session.application keyboards];
  if (keyboards == nil) {
    return FBResponseWithObject(@NO);
  }
  NSArray *kb = [keyboards allElementsBoundByIndex];
  if (kb == nil || kb.count == 0) {
    return FBResponseWithObject(@NO);
  }
  return FBResponseWithObject(@YES);
}

+ (id<FBResponsePayload>)handleGetElementCacheSizeCommand:(FBRouteRequest *)request
{
  NSNumber *count = [NSNumber numberWithUnsignedInteger:[request.session.elementCache count]];
  return FBResponseWithObject(count);
}

+ (id<FBResponsePayload>)handleClearElementCacheCommand:(FBRouteRequest *)request
{
  FBElementCache *elementCache = request.session.elementCache;
  [elementCache clear];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleQuiescence:(FBRouteRequest *)request
{
  FBApplication *application = [FBApplication fb_activeApplication];
//  BOOL idleAnimations = [application isIdleAnimationWaitEnabled];
//  [application setIdleAnimationWaitEnabled:NO];
  [application _waitForQuiescence];
//  [application setIdleAnimationWaitEnabled:idleAnimations];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleResetLocationCommand:(FBRouteRequest *)request
{
  XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier: @"com.apple.Preferences"];
  [app activate];

  if ([self tap:@"Reset Location & Privacy" app:app]) {
    if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ) {
      [self tapButton:@"Reset" element:@"Reset Warnings" app:app];
    }
    else {
      [self tap:@"Reset Warnings" app:app];
    }
  }
  else {
    [self tap:@"General" app:app];
    [self tap:@"Reset" app:app];
    [self tap:@"Reset Location & Privacy" app:app];
    if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ) {
      [self tapButton:@"Reset" element:@"Reset Warnings" app:app];
    }
    else {
      [self tap:@"Reset Warnings" app:app];
    }
  }
  return FBResponseWithOK();
}

+ (BOOL)tap:(NSString *)name app:(XCUIApplication *)app {
  NSArray *elements = [FBFindElementCommands elementsUsing:@"id" withValue:name under:app shouldReturnAfterFirstMatch:NO];
  if (elements.count > 0) {
    XCUIElement *element = elements[0];
    return [element fb_tapWithError:nil];
  }
  return NO;
}

+ (BOOL)tapButton:(NSString *)name element:(NSString *)element app:(XCUIApplication *)app {
  NSArray *elements = [FBFindElementCommands elementsUsing:@"id" withValue:element under:app shouldReturnAfterFirstMatch:NO];
  if (elements.count > 0) {
    NSArray *buttons = [elements[0] buttons].allElementsBoundByIndex;
    for (XCUIElement *button in buttons) {
      NSString *label = button.label;
      if ([label caseInsensitiveCompare:name] == NSOrderedSame) {
        [button tap];
        return YES;
      }
    }
  }
  return NO;
}

static NSTimer *kTimer = nil;
static SRWebSocket *kSRWebSocket;
static NSData *kLastImageData;

+ (id<FBResponsePayload>)handleScreenCast:(FBRouteRequest *)request
{
  NSInteger fps = [request.arguments[@"fps"] integerValue];
  NSString *url = request.arguments[@"url"];

  if (fps <= 0) {
    fps = 10;
  }
  if (url == nil) {
      return FBResponseWithObject(@"Missing URL");
  }
  
  if (kTimer != nil) {
    [kTimer invalidate];
  }
  if (kSRWebSocket != nil) {
    [kSRWebSocket close];
  }
  
  NSURL *nsURL = [NSURL URLWithString:url];
  kSRWebSocket = [[SRWebSocket alloc] initWithURL:nsURL securityPolicy:[SRSecurityPolicy defaultPolicy]];
  [kSRWebSocket open];
  kTimer = [NSTimer scheduledTimerWithTimeInterval:1/fps target:self selector:@selector(performScreenCast:) userInfo:nil repeats:YES];
  return FBResponseWithOK();
}

+ (id<FBResponsePayload>)handleStopScreenCast:(FBRouteRequest *)request
{
  if (kTimer != nil) {
    [kTimer invalidate];
    kTimer = nil;
  }
  if (kSRWebSocket != nil) {
    [kSRWebSocket close];
  }
  kLastImageData = nil;
  return FBResponseWithOK();
}

+ (void)performScreenCast:(NSTimer*)timer {
//  dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
    NSError *error = nil;
  NSData *screenshotData = [[XCUIDevice sharedDevice] fb_screenshotHighWithError:&error quality:0.0 type:@"jpeg"];
    if (screenshotData != nil && error == nil) {
      if ([kLastImageData isEqualToData:screenshotData]) {
        return;
      }
      kLastImageData = screenshotData;
      [kSRWebSocket sendData:screenshotData error:&error];
      if (error) {
        NSLog(@"Error sending screenshot: %@", error);
      }
      else {
        //log the time it took to transport
      }
    }
    else {
      NSLog(@"Error taking screenshot: %@", error == nil ? @"Unknown error" : error);
    }
//  });
}

@end
