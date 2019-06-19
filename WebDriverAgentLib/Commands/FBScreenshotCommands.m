/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBScreenshotCommands.h"
#import "FBRoute.h"
#import "FBRouteRequest.h"
#import "XCUIDevice+FBHelpers.h"

@implementation FBScreenshotCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute GET:@"/screenshot"].withoutSession respondWithTarget:self action:@selector(handleGetScreenshot:)],
    [[FBRoute GET:@"/screenshotHigh"].withoutSession respondWithTarget:self action:@selector(handleGetScreenshotHigh:)],
    [[FBRoute GET:@"/screenshotHigh2"].withoutSession respondWithTarget:self action:@selector(handleGetScreenshotHigh2:)],
    [[FBRoute GET:@"/screenshotHigh2/quality/:quality"].withoutSession respondWithTarget:self action:@selector(handleGetScreenshotHigh2:)],
    [[FBRoute GET:@"/screenshotHigh2/type/:type"].withoutSession respondWithTarget:self action:@selector(handleGetScreenshotHigh2:)],
    [[FBRoute GET:@"/screenshotHigh2/quality/:quality/type/:type"].withoutSession respondWithTarget:self action:@selector(handleGetScreenshotHigh2:)],
    [[FBRoute GET:@"/screenshot"] respondWithTarget:self action:@selector(handleGetScreenshot:)],
  ];
}


#pragma mark - Commands

+ (id<FBResponsePayload>)handleGetScreenshot:(FBRouteRequest *)request
{
  NSError *error;
  NSData *screenshotData = [[XCUIDevice sharedDevice] fb_screenshotWithError:&error];
  if (nil == screenshotData) {
    return FBResponseWithError(error);
  }
  NSString *screenshot = [screenshotData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
  return FBResponseWithObject(screenshot);
}

+ (id<FBResponsePayload>)handleGetScreenshotHigh:(FBRouteRequest *)request
{
  NSError *error;
  NSData *screenshotData = [[XCUIDevice sharedDevice] fb_screenshotHighWithError:&error quality:1.0 type:@"png"];
  if (nil == screenshotData) {
    return FBResponseWithError(error);
  }
  NSString *screenshot = [screenshotData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
  return FBResponseWithObject(screenshot);
}

+ (id<FBResponsePayload>)handleGetScreenshotHigh2:(FBRouteRequest *)request
{
  NSError *error;
  double quality = [request.parameters[@"quality"] doubleValue];
  NSString *type = request.parameters[@"type"];
  NSLog(@"%f, %@", quality, type);
  if (quality < 0.0 || quality > 1.0) {
    quality = 0.0;
  }
  if (type == nil || ([type caseInsensitiveCompare:@"jpeg"] != NSOrderedSame && [type caseInsensitiveCompare:@"png"] != NSOrderedSame)) {
    type = @"jpeg";
  }
  NSData *screenshotData = [[XCUIDevice sharedDevice] fb_screenshotHighWithError:&error quality:quality type:type];
  if (nil == screenshotData) {
    return FBResponseWithError(error);
  }
  NSString *screenshot = [screenshotData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength];
  return FBResponseWithObject(screenshot);
}

@end
