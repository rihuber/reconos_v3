#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>

#include "reconos.h"
#include "reconosNoC.h"

#define SEND_NUMBER_OF_PACKETS_COMMAND 0x1

typedef struct checksumThread{
	struct reconos_hwt hwt;
	struct reconos_resource res[2];
	struct mbox mb_put;
	struct mbox mb_get;
}checksumThread_t;

int initChecksumHwThread(checksumThread_t** checksumThread)
{
	int errCode;

	checksumThread_t* newThread = malloc(sizeof(checksumThread_t));
	if(!newThread)
		return -ENOMEM;

	// init mbox put
	errCode = mbox_init(&newThread->mb_put, MBOX_SIZE);
	if(errCode)
		return errCode;
	newThread->res[0].type = RECONOS_TYPE_MBOX;
	newThread->res[0].ptr  = &newThread->mb_put;

	// init mbox get
	errCode = mbox_init(&newThread->mb_get, MBOX_SIZE);
	if(errCode)
		return errCode;
	newThread->res[1].type = RECONOS_TYPE_MBOX;
	newThread->res[1].ptr  = &newThread->mb_get;

	// start the hardware thread
	reconos_hwt_setresources(&newThread->hwt, newThread->res, 2);
	reconos_hwt_create(&newThread->hwt, 2, NULL);

	*checksumThread = newThread;

	return 0;
}

reconosNoCPacket* createDummyPacket(uint32_t payloadLength, uint32_t startValue)
{
	reconosNoCPacket* result = malloc(sizeof(reconosNoCPacket));
	result->direction = 1;
	result->srcIdp = 0x02030405;
	result->dstIdp = 0x06070809;
	result->latencyCritical = 0;
	result->priority = 0;
	result->hwAddrGlobal = 0;
	result->hwAddrLocal = 0;
	result->payloadLength = payloadLength;
	result->payload = malloc(payloadLength);
	int i;
	for(i=0; i<payloadLength; i++)
	{
		result->payload[i] = (uint8_t)(i+10+startValue);
	}
	return result;
}

int myPacketReceptionHandler(reconosNoCPacket* receivedPacket)
{
	printf("Received Packet (size: %i Bytes)\n", receivedPacket->payloadLength);
//	if((receivedPacket->payloadLength & 0x0F) == 0)
//	{
//		int i;
//		for(i=0; i<receivedPacket->payloadLength; i++)
//			printf("%i: %i\n", i, receivedPacket->payload[i]);
//	}
	return 0;
}

int main(int argc, char ** argv)
{
	int errCode;

	printf("Ring buffer size is %i bytes\n", RING_BUFFER_SIZE);

	// init reconos and communication resources
	errCode = reconos_init_autodetect();
	if(errCode)
	{
		printf("Error when initializing reconos! Error code: %i", errCode);
		return 0;
	}

	// init the HW-SW interface
	reconosNoC* nocPtr = NULL;
	errCode = reconosNoCInit(&nocPtr);
	if(errCode)
	{
		printf("Error when initializing HW-SW interface! Error code: %i", errCode);
		return 0;
	}

	// register a packet reception handler
	reconosNoCRegisterPacketReceptionHandler(nocPtr, myPacketReceptionHandler);

	checksumThread_t* checksumThread;
	errCode = initChecksumHwThread(&checksumThread);
	if(errCode)
	{
		printf("Error when initializing checksum hw thread! Error code: %i", errCode);
		return 0;
	}

	mbox_put(&checksumThread->mb_put, SEND_NUMBER_OF_PACKETS_COMMAND);
	int result = mbox_get(&checksumThread->mb_get);
	printf("Checksum thread has seen %i packets\n", result);


	printf("Now starting network traffic\n");

	int i;
	for(i=1; i<=MAXIMUM_PAYLOAD_SIZE; i++)
	{
		// send one packet
		reconosNoCPacket* dummyPacket = createDummyPacket(i, 0);
		errCode = reconosNoCSendPacket(nocPtr, dummyPacket);
		if(errCode)
			printf("Error when sending packet! Error code: %i\n", errCode);
	}
	printf("%i packets sent!\n", i-1);

	mbox_put(&checksumThread->mb_put, SEND_NUMBER_OF_PACKETS_COMMAND);
	result = mbox_get(&checksumThread->mb_get);
	printf("Checksum thread has seen %i packets\n", result);

	while(1)
	{
		/* ... do a lot of networking ... */
	}

	errCode = reconosNoCStop(nocPtr);
	if(errCode)
		printf("Error when stopping NoC! Error code: %i", errCode);
	nocPtr = NULL;
}
