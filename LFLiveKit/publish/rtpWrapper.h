//
//  rtpWrapper.h
//  LFLiveKit
//
//  Created by hyq on 16/10/9.
//  Copyright © 2016年 admin. All rights reserved.
//

#ifndef rtpWrapper_h
#define rtpWrapper_h

#include <stdio.h>
#include <stdlib.h>


void rtpSetup(const char* dstAddr, uint16_t videoPort, uint16_t audioPort);
void rtpRelease();

int rtpSendH264Nalu(uint32_t len, uint8_t *data, uint32_t timestamp);
int rtpSendAAC(uint32_t len, uint8_t *data, uint32_t timestamp);


#endif /* rtpWrapper_h */
