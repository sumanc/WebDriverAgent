/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBWebServer.h"

#import <RoutingHTTPServer/RoutingConnection.h>
#import <RoutingHTTPServer/RoutingHTTPServer.h>

#import "FBCommandHandler.h"
#import "FBErrorBuilder.h"
#import "FBExceptionHandler.h"
#import "FBRouteRequest.h"
#import "FBRuntimeUtils.h"
#import "FBSession.h"
#import "FBUnknownCommands.h"
#import "FBConfiguration.h"
#import "FBLogger.h"
#import "FBApplication.h"

#import "XCUIDevice+FBHelpers.h"
#import "BSWDataModelHandler.h"

static NSString *const FBServerURLBeginMarker = @"ServerURLHere->";
static NSString *const FBServerURLEndMarker = @"<-ServerURLHere";

@interface FBHTTPConnection : RoutingConnection
@end

@implementation FBHTTPConnection

- (void)handleResourceNotFound
{
  [FBLogger logFmt:@"Received request for %@ which we do not handle", self.requestURI];
  [super handleResourceNotFound];
}

@end


@interface FBWebServer ()
@property (nonatomic, strong) FBExceptionHandler *exceptionHandler;
@property (nonatomic, strong) RoutingHTTPServer *server;
@property (atomic, assign) BOOL keepAlive;
@property (nonatomic, strong) PSWebSocketServer *wsServer;
@property (atomic, assign) NSInteger wsPort;
@property (nonatomic, strong) PSWebSocket *wsSocket;
@property (atomic, assign) NSInteger fps;
@property (atomic, assign) NSInteger quality;
@property (nonatomic, strong) NSTimer *scTimer;
@property (nonatomic, strong) NSData *lastImageData;
@end

@implementation FBWebServer

+ (NSArray<Class<FBCommandHandler>> *)collectCommandHandlerClasses
{
  NSArray *handlersClasses = FBClassesThatConformsToProtocol(@protocol(FBCommandHandler));
  NSMutableArray *handlers = [NSMutableArray array];
  for (Class aClass in handlersClasses) {
    if ([aClass respondsToSelector:@selector(shouldRegisterAutomatically)]) {
      if (![aClass shouldRegisterAutomatically]) {
        continue;
      }
    }
    [handlers addObject:aClass];
  }
  return handlers.copy;
}

