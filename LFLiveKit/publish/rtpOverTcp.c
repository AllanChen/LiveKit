//
//  rtpOverTcp.c
//  Pods
//
//  Created by hyq on 16/10/20.
//
//

#include "rtpOverTcp.h"
#include <string.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <pthread.h>
#include <errno.h>
#include <err.h>
#include <netdb.h>

const int FU_HEADER_LEN     = 2;
const int AU_HEADER_LEN     = 4;
const int RTP_HEADER_LEN    = 12;
const int TYPE_FU_A         = 28;           /*fragmented unit 0x1C*/
const int MAX_PAYLOAD_LEN   = 1400;
const int RTP_PKT_VIDEO     = 0x00;
const int RTP_PKT_AUDIO     = 0x02;
const int MSG_TYPE_STREAM   = 0x24;
const int SEND_BUF_SIZE     = 2 * 1024 * 1024;
const int RECV_BUF_SIZE     = 10 *1024;

struct RTP_SESSION_TCP{
    int      sock;
    uint16_t videoSeqNo;
    uint16_t audioSeqNo;
    uint32_t videoSSRC;
    uint32_t audioSSRC;
    uint8_t  sendBuf[SEND_BUF_SIZE];
    uint8_t  recvBuf[RECV_BUF_SIZE];
    uint32_t sendBufLen;
    uint32_t recvBufLen;
    
}RTP_SESSION_TCP;
struct RTP_SESSION_TCP *rtpTcpSession = NULL;


static int  sendAudio(uint32_t len, uint8_t *data);
static int  sendVideo(uint32_t len, uint8_t *data);
static void buildRtpHeader(uint8_t *buf, uint16_t seqNO, uint32_t ssrc, uint32_t timestamp, uint8_t markbitAndpayloadType);
static void buildMsgHeader(uint8_t *buf, uint8_t msgType, uint8_t channel, uint32_t len);
static void modifyMsgHeader(uint8_t *buf, uint32_t len);
static void buildFuHeader(uint8_t *buf, uint8_t serMark, uint8_t naluHeder);

void rtptcpSetup() {
    rtpTcpSession = (struct RTP_SESSION_TCP *)malloc(sizeof(RTP_SESSION_TCP));
    memset(rtpTcpSession, 0, sizeof(RTP_SESSION_TCP));
    rtpTcpSession->videoSSRC = 0x55667788;
    rtpTcpSession->audioSSRC = 0x66778899;
}

void rtptcpRelease() {
    free(rtpTcpSession);
    rtpTcpSession = NULL;
}


int rtptcpSendH264Nalu(uint32_t len, uint8_t *data, uint32_t timestamp) {
    
    int totalLen = 0;
    
    if (len <= MAX_PAYLOAD_LEN) {
        uint8_t  *msgHdr = rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen;
        uint32_t msgHdrPos = rtpTcpSession->sendBufLen;
        
        buildMsgHeader(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, MSG_TYPE_STREAM, RTP_PKT_VIDEO, 0);
        buildRtpHeader(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, rtpTcpSession->videoSeqNo, rtpTcpSession->videoSSRC, timestamp, 0x60);
        memcpy(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, data, len);
        rtpTcpSession->sendBufLen += len;
        modifyMsgHeader(msgHdr, rtpTcpSession->sendBufLen - msgHdrPos - 4);
    } else {
        uint32_t pos = 0;
        uint8_t nalu_header = data[0];
        uint8_t *nalu = data + 1;
        uint32_t nalu_len = len - 1;
        
        while (pos < nalu_len) {
            
            uint8_t  *msgHdr = rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen;
            uint32_t msgHdrPos = rtpTcpSession->sendBufLen;
            buildMsgHeader(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, MSG_TYPE_STREAM, RTP_PKT_VIDEO, 0);
            buildRtpHeader(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, rtpTcpSession->videoSeqNo, rtpTcpSession->videoSSRC, timestamp, 0x60);
            
            if (pos == 0) {
                
                //1   first rtp packet fu header
                buildFuHeader(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, 0x80, nalu_header);
                memcpy(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, nalu, MAX_PAYLOAD_LEN - FU_HEADER_LEN);
                rtpTcpSession->sendBufLen += (MAX_PAYLOAD_LEN - FU_HEADER_LEN);
                pos += (MAX_PAYLOAD_LEN - FU_HEADER_LEN);
            } else if (nalu_len - pos + FU_HEADER_LEN <= MAX_PAYLOAD_LEN) {
                
                //2   last rtp packe fu headert
                buildFuHeader(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, 0x40, nalu_header);
                memcpy(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, nalu + pos, nalu_len - pos);
                rtpTcpSession->sendBufLen += (nalu_len - pos);
                pos += (nalu_len - pos);
            } else {
                
                //3   normal rtp packe fu headert
                buildFuHeader(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, 0x00, nalu_header);
                memcpy(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, nalu + pos, MAX_PAYLOAD_LEN - FU_HEADER_LEN);
                rtpTcpSession->sendBufLen += (MAX_PAYLOAD_LEN - FU_HEADER_LEN);
                pos += (MAX_PAYLOAD_LEN - FU_HEADER_LEN);
            }
            
            modifyMsgHeader(msgHdr, rtpTcpSession->sendBufLen - msgHdrPos - 4);
            totalLen += sendVideo(rtpTcpSession->sendBufLen, rtpTcpSession->sendBuf);
        }
    }
    return totalLen;
}

