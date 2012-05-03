#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

#include "reconos.h"
#include "reconosNoC.h"

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
		result->payload[i] = i+10+startValue;
	}
	return result;
}

//int myPacketReceptionHandler(reconosNoCPacket* receivedPacket)
//{
//	printf("Received Packet (size: %i Bytes)", receivedPacket->payloadLength);
//	return 0;
//}

int main(int argc, char ** argv)
{
	int errCode;

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
	//reconosNoCRegisterPacketReceptionHandler(nocPtr, myPacketReceptionHandler);

	int i;
	for(i=1; i<=MAXIMUM_PAYLOAD_SIZE; i++)
	{
		// send one packet
		reconosNoCPacket* dummyPacket = createDummyPacket(i, 0);
		errCode = reconosNoCSendPacket(nocPtr, dummyPacket);
		if(errCode)
			printf("Error when sending packet! Error code: %i\n", errCode);

		sleep(5);
	}
	printf("done");

//	printf("Creating a dummy packet...\n");
//	dummyPacket = createDummyPacket(5, 0x10);

//	printf("Creating a dummy packet... done!\n");
//	errCode = reconosNoCSendPacket(nocPtr, dummyPacket);
//	if(errCode)
//		printf("Error when sending packet! Error code: %i\n", errCode);

//	printf("Creating a dummy packet...\n");
//		dummyPacket = createDummyPacket(5);
//		printf("Creating a dummy packet... done!\n");
//		errCode = reconosNoCSendPacket(nocPtr, dummyPacket);
//		if(errCode)
//			printf("Error when sending packet! Error code: %i\n", errCode);

	while(1)
	{
		/* ... do a lot of networking ... */
	}

//	errCode = reconosNoCStop(nocPtr);
//	if(errCode)
//		printf("Error when stopping NoC! Error code: %i", errCode);

	free(nocPtr);
}