- (void)startServing
{
  [FBLogger logFmt:@"Built at %s %s", __DATE__, __TIME__];
  self.exceptionHandler = [FBExceptionHandler new];
  [self startHTTPServer];

  self.keepAlive = YES;
  NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
  while (self.keepAlive &&
         [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
}

- (void)startHTTPServer
{
  self.server = [[RoutingHTTPServer alloc] init];
  [self.server setRouteQueue:dispatch_get_main_queue()];
  [self.server setDefaultHeader:@"Server" value:@"WebDriverAgent/1.0"];
  [self.server setConnectionClass:[FBHTTPConnection self]];

  [self registerRouteHandlers:[self.class collectCommandHandlerClasses]];
  [self registerServerKeyRouteHandlers];

  NSRange serverPortRange = FBConfiguration.bindingPortRange;
  NSError *error;
  BOOL serverStarted = NO;

  for (NSUInteger index = 0; index < serverPortRange.length; index++) {
    NSInteger port = serverPortRange.location + index;
    [self.server setPort:(UInt16)port];

    serverStarted = [self attemptToStartServer:self.server onPort:port withError:&error];
    if (serverStarted) {
      break;
    }

    [FBLogger logFmt:@"Failed to start web server on port %ld with error %@", (long)port, [error description]];
  }

  if (!serverStarted) {
    [FBLogger logFmt:@"Last attempt to start web server failed with error %@", [error description]];
    abort();
  }
  [FBLogger logFmt:@"%@http://%@:%d%@", FBServerURLBeginMarker, [XCUIDevice sharedDevice].fb_wifiIPAddress ?: @"localhost", [self.server port], FBServerURLEndMarker];
  
  _wsPort = [self.server port]+1;
  
  if (NSProcessInfo.processInfo.environment[@"USE_WS_PORT"] &&
      [NSProcessInfo.processInfo.environment[@"USE_WS_PORT"] length] > 0) {
    _wsPort = [NSProcessInfo.processInfo.environment[@"USE_WS_PORT"] integerValue];
  }
  
  [self startWebSocketServer:[XCUIDevice sharedDevice].fb_wifiIPAddress ?: @"localhost" port:_wsPort];
  
  [FBLogger logFmt:@"Mesmer WDA Version: %@", @"9.23.2019.1"];
  [self startTimedTask];
  [[BSWDataModelHandler sharedInstance] loadModel:@"model" modelFileExtn:@"tflite" labels:@"labels" labelsFileExtn:@"txt"];
}

- (void)startWebSocketServer:(NSString *)host port:(NSInteger)port {
  _wsServer = [PSWebSocketServer serverWithHost:host port:port];
  _wsServer.delegate = self;
  [_wsServer start];
}

- (void)startScreenCast:(NSTimer*)timer {
  dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
    NSError *error = nil;
    NSData *screenshotData = [[XCUIDevice sharedDevice] fb_screenshotHighWithError:&error quality:_quality type:@"jpeg"];
    if (screenshotData != nil && error == nil) {
      if ([_lastImageData isEqualToData:screenshotData]) {
        return;
      }
      _lastImageData = screenshotData;
      [_wsSocket send:screenshotData];
    }
    else {
      NSLog(@"Error taking screenshot: %@", error == nil ? @"Unknown error" : error);
    }
  });
}

- (void)stopScreenCast {
  if (_scTimer != nil) {
    [_scTimer invalidate];
    _scTimer = nil;
  }
  if (_wsSocket != nil) {
    [_wsSocket close];
  }
  _lastImageData = nil;
}

#pragma mark - PSWebSocketServerDelegate

- (void)serverDidStart:(PSWebSocketServer *)server {
  [FBLogger logFmt:@"%@ws://%@:%ld", @"WebSocket Server started and listening on ", [XCUIDevice sharedDevice].fb_wifiIPAddress ?: @"localhost", _wsPort];
}

- (void)serverDidStop:(PSWebSocketServer *)server {
  NSLog(@"Server did stop…");
}

- (BOOL)server:(PSWebSocketServer *)server acceptWebSocketWithRequest:(NSURLRequest *)request {
  NSLog(@"Server should accept request: %@", request);
  return YES;
}

- (void)server:(PSWebSocketServer *)server webSocket:(PSWebSocket *)webSocket didReceiveMessage:(id)message {
  NSLog(@"Server websocket did receive message: %@", message);
  _wsSocket = webSocket;
  NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error;
  NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error) {
    NSLog(@"Invalid message to web socket: %@", error);
    return;
  }
  
  NSString *cmd = [dict objectForKey:@"cmd"];
  if ([cmd caseInsensitiveCompare:@"screenCast"] == NSOrderedSame) {
    _fps = [[dict objectForKey:@"fps"] integerValue];
    if (_fps <= 0) {
      _fps = 5;
    }
    _quality = [[dict objectForKey:@"quality"] integerValue];
    _scTimer = [NSTimer scheduledTimerWithTimeInterval:1/_fps target:self selector:@selector(startScreenCast:) userInfo:nil repeats:YES];
  }
  else if ([cmd caseInsensitiveCompare:@"stopScreenCast"] == NSOrderedSame) {
    [self stopScreenCast];
  }
}

- (void)server:(PSWebSocketServer *)server webSocketDidOpen:(PSWebSocket *)webSocket {
  NSLog(@"Server websocket did open");
}

- (void)server:(PSWebSocketServer *)server webSocket:(PSWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
  NSLog(@"Server websocket did close with code: %@, reason: %@, wasClean: %@", @(code), reason, @(wasClean));
}