int rtptcpSendAAC(uint32_t len, uint8_t *data, uint32_t timestamp) {

    uint8_t  *msgHdr = rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen;
    uint32_t msgHdrPos = rtpTcpSession->sendBufLen;
 
    buildMsgHeader(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, MSG_TYPE_STREAM, RTP_PKT_AUDIO, 0);
    buildRtpHeader(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, rtpTcpSession->audioSeqNo, rtpTcpSession->audioSSRC, timestamp, 0xE1);
    
    //aac au header size + au header rfc 3640
    uint8_t *auHeader = rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen;
    auHeader[0] = 0x00;
    auHeader[1] = 0x10;//in bit
    auHeader[2] = (len & 0x1fe0) >> 5;
    auHeader[3] = (len & 0x1f) << 3;
    rtpTcpSession->sendBufLen += 4;
    
    memcpy(rtpTcpSession->sendBuf + rtpTcpSession->sendBufLen, data, len);
    rtpTcpSession->sendBufLen += len;
    modifyMsgHeader(msgHdr, rtpTcpSession->sendBufLen - msgHdrPos - 4);
    return sendAudio(rtpTcpSession->sendBufLen, rtpTcpSession->sendBuf);
}

static int sendData(uint32_t len, uint8_t *data) {
    int sendLen = 0;
    while (sendLen < len) {
        int ret = (int)send(rtpTcpSession->sock, data + sendLen, len - sendLen, 0);
        if (ret <= 0) {
            int err = errno;
            printf("[RTPTCP] [sendData] send errno=%d:%s!\n", err, strerror(err));
            rtptcpDisconnect();
            return -1;
        }
        sendLen += ret;
    }
    
    return sendLen;
}

static int sendVideo(uint32_t len, uint8_t *data) {
    int sendLen = sendData(len, data);
    rtpTcpSession->sendBufLen = 0;
    return sendLen;
}

static int sendAudio(uint32_t len, uint8_t *data) {
    int sendLen = sendData(len, data);
    rtpTcpSession->sendBufLen = 0;
    return sendLen;
}


static int recvData(uint32_t len, uint8_t *buf) {
    int recvLen = 0;
    while (recvLen < len) {
        size_t ret = recv(rtpTcpSession->sock, buf + recvLen, len - recvLen, 0);
        if (ret <= 0) {
            int err = errno;
            printf("[RTPTCP] [recvData] errno=%d:%s!\n", err, strerror(err));
            rtptcpDisconnect();
            return -1;
        }
        recvLen += ret;
    }
    
    return recvLen;
}

int rtptcpRecvMessage() {
    rtpTcpSession->recvBufLen = 0;
    uint8_t *buf = rtpTcpSession->recvBuf + rtpTcpSession->recvBufLen;
    int ret = recvData(4, buf);
    if (ret < 0) return ret;
    rtpTcpSession->recvBufLen += ret;
    
    int message = buf[0];
    int messageLen = (buf[2] << 8) | buf[3];
    
    if (messageLen > 0) {
        buf = rtpTcpSession->recvBuf + rtpTcpSession->recvBufLen;
        ret = recvData(messageLen, buf);
        if (ret < 0) return message;
        rtpTcpSession->recvBufLen += ret;
    }
    
    return message;
}

