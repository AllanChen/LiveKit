//
//  rtpWrapper.c
//  LFLiveKit
//
//  Created by hyq on 16/10/9.
//  Copyright © 2016年 admin. All rights reserved.
//

#include "rtpWrapper.h"
#include <string.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <errno.h>

const int FU_HEADER_LEN_UDP = 2;
const int AU_HEADER_LEN_UDP = 4;
const int RTP_HEADER_LEN_UDP = 12;
const int TYPE_FU_A_UDP = 28;           /*fragmented unit 0x1C*/
const int MAX_PAYLOAD_LEN_UDP = 1280;
struct RTP_SESSION{
    int      videoSock;
    int      audioSock;
    uint16_t videoSeqNo;
    uint16_t audioSeqNo;
    uint32_t videoSSRC;
    uint32_t audioSSRC;
    uint8_t  sendBuf[MAX_PAYLOAD_LEN_UDP + RTP_HEADER_LEN_UDP];
    uint8_t  sendAudioBuf[MAX_PAYLOAD_LEN_UDP + RTP_HEADER_LEN_UDP];
}RTP_SESSION;
struct RTP_SESSION *session = NULL;


static int  sendAudio(uint32_t len, uint8_t *data);
static int  sendVideo(uint32_t len, uint8_t *data);
static void setupSocket(const char* dstAddr, uint16_t videoPort, uint16_t audioPort);
static void releaseSocket();
static void buildRtpHeader(uint8_t *buf, uint16_t seqNO, uint32_t ssrc, uint32_t timestamp, uint8_t markbitAndpayloadType);


void rtpSetup(const char* dstAddr, uint16_t videoPort, uint16_t audioPort) {
    session = (struct RTP_SESSION *)malloc(sizeof(RTP_SESSION));
    memset(session, 0, sizeof(RTP_SESSION));
    session->videoSSRC = 0x55667788;
    session->audioSSRC = 0x66778899;
    
    setupSocket(dstAddr, videoPort, audioPort);
}

void rtpRelease() {
    releaseSocket();
    free(session);
    session = NULL;
}

int rtpSendH264Nalu(uint32_t len, uint8_t *data, uint32_t timestamp) {
    if (len <= MAX_PAYLOAD_LEN_UDP) {
        buildRtpHeader(session->sendBuf, session->videoSeqNo, session->videoSSRC, timestamp, 0xE0);
        memcpy(session->sendBuf + RTP_HEADER_LEN_UDP, data, len);
        sendVideo(len + RTP_HEADER_LEN_UDP, session->sendBuf);
    } else {
    
        uint32_t pos = 0;
        uint8_t nalu_header = data[0];
        uint8_t *nalu = data + 1;
        uint32_t nalu_len = len - 1;
        uint8_t *fuHeader = session->sendBuf + RTP_HEADER_LEN_UDP;
        
        while (pos < nalu_len) {
            if (pos == 0) {
                
                //1   first rtp packet
                buildRtpHeader(session->sendBuf, session->videoSeqNo, session->videoSSRC, timestamp, 0x60);
                //1.1 fu indicatior
                fuHeader[0] = (nalu_header & 0xe0) | TYPE_FU_A_UDP;
                //1.2 fu header s|e|r|nalu type
                fuHeader[1] = 0x80 | (nalu_header & 0x1f);
                memcpy(fuHeader + FU_HEADER_LEN_UDP, nalu, MAX_PAYLOAD_LEN_UDP - FU_HEADER_LEN_UDP);
                sendVideo(MAX_PAYLOAD_LEN_UDP + RTP_HEADER_LEN_UDP, session->sendBuf);
                pos += (MAX_PAYLOAD_LEN_UDP - FU_HEADER_LEN_UDP);
            } else if (nalu_len - pos + FU_HEADER_LEN_UDP <= MAX_PAYLOAD_LEN_UDP) {
                
                //2   last rtp packet
                buildRtpHeader(session->sendBuf, session->videoSeqNo, session->videoSSRC, timestamp, 0x60);
                //2.2 fu indicatior
                fuHeader[0] = (nalu_header & 0xe0) | TYPE_FU_A_UDP;
                //2.3 fu header s|e|r|nalu type
                fuHeader[1] = 0x40 | (nalu_header & 0x1f);
                
                memcpy(fuHeader + FU_HEADER_LEN_UDP, nalu + pos, nalu_len - pos);
                sendVideo(nalu_len - pos + RTP_HEADER_LEN_UDP + FU_HEADER_LEN_UDP, session->sendBuf);
                pos += (nalu_len - pos);
                break;
            } else {
                
                //3   normal rtp packet
                buildRtpHeader(session->sendBuf, session->videoSeqNo, session->videoSSRC, timestamp, 0x60);
                //3.1 fu indicatior
                fuHeader[0] = (nalu_header & 0xe0) | TYPE_FU_A_UDP;
                //3.2 fu header s|e|r|nalu type
                fuHeader[1] = 0x0 | (nalu_header & 0x1f);
                
                memcpy(fuHeader + FU_HEADER_LEN_UDP, nalu + pos, MAX_PAYLOAD_LEN_UDP - FU_HEADER_LEN_UDP);
                sendVideo(MAX_PAYLOAD_LEN_UDP + RTP_HEADER_LEN_UDP, session->sendBuf);
                pos += (MAX_PAYLOAD_LEN_UDP - FU_HEADER_LEN_UDP);
                usleep(3000);
            }
        }
    }
    return len;
}

