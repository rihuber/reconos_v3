#include <stdlib.h>
#include <stdio.h>

#include "reconos.h"
#include "reconosNoC.h"

reconosNoCPacket* createDummyPacket(uint32_t payloadLength)
{
	reconosNoCPacket* result = malloc(sizeof(reconosNoCPacket));
	result->direction = 0;
	result->srcIdp = 0x03040506;
	result->dstIdp = 0x0708090a;
	result->latencyCritical = 1;
	result->priority = 0;
	result->hwAddrGlobal = 1;
	result->hwAddrLocal = 0;
	result->payloadLength = payloadLength;
	result->payload = malloc(payloadLength);
	int i;
	for(i=0; i<payloadLength; i++)
	{
		result->payload[i] = i+11;
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

	// send one packet
	printf("Creating a dummy packet...\n");
	reconosNoCPacket* dummyPacket = createDummyPacket(18);
	printf("Creating a dummy packet... done!\n");
	errCode = reconosNoCSendPacket(nocPtr, dummyPacket);
	if(errCode)
		printf("Error when sending packet! Error code: %i\n", errCode);
	//free(dummyPacket);

	while(1)
	{
		/* ... do a lot of networking ... */
	}

//	errCode = reconosNoCStop(nocPtr);
//	if(errCode)
//		printf("Error when stopping NoC! Error code: %i", errCode);

	free(nocPtr);
}