static int rtptcpLogin(uint32_t uid) {
    int msgLen = 4;
    uint8_t buf[8] = {0};
    buf[0] = MSG_LOGIN;
    buf[1] = 0;
    buf[2] = msgLen >> 8;
    buf[3] = msgLen;
    buf[4] = uid >> 24;
    buf[5] = uid >> 16;
    buf[6] = uid >> 8;
    buf[7] = uid;
    
    if (sendData(8, buf) != 8) {
        return -1;
    }
    
    return 0;
}

int rtptcpConnect(const char* dstIP, uint16_t port, uint32_t uid) {
    struct addrinfo hints, *res, *res0;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_DEFAULT;
    
    int error, s;
    error = getaddrinfo(dstIP, NULL, &hints, &res0);
    if (error) {
        printf("[RTPTCP] [rtptcpConnect] [getaddrinfo error=%s][IP=%s][port=%d]\n", gai_strerror(error), dstIP, port);
        return -1;
    }
    
    s = -1;
    for (res = res0; res; res = res->ai_next) {
        s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
        if (s < 0) continue;
        
        int sendBufSize = 2 * 1024 * 1024; //设置为2M
        if (setsockopt(s, SOL_SOCKET, SO_SNDBUF, (const char*)&sendBufSize, sizeof(int))) {
            printf("[RTPTCP] [rtptcpConnect] [setsockopt sndbuf error=%d][IP=%s][port=%d]\n", errno, dstIP, port);
            return -1;
        }
        
        int nosigpipe = 1;
        if (setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, (const char*)&nosigpipe, sizeof(int))) {
            printf("[RTPTCP] [rtptcpConnect] [setsockopt nosigpipe error=%d][IP=%s][port=%d]\n", errno, dstIP, port);
            return -1;
        }

        if (res->ai_family == AF_INET6) {
            struct sockaddr_in6 *addr6 = (struct sockaddr_in6 *)res->ai_addr;
            addr6->sin6_port = htons(port);
        }else {
            struct sockaddr_in *addr4 = (struct sockaddr_in *)res->ai_addr;
            addr4->sin_port = htons(port);
        }
        
        if (connect(s, (struct sockaddr *)res->ai_addr, res->ai_addrlen) < 0) {
            close(s);
            s = -1;
            continue;
        }
        
        break;
    }
    
    if (s < 0) {
        printf("[RTPTCP] [rtptcpConnect] [connect error=%d][IP=%s][port=%d]\n", errno, dstIP, port);
        freeaddrinfo(res0);
        return -1;
    }
    rtpTcpSession->sock = s;
    
    if (rtptcpLogin(uid)) {
        printf("[RTPTCP] [rtptcpConnect] [login error=%d][IP=%s][port=%d][uid=%d]\n", errno, dstIP, port, uid);
        return -1;
    }
    
    return 0;
}

void rtptcpDisconnect() {
    if (rtpTcpSession->sock > 0) {
        close(rtpTcpSession->sock);
        rtpTcpSession->sock = -1;
    }
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
    
    if (markbitAndpayloadType == 0x60) {
        rtpTcpSession->videoSeqNo++;
    } else {
        rtpTcpSession->audioSeqNo++;
    }

    rtpTcpSession->sendBufLen += RTP_HEADER_LEN;
}

static void buildMsgHeader(uint8_t *buf, uint8_t msgType, uint8_t channel, uint32_t len) {
    buf[0] = msgType;
    buf[1] = channel;
    buf[2] = (len & 0xffff) >> 8;
    buf[3] = len & 0xff;
    rtpTcpSession->sendBufLen += 4;
}

static void modifyMsgHeader(uint8_t *buf, uint32_t len) {
    buf[2] = (len & 0xffff) >> 8;
    buf[3] = len & 0xff;
}

static void buildFuHeader(uint8_t * fuHeader, uint8_t serMark, uint8_t naluHeder) {
    //1 fu indicatior
    fuHeader[0] = (naluHeder & 0xe0) | TYPE_FU_A;
    //1 fu header s|e|r|nalu type
    fuHeader[1] = serMark | (naluHeder & 0x1f);
    rtpTcpSession->sendBufLen += FU_HEADER_LEN;
}