- (void)server:(PSWebSocketServer *)server webSocket:(PSWebSocket *)webSocket didFailWithError:(NSError *)error {
  NSLog(@"Server websocket did fail with error: %@", error);
}

- (void)startTimedTask {
  [NSTimer scheduledTimerWithTimeInterval:.2 target:self selector:@selector(performBackgroundTask) userInfo:nil repeats:YES];
}

- (void)performBackgroundTask {
  static UIInterfaceOrientation deviceOrientation;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    deviceOrientation = [[FBApplication fb_activeApplication] interfaceOrientation];
    NSLog(@"MESMER: Device Orientaion is %@", UIInterfaceOrientationIsPortrait(deviceOrientation) ? @"Portrait" : @"Landscape");
  });
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    dispatch_async(dispatch_get_main_queue(), ^{
      UIInterfaceOrientation orientation = [[FBApplication fb_activeApplication] interfaceOrientation];
      if (orientation != deviceOrientation) {
        deviceOrientation = orientation;
        NSLog(@"MESMER: Device Orientaion changed to %@", UIInterfaceOrientationIsPortrait(deviceOrientation) ? @"Portrait" : @"Landscape");
      }
    });
  });
}

- (void)stopServing
{
  [FBSession.activeSession kill];
  if (self.server.isRunning) {
    [self.server stop:NO];
  }
  self.keepAlive = NO;
}

- (BOOL)attemptToStartServer:(RoutingHTTPServer *)server onPort:(NSInteger)port withError:(NSError **)error
{
  server.port = (UInt16)port;
  NSError *innerError = nil;
  BOOL started = [server start:&innerError];
  if (!started) {
    if (!error) {
      return NO;
    }

    NSString *description = @"Unknown Error when Starting server";
    if ([innerError.domain isEqualToString:NSPOSIXErrorDomain] && innerError.code == EADDRINUSE) {
      description = [NSString stringWithFormat:@"Unable to start web server on port %ld", (long)port];
    }
    return
    [[[[FBErrorBuilder builder]
       withDescription:description]
      withInnerError:innerError]
     buildError:error];
  }
  return YES;
}

- (void)registerRouteHandlers:(NSArray *)commandHandlerClasses
{
  for (Class<FBCommandHandler> commandHandler in commandHandlerClasses) {
    NSArray *routes = [commandHandler routes];
    for (FBRoute *route in routes) {
      [self.server handleMethod:route.verb withPath:route.path block:^(RouteRequest *request, RouteResponse *response) {
        NSDictionary *arguments = [NSJSONSerialization JSONObjectWithData:request.body options:NSJSONReadingMutableContainers error:NULL];
        FBRouteRequest *routeParams = [FBRouteRequest
          routeRequestWithURL:request.url
          parameters:request.params
          arguments:arguments ?: @{}
        ];

        [FBLogger verboseLog:routeParams.description];

        @try {
          [route mountRequest:routeParams intoResponse:response];
        }
        @catch (NSException *exception) {
          [self handleException:exception forResponse:response];
        }
      }];
    }
  }
}

- (void)handleException:(NSException *)exception forResponse:(RouteResponse *)response
{
  if ([self.exceptionHandler webServer:self handleException:exception forResponse:response]) {
    return;
  }
  id<FBResponsePayload> payload = FBResponseWithErrorFormat(@"%@\n\n%@", exception.description, exception.callStackSymbols);
  [payload dispatchWithResponse:response];
}

- (void)registerServerKeyRouteHandlers
{
  [self.server get:@"/health" withBlock:^(RouteRequest *request, RouteResponse *response) {
    [response respondWithString:@"I-AM-ALIVE"];
  }];

  [self.server get:@"/wda/shutdown" withBlock:^(RouteRequest *request, RouteResponse *response) {
    [response respondWithString:@"Shutting down"];
    [self.delegate webServerDidRequestShutdown:self];
  }];

  [self registerRouteHandlers:@[FBUnknownCommands.class]];
}

@end
