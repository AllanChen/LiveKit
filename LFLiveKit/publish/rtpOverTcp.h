//
//  rtpOverTcp.h
//  Pods
//
//  Created by hyq on 16/10/20.
//
//

#ifndef rtpOverTcp_h
#define rtpOverTcp_h

//0x23 message; 0x24 rtp 0x25 connect 0x26 start 0x27 stop 0x28 disconnect
enum RTPTCP_MESSAGE {
    MSG_LOGIN       = 0x25,
    MSG_PUBLISH     = 0x26,
    MSG_UNPUBLISH   = 0x27,
    MSG_LOGOUT      = 0x28,
};

#include <stdio.h>
#include <stdlib.h>

void rtptcpSetup();
void rtptcpRelease();

int  rtptcpConnect(const char* dstAddr, uint16_t port, uint32_t uid);
void rtptcpDisconnect();

int  rtptcpSendH264Nalu(uint32_t len, uint8_t *data, uint32_t timestamp);
int  rtptcpSendAAC(uint32_t len, uint8_t *data, uint32_t timestamp);

//返回RTPTCP_MESSAGE
int  rtptcpRecvMessage();

#endif /* rtpOverTcp_h */
