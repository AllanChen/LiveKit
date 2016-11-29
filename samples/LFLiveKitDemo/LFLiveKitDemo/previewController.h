//
//  previewController.h
//  LFLiveKitDemo
//
//  Created by hyq on 16/10/18.
//  Copyright © 2016年 admin. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface previewController : UIViewController
@property(copy, nonatomic, nullable) NSString *host;
@property(copy, nonatomic, nullable) NSString *port;
@property(copy, nonatomic, nullable) NSString *url;
@property(copy, nonatomic) void (^_Nonnull didClose)();
@property(nonatomic, assign) BOOL onLive;

@end
