//
//  DDLoggerWrapper.h
//  LFLiveKit
//
//  Created by hyq on 16/11/25.
//  Copyright © 2016年 admin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CocoaLumberjack/CocoaLumberjack.h>
extern DDLogLevel ddLogLevel;

#define NSLog(fmt,...) DDLogInfo(fmt, ##__VA_ARGS__)

@interface DDLoggerWrapper : NSObject
+(void)setupLoger;
@end