/* 相关资料
 3016与3640，3640介绍的是mpeg4-generic的rtp封装说明（AU_header_size+AU_header加原数据），3016介绍的是MP4A-LATM的rtp封装说明（StreamMuxConfig + PayloadLengthInfo + PayloadMux）
 UINT8 audioConfig[2] = {0};
 UINT8 const audioObjectType = profile + 1;
 audioConfig[0] = (audioObjectType<<3) | (samplingFrequencyIndex>>1);
 audioConfig[1] = (samplingFrequencyIndex<<7) | (channelConfiguration<<3);
 sampling_frequency_index  sampling frequeny [Hz]
 0x0                       96000
 0x1                       88200
 0x2                       64000
 0x3                       48000
 0x4                       44100
 0x5                       32000
 0x6                       24000
 0x7                       22050
 0x8                       16000
 0x9                       12000
 0xa                       11025
 0xb                       8000
 0xc                       reserved
 0xd                       reserved
 0xe                       reserved
 0xf                       reserved
 */
int rtpSendAAC(uint32_t len, uint8_t *data, uint32_t timestamp) {
    buildRtpHeader(session->sendAudioBuf, session->audioSeqNo, session->audioSSRC, timestamp, 0xE1);
    
    //aac au header size + au header rfc 3640
    uint8_t *auHeader = session->sendAudioBuf + RTP_HEADER_LEN_UDP;
    auHeader[0] = 0x00;
    auHeader[1] = 0x10;//in bit
    auHeader[2] = (len & 0x1fe0) >> 5;
    auHeader[3] = (len & 0x1f) << 3;
    
    memcpy(session->sendAudioBuf + RTP_HEADER_LEN_UDP + AU_HEADER_LEN_UDP, data, len);
    sendAudio(len + RTP_HEADER_LEN_UDP + AU_HEADER_LEN_UDP, session->sendAudioBuf);
    return len;
}

static int sendAudio(uint32_t len, uint8_t *data) {
    session->audioSeqNo++;
    return (int)send(session->audioSock, data, len, 0);
}

static int  sendVideo(uint32_t len, uint8_t *data) {
    int ret = (int)send(session->videoSock, data, len, 0);
//    printf("[udp] send seq=%d, len=%d ret=%d\n", session->videoSeqNo, len, ret);
    session->videoSeqNo++;
    return ret;
}

static void setupSocket(const char* dstIP, uint16_t videoPort, uint16_t audioPort) {
    session->videoSock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    struct sockaddr_in videoAddr;
    bzero(&videoAddr, sizeof(videoAddr));
    videoAddr.sin_family = AF_INET;
    videoAddr.sin_len = sizeof(videoAddr);
    videoAddr.sin_port = htons(videoPort);
    videoAddr.sin_addr.s_addr = inet_addr(dstIP);
    
    int sendBufLen =2 * 1024 * 1024;
    if (setsockopt(session->videoSock, SOL_SOCKET, SO_SNDBUF, (const char*)&sendBufLen, sizeof(int))) {
        printf("[RTP] [setupSocket] [setsockopt error=%d][IP=%s][port=%d]\n", errno, dstIP, videoPort);
    }
    
    if(connect(session->videoSock, (struct sockaddr *)&videoAddr, sizeof(videoAddr))) {
        printf("[RTP] [setupSocket] [connect error][IP=%s][port=%d]", dstIP, videoPort);
        return;
    }
    
    session->audioSock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    struct sockaddr_in audioAddr;
    bzero(&audioAddr, sizeof(audioAddr));
    audioAddr.sin_family = AF_INET;
    audioAddr.sin_len = sizeof(audioAddr);
    audioAddr.sin_port = htons(audioPort);
    audioAddr.sin_addr.s_addr = inet_addr(dstIP);
    if (connect(session->audioSock, (struct sockaddr *)&audioAddr, sizeof(audioAddr))) {
        printf("[RTP] [setupSocket] [connect error][IP=%s][port=%d]", dstIP, audioPort);
    }
}

static void releaseSocket() {
    close(session->videoSock);
    close(session->audioSock);
}

static void buildRtpHeader(uint8_t *buf, uint16_t seqNO, uint32_t ssrc, uint32_t timestamp, uint8_t markbitAndpayloadType) {
    //rtp header rfc3550
    uint8_t *rtpHeader = buf;
    rtpHeader[0] = 0x80;
    rtpHeader[1] = markbitAndpayloadType;
    rtpHeader[2] = seqNO >> 8;
    rtpHeader[3] = seqNO;
    rtpHeader[4] = timestamp >> 24;
    rtpHeader[5] = timestamp >> 16;
    rtpHeader[6] = timestamp >> 8;
    rtpHeader[7] = timestamp;
    rtpHeader[8] = ssrc >> 24;
    rtpHeader[9] = ssrc >> 16;
    rtpHeader[10] = ssrc >> 8;
    rtpHeader[11] = ssrc;
}
