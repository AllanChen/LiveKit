//
//  LFStreamRTPTCPSocket.h
//  Pods
//
//  Created by hyq on 16/10/20.
//
//

#import "LFStreamSocket.h"

@interface LFStreamRTPTCPSocket : NSObject<LFStreamSocket>

#pragma mark - Initializer
///=============================================================================
/// @name Initializer
///=============================================================================
- (nullable instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (nullable instancetype)new UNAVAILABLE_ATTRIBUTE;

@property(nonatomic, assign) NSUInteger uid;
@end
