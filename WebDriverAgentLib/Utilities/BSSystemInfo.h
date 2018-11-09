//
//  BSSystemInfo.h
//  WebDriverAgentLib
//
//  Created by Suman Cherukuri on 11/8/18.
//  Copyright © 2018 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <mach/mach.h>

NSDictionary *cpuUsage(void);
NSDictionary *memoryUsage(void);
NSDictionary* diskUsage(void);
float batteryLevel(void);
NSDictionary *systemInfo(void);
