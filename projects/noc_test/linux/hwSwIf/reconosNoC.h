#ifndef RECONOS_NOC_H
#define RECONOS_NOC_H

// print verbose debug output
#define RECONOS_NOC_VERBOSE

#include <stdint.h>
#include "reconos.h"
#include "mbox.h"

typedef struct reconosNoCPacket{
	char hwAddrLocal;		// the local hardware address
	char hwAddrGlobal;		// the global hardware address
	char priority;			// range [0..3]
	char direction;			// 1 for ingress, 0 for egress
	char latencyCritical;	// 1: packet is latency critical, 0 packet is not latency critical
	uint32_t srcIdp;		// src IDP of the packet
	uint32_t dstIdp;		// dst IDP of the packet
	uint32_t payloadLength;	// the length of the payload in bytes
	char* payload;			// pointer to the actual payload
}reconosNoCPacket;

#include "packetList.h"

typedef struct reconosNoCsw2hwInterface{
	struct reconos_hwt hwt;
	struct reconos_resource res[2];
	struct mbox mb_put;
	struct mbox mb_get;
	char* ringBufferBaseAddr;
	uint32_t readOffset;
	uint32_t writeOffset, hwWriteOffset;
	char writePointerDirty;
	pthread_t packetProcessingThread, timerThread, pointerExchangeThread, threadControlThread;
	pthread_mutex_t timerMutex, pointersMutex;
	pthread_cond_t offsetUpdateCond, startTimerCond, abortTimerCond, exchangePointersCond;
	sem_t processOnePacketSem, hardwareThreadReadySem;
	char startTimer, timerRunning;
	packetList packetsToProcess;
	pthread_mutex_t packetListManipulateMutex;
}reconosNoCsw2hwInterface;

typedef struct reconosNoChw2swInterface{
	struct reconos_hwt hwt;
	struct reconos_resource res[2];
	struct mbox mb_put;
	struct mbox mb_get;
	char* ringBufferBaseAddr;
	uint32_t readOffset;
	uint32_t writeOffset;
	pthread_t packetProcessingThread, pointerExchangeThread, threadControlThread;
	pthread_mutex_t timerMutex, pointersMutex;
	sem_t packetsToProcessSem, hardwareThreadReadySem;
	char startTimer, timerRunning;
	packetList packetsToProcess;
}reconosNoChw2swInterface;

typedef struct reconosNoC{
	reconosNoCsw2hwInterface* sw2hwInterface;
	reconosNoChw2swInterface* hw2swInterface;
	sem_t killThreadsSem;
	pthread_t threadControlThread;
}reconosNoC;

// the number of messages that fit in the message boxes
#define MBOX_SIZE 4

// the size of the ring buffer in bytes
#define RING_BUFFER_SIZE 64

// used to transmit the thread exit command with message boxes
#define MBOX_SIGNAL_THREAD_EXIT 0xFFFFFFFF

// the number of bytes of the NoC header
#define HEADER_SIZE 10

// if after writing a packet to the ringbuffer the amount of free space
// in the ringbuffer is below this threshold, a write pointer exchange
// is delegated
#define ALMOST_FULL_TRESHOLD 20

// a write pointer exchange is delegated if no write pointer exchange
// is yet delegated after this amount of time after a packet has been
// written to the ringbuffer
#define TIMEOUT_DURATION_MICROSEC 0
#define TIMEOUT_DURATION_SEC 10

// header bitmasks
#define GLOBAL_ADDR_MASK 15
#define GLOBAL_ADDR_OFFSET 0
#define LOCAL_ADDR_MASK 3
#define LOCAL_ADDR_OFFSET 4
#define PRIORITY_MASK 3
#define PRIORITY_OFFSET 6
#define DIRECTION_MASK 1
#define DIRECTION_OFFSET 0
#define LATENCY_CRITICAL_MASK 1
#define LATENCY_CRITICAL_OFFSET 1

int reconosNoCInit(reconosNoC** nocPtr);
int reconosNoCStop(reconosNoC* nocPtr);
int reconosNoCSendPacket(reconosNoC* nocPtr, reconosNoCPacket* packet);
int reconosNoCRegisterPacketReceptionHandler(reconosNoC* nocPtr, int (*newHandler)(reconosNoCPacket*));

#endif
