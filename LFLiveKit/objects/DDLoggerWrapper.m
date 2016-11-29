//
//  DDLoggerWrapper.m
//  LFLiveKit
//
//  Created by hyq on 16/11/25.
//  Copyright © 2016年 admin. All rights reserved.
//

#import "DDLoggerWrapper.h"


@interface DDLogRenameStorageFileName : DDLogFileManagerDefault
@end

@implementation DDLogRenameStorageFileName

- (NSString *)newLogFileName {
    NSString *appName = [self applicationName];
    
    NSDateFormatter *dateFormatter = [self logFileDateFormatter];
    NSString *formattedDate = [dateFormatter stringFromDate:[NSDate date]];
    
    return [NSString stringWithFormat:@"%@_%@.log", appName, formattedDate];
}

- (NSString *)applicationName {
    static NSString *_appName = @"yy.mshow.lanmediasdk";
    
    return _appName;
}

- (BOOL)isLogFile:(NSString *)fileName {
    NSString *appName = [self applicationName];
    
    BOOL hasProperPrefix = [fileName hasPrefix:appName];
    BOOL hasProperSuffix = [fileName hasSuffix:@".log"];
    BOOL hasProperDate = NO;
    
    if (hasProperPrefix && hasProperSuffix) {
        NSUInteger lengthOfMiddle = fileName.length - appName.length - @".log".length;
        
        // Date string should have at least 16 characters - " 2013-12-03 17-14"
        if (lengthOfMiddle >= 17) {
            NSRange range = NSMakeRange(appName.length, lengthOfMiddle);
            
            NSString *middle = [fileName substringWithRange:range];
            NSArray *components = [middle componentsSeparatedByString:@"_"];
            
            // When creating logfile if there is existing file with the same name, we append attemp number at the end.
            // Thats why here we can have three or four components. For details see createNewLogFile method.
            //
            // Components:
            //     "", "2013-12-03", "17-14"
            // or
            //     "", "2013-12-03", "17-14", "1"
            if (components.count == 3 || components.count == 4) {
                NSString *dateString = [NSString stringWithFormat:@"%@_%@", components[1], components[2]];
                NSDateFormatter *dateFormatter = [self logFileDateFormatter];
                
                NSDate *date = [dateFormatter dateFromString:dateString];
                
                if (date) {
                    hasProperDate = YES;
                }
            }
        }
    }
    
    return (hasProperPrefix && hasProperDate && hasProperSuffix);
}

- (NSDateFormatter *)logFileDateFormatter {
    NSMutableDictionary *dictionary = [[NSThread currentThread]
                                       threadDictionary];
    NSString *dateFormat = @"yyyy'-'MM'-'dd'_'HH'-'mm'";
    NSString *key = [NSString stringWithFormat:@"logFileDateFormatter.%@", dateFormat];
    NSDateFormatter *dateFormatter = dictionary[key];
    
    if (dateFormatter == nil) {
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"zh_CN"]];
        [dateFormatter setDateFormat:dateFormat];
        [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:8 * 3600]];
        dictionary[key] = dateFormatter;
    }
    
    return dateFormatter;
}

@end


DDLogLevel ddLogLevel = DDLogLevelVerbose;

@implementation DDLoggerWrapper

+ (void)setupLoger {
    [DDLog addLogger:[DDTTYLogger sharedInstance]]; // TTY = Xcode console
    //    [DDLog addLogger:[DDASLLogger sharedInstance]]; // ASL = Apple System Logs
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    DDLogRenameStorageFileName *fileMgrDft = [[DDLogRenameStorageFileName alloc]initWithLogsDirectory:documentsDirectory];
    DDFileLogger *fileLogger = [[DDFileLogger alloc] initWithLogFileManager:fileMgrDft]; // File Logger
    fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    fileLogger.logFileManager.maximumNumberOfLogFiles = 10;
    [DDLog addLogger:fileLogger];
}

@end
