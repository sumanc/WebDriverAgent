/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDebugCommands.h"

#import "FBApplication.h"
#import "FBRouteRequest.h"
#import "FBSession.h"
#import "XCUIApplication+FBHelpers.h"
#import "XCUIElement+FBUtilities.h"
#import "FBXPath.h"

@implementation FBDebugCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute GET:@"/source"] respondWithTarget:self action:@selector(handleGetSourceCommand:)],
    [[FBRoute GET:@"/source"].withoutSession respondWithTarget:self action:@selector(handleGetSourceCommand:)],
    [[FBRoute GET:@"/attr/:attributes/source"].withoutSession respondWithTarget:self action:@selector(handleGetSourceCommand:)],
    [[FBRoute GET:@"/attr/:attributes/format/:sourceType/source"].withoutSession respondWithTarget:self action:@selector(handleGetSourceCommand:)],
    [[FBRoute GET:@"/wda/accessibleSource"] respondWithTarget:self action:@selector(handleGetAccessibleSourceCommand:)],
    [[FBRoute GET:@"/wda/accessibleSource"].withoutSession respondWithTarget:self action:@selector(handleGetAccessibleSourceCommand:)],
  ];
}


#pragma mark - Commands

static NSString *const SOURCE_FORMAT_XML = @"xml";
static NSString *const SOURCE_FORMAT_JSON = @"json";
static NSString *const SOURCE_FORMAT_DESCRIPTION = @"description";

+ (id<FBResponsePayload>)handleGetSourceCommand:(FBRouteRequest *)request
{
  FBApplication *application = request.session.application ?: [FBApplication fb_activeApplication];
  NSString *attributes = request.parameters[@"attributes"];
  if (attributes != nil) {
    attributes = [attributes stringByReplacingOccurrencesOfString:@":" withString:@" @"];
    attributes = [NSString stringWithFormat:@" @%@ ", attributes];
  }
  NSString *maxCells = request.parameters[@"maxcells"];
  NSInteger maxCellsToReturn = -1;
  if (maxCells != nil) {
    maxCellsToReturn = [maxCells integerValue];
  }
  NSLog(@"%@", maxCells);
  NSLog(@"%@", attributes);
  NSString *sourceType = request.parameters[@"format"] ?: SOURCE_FORMAT_XML;
  id result;
//  int visible = 0;
  if ([sourceType caseInsensitiveCompare:SOURCE_FORMAT_XML] == NSOrderedSame) {
    [application fb_waitUntilSnapshotIsStable];
    result = [FBXPath xmlStringWithSnapshot:application.fb_lastSnapshot query:attributes maxCells:maxCellsToReturn];
  } else if ([sourceType caseInsensitiveCompare:SOURCE_FORMAT_JSON] == NSOrderedSame) {
    result = application.fb_tree;
  } else if ([sourceType caseInsensitiveCompare:SOURCE_FORMAT_DESCRIPTION] == NSOrderedSame) {
    NSMutableArray<NSString *> *childrenDescriptions = [NSMutableArray array];
    for (XCUIElement *child in [application childrenMatchingType:XCUIElementTypeAny].allElementsBoundByIndex) {
//      XCElementSnapshot *elementSnapshot = child.fb_lastSnapshot;
//      NSDictionary *additionalAttrinutes = elementSnapshot.additionalAttributes;
//      NSString *class = [additionalAttrinutes objectForKey:@5004];
//      if ([child elementType] == XCUIElementTypeCell) {
//        if (maxCellsToReturn > 0 && visible++ > maxCellsToReturn) {
//          break;
//        }
//      }
      [childrenDescriptions addObject:child.debugDescription];
    }
    // debugDescription property of XCUIApplication instance shows descendants addresses in memory
    // instead of the actual information about them, however the representation works properly
    // for all descendant elements
    result = (0 == childrenDescriptions.count) ? application.debugDescription : [childrenDescriptions componentsJoinedByString:@"\n\n"];
  } else {
    return FBResponseWithStatus(
      FBCommandStatusUnsupported,
      [NSString stringWithFormat:@"Unknown source format '%@'. Only %@ source formats are supported.",
       sourceType, @[SOURCE_FORMAT_XML, SOURCE_FORMAT_JSON, SOURCE_FORMAT_DESCRIPTION]]
    );
  }
  if (nil == result) {
    return FBResponseWithErrorFormat(@"Cannot get '%@' source of the current application", sourceType);
  }
  return FBResponseWithObject(result);
}

+ (id<FBResponsePayload>)handleGetAccessibleSourceCommand:(FBRouteRequest *)request
{
  FBApplication *application = request.session.application ?: [FBApplication fb_activeApplication];
  return FBResponseWithObject(application.fb_accessibilityTree ?: @{});
}

@end
