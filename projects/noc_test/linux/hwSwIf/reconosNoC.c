#include <pthread.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#define __USE_GNU
#include <sys/time.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include "reconos.h"
#include "mbox.h"

#include "reconosNoC.h"

#include "packetList.h"
#include "bytePacket.h"


// threadControlThread
void* threadControlThreadMain(void*);
void threadControlThreadTerminateHw2SwThreads(reconosNoChw2swInterface* interface);
void threadControlThreadTerminateSw2HwThreads(reconosNoCsw2hwInterface* interface);

// called by all sw threads on error exit
void basicThreadCleanup(void* arg);

// ceil a byte address to the start of the next word
uint32_t ceilToWordAddress(uint32_t byteAddress);


////////////////////////////////////////////////////////////
//////// SW -> HW Interface
////////////////////////////////////////////////////////////

// create interface
int createSw2HwInterface(reconosNoC* nocPtr);

// SW to HW packetProcessingThread
void* sw2hwPacketProcessingThreadMain(void*);
int   sw2hwPacketProcessingThreadEnoughSpaceForPacket(reconosNoCsw2hwInterface* interface, reconosNoCPacket* newPacket);
int   sw2hwPacketProcessingThreadIsAlmostFull(reconosNoCsw2hwInterface* interface);
int   sw2hwPacketProcessingThreadWritePacketToRingBuffer(reconosNoCsw2hwInterface* interface, reconosNoCPacket* newPacket);
int   sw2hwPacketProcessingThreadWriteIntegerToCharArray(char* array, uint32_t value, uint32_t startOffset, uint32_t* endOffset);

// timerThread
void* sw2hwTimerThreadMain(void*);

// pointerExchangeThread
void* sw2hwPointerExchangeThreadMain(void*);




////////////////////////////////////////////////////////////
//////// HW -> SW Interface
////////////////////////////////////////////////////////////

// create interface
int createHw2SwInterface(reconosNoC* nocPtr);

// pointerExchangeThread
void* hw2swPointerExchangeThreadMain(void*);
int hw2swPointerExchangeThreadDecodePacket(char* packetBytes, uint32_t packetLength, reconosNoCPacket** decodedPacket);

// packetProcessingThread
void* hw2swPacketProcessingThreadMain(void*);


////////////////////////////////////////////////////////////
//////// Debug output
////////////////////////////////////////////////////////////

#ifdef RECONOS_NOC_VERBOSE

#define RECONOS_NOC_PRINT(text) printDebugOutput(text);
#define RECONOS_NOC_PRINT_INT(text, number) printDebugOutputInt(text, number);
#define RECONOS_NOC_PRINT_RINGBUFFER_DUMP(type, interface) printRingbufferDump(type, interface);

void printDebugOutput(char* text)
{
	printf(text);
	fflush(stdout);
}

void printDebugOutputInt(char* text, int i)
{
	printf(text, i);
	fflush(stdout);
}

void printRingbufferDump(int type, void* interface)
{
	char* ringBuffer;
	uint32_t readOffset, writeOffset;
	printf("\n\n____________________\n");
	if(type == 0)
	{
		printf("HW -> SW ring buffer\n");
		reconosNoChw2swInterface* hw2swInterface = (reconosNoChw2swInterface*)interface;
		ringBuffer = hw2swInterface->ringBufferBaseAddr;
		readOffset = hw2swInterface->readOffset;
		writeOffset = hw2swInterface->writeOffset;
	}
	else
	{
		printf("SW -> HW ring buffer\n");
		reconosNoCsw2hwInterface* sw2hwInterface = (reconosNoCsw2hwInterface*)interface;
		ringBuffer = sw2hwInterface->ringBufferBaseAddr;
		readOffset = sw2hwInterface->readOffset;
		writeOffset = sw2hwInterface->writeOffset;
	}
	printf("Read Offset: %i\n", readOffset);
	printf("Write Offset: %i\n", writeOffset);
	int i;
	for(i=0; i<RING_BUFFER_SIZE; i++)
		printf("%i:\t%x\n", i, (0xFF & ringBuffer[i]));
	printf("\n");
	fflush(stdout);
}

#else

#define RECONOS_NOC_PRINT(text)
#define RECONOS_NOC_PRINT_INT(text, number)
#define RECONOS_NOC_PRINT_RINGBUFFER_DUMP(type, interface)

#endif

////////////////////////////////////////////////////////////
//////// Implementation
////////////////////////////////////////////////////////////

int reconosNoCInit(reconosNoC** ptrToNocPtr)
{
	int errCode;

	reconosNoC* nocPtr = malloc(sizeof(reconosNoC));
	if(!nocPtr)
		return -ENOMEM;
	*ptrToNocPtr = nocPtr;

	sem_init(&nocPtr->killThreadsSem, 0, 0);

	errCode = pthread_create(&nocPtr->threadControlThread, NULL, threadControlThreadMain, nocPtr);
	if(errCode)
		return errCode;
	RECONOS_NOC_PRINT("ReconosNoC: started thread control thread\n");

	errCode = createSw2HwInterface(nocPtr);
	if(errCode)
	{
		sem_post(&nocPtr->killThreadsSem);
		return errCode;
	}

	errCode = createHw2SwInterface(nocPtr);
	if(errCode)
	{
		sem_post(&nocPtr->killThreadsSem);
		return errCode;
	}

	return 0;
}

int reconosNoCSendPacket(reconosNoC* nocPtr, reconosNoCPacket* packet)
{
	int errCode;

	if(!nocPtr || !packet)
		return -EINVAL;

	if(!packet->payloadLength)
		return -EINVAL;

	if(!packet->payload)
		return -EINVAL;

	reconosNoCsw2hwInterface* interface = nocPtr->sw2hwInterface;

	RECONOS_NOC_PRINT("reconosNoCSendPacket: Adding a new packet to the queue\n");
	pthread_mutex_lock(&interface->packetListManipulateMutex);
	errCode = packetListAdd(&interface->packetsToProcess, packet);
	pthread_mutex_unlock(&interface->packetListManipulateMutex);
	if(errCode)
		return errCode;

	RECONOS_NOC_PRINT("reconosNoCSendPacket: Signaling that a new packet is ready to be processed\n");
	sem_post(&nocPtr->sw2hwInterface->processOnePacketSem);
	return 0;
}

int createSw2HwInterface(reconosNoC* nocPtr)
{
	int errCode;

	reconosNoCsw2hwInterface* interface = malloc(sizeof(reconosNoCsw2hwInterface));
	nocPtr->sw2hwInterface = interface;

	if(!interface)
		return -ENOMEM;
	memset(interface, 0, sizeof(interface));
	RECONOS_NOC_PRINT("SW -> HW: Allocated memory for interface\n");

	// create the ring buffer
	interface->ringBufferBaseAddr = valloc(RING_BUFFER_SIZE);
	if(!interface->ringBufferBaseAddr)
		return -ENOMEM;
	RECONOS_NOC_PRINT("SW -> HW: Allocated memory for ring buffer\n");

	// init the conditions
	pthread_cond_init(&interface->abortTimerCond, NULL);
	pthread_cond_init(&interface->exchangePointersCond, NULL);
	pthread_cond_init(&interface->offsetUpdateCond, NULL);
	pthread_cond_init(&interface->startTimerCond, NULL);
	RECONOS_NOC_PRINT("SW -> HW: Initialized conditions\n");

	// init the mutexes
	pthread_mutex_init(&interface->timerMutex, NULL);
	pthread_mutex_init(&interface->pointersMutex, NULL);
	pthread_mutex_init(&interface->packetListManipulateMutex, NULL);
	RECONOS_NOC_PRINT("SW -> HW: Initialized mutexes\n");

	// init the semaphores
	errCode = sem_init(&interface->processOnePacketSem, 0, 0);
	if(errCode)
		return errCode;
	errCode = sem_init(&interface->hardwareThreadReadySem, 0, 0);
		if(errCode)
			return errCode;
	RECONOS_NOC_PRINT("SW -> HW: Initialized semaphores\n");

	// init mbox put
	errCode = mbox_init(&interface->mb_put, MBOX_SIZE);
	if(errCode)
		return errCode;
	interface->res[0].type = RECONOS_TYPE_MBOX;
	interface->res[0].ptr  = &interface->mb_put;
	RECONOS_NOC_PRINT("SW -> HW: Initialized mbox_put\n");

	// init mbox get
	errCode = mbox_init(&interface->mb_get, MBOX_SIZE);
	if(errCode)
		return errCode;
	interface->res[1].type = RECONOS_TYPE_MBOX;
	interface->res[1].ptr  = &interface->mb_get;
	RECONOS_NOC_PRINT("SW -> HW: Initialized mbox_get\n");

	// start the hardware thread
	reconos_hwt_setresources(&interface->hwt, interface->res, 2);
	reconos_hwt_create(&interface->hwt, 1, NULL);
	RECONOS_NOC_PRINT("SW -> HW: Hardware thread started\n");

	// tell the hardware thread the base address of the ring buffer
	mbox_put(&interface->mb_put, (uint32)(interface->ringBufferBaseAddr));
	RECONOS_NOC_PRINT("SW -> HW: Initialized ring buffer base address in hardware thread\n");

	// start the software threads
	errCode = pthread_create(&interface->pointerExchangeThread, NULL, sw2hwPointerExchangeThreadMain, nocPtr);
	if(errCode)
		return errCode;
	RECONOS_NOC_PRINT("SW -> HW: started pointer exchange thread\n");
	errCode = pthread_create(&interface->timerThread, NULL, sw2hwTimerThreadMain, nocPtr);
	if(errCode)
		return errCode;
	RECONOS_NOC_PRINT("SW -> HW: started timer thread\n");
	errCode = pthread_create(&interface->packetProcessingThread, NULL, sw2hwPacketProcessingThreadMain, nocPtr);
	if(errCode)
		return errCode;
	RECONOS_NOC_PRINT("SW -> HW: started packet processing thread\n");

	return 0;
}

int createHw2SwInterface(reconosNoC* nocPtr)
{
	int errCode;

	reconosNoChw2swInterface* interface = malloc(sizeof(reconosNoChw2swInterface));
	nocPtr->hw2swInterface = interface;

	if(!interface)
		return -ENOMEM;
	memset(interface, 0, sizeof(interface));
	RECONOS_NOC_PRINT("HW -> SW: Allocated memory for interface\n");

	// create the ring buffer
	interface->ringBufferBaseAddr = valloc(RING_BUFFER_SIZE);
	if(!interface->ringBufferBaseAddr)
		return -ENOMEM;
	RECONOS_NOC_PRINT("HW -> SW: Allocated memory for ring buffer\n");

	// init the semaphores
	errCode = sem_init(&interface->packetsToProcessSem, 0, 0);
	if(errCode)
		return errCode;
	errCode = sem_init(&interface->hardwareThreadReadySem, 0, 0);
	if(errCode)
		return errCode;
	RECONOS_NOC_PRINT("HW -> SW: Initialized semaphores\n");

	// init the mutexes
	pthread_mutex_init(&interface->packetHandlerListMutex, NULL);
	pthread_mutex_init(&interface->packetListManipulateMutex, NULL);
	RECONOS_NOC_PRINT("SW -> HW: Initialized mutexes\n");

	// init the packet handler list
	interface->packetHandlerListHead = NULL;

	// init mbox put
	errCode = mbox_init(&interface->mb_put, MBOX_SIZE);
	if(errCode)
		return errCode;
	interface->res[0].type = RECONOS_TYPE_MBOX;
	interface->res[0].ptr  = &interface->mb_put;
	RECONOS_NOC_PRINT("HW -> SW: Initialized mbox_put\n");

	// init mbox get
	errCode = mbox_init(&interface->mb_get, MBOX_SIZE);
	if(errCode)
		return errCode;
	interface->res[1].type = RECONOS_TYPE_MBOX;
	interface->res[1].ptr  = &interface->mb_get;
	RECONOS_NOC_PRINT("HW -> SW: Initialized mbox_get\n");

	// start the hardware thread
	reconos_hwt_setresources(&interface->hwt, interface->res, 2);
	reconos_hwt_create(&interface->hwt, 0, NULL);
	RECONOS_NOC_PRINT("HW -> SW: Hardware thread started\n");

	// tell the hardware thread the base address of the ring buffer
	mbox_put(&interface->mb_put, (uint32)(interface->ringBufferBaseAddr));
	RECONOS_NOC_PRINT("HW -> HW: Initialized ring buffer base address in hardware thread\n");

	// start the software threads
	errCode = pthread_create(&interface->pointerExchangeThread, NULL, hw2swPointerExchangeThreadMain, nocPtr);
	if(errCode)
		return errCode;
	RECONOS_NOC_PRINT("HW -> SW: pointer exchange thread started\n");
	errCode = pthread_create(&interface->packetProcessingThread, NULL, hw2swPacketProcessingThreadMain, nocPtr);
	if(errCode)
		return errCode;
	RECONOS_NOC_PRINT("HW -> SW: packet processing thread thread started\n");

	return 0;
}

int reconosNoCStop(reconosNoC* nocPtr)
{
	sem_post(&nocPtr->killThreadsSem);
	// TODO: Implement cleanup stuff!!!
	return 0;
}

void* sw2hwPacketProcessingThreadMain(void* arg)
{
	int errCode;

	reconosNoC* nocPtr = (reconosNoC*)arg;
	reconosNoCsw2hwInterface* interface = nocPtr->sw2hwInterface;
	pthread_cleanup_push(basicThreadCleanup, nocPtr);

	while(1)
	{
		// wait for a new packet
		RECONOS_NOC_PRINT("SW -> HW (packetProcessingThread): waiting for a new packet\n");
		sem_wait(&interface->processOnePacketSem);
		RECONOS_NOC_PRINT("SW -> HW (packetProcessingThread): processing a new packet\n");

		// ensure that the timer does not change its status
		RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): attempting to lock timer mutex\n");
		pthread_mutex_lock(&interface->timerMutex);
		RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): attempting to lock timer mutex ...done!\n");

		// ensure that the readPointer and writePointer do not change their value
		RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): attempting to lock pointer mutex\n");
		pthread_mutex_lock(&interface->pointersMutex);
		RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): attempting to lock pointer mutex ...done!\n");

		// get the first packet from the queue
		reconosNoCPacket* newPacket = NULL;
		pthread_mutex_lock(&interface->packetListManipulateMutex);
		errCode = packetListPoll(&interface->packetsToProcess, &newPacket);
		pthread_mutex_unlock(&interface->packetListManipulateMutex);
		if(errCode)
			pthread_exit((int*)errCode);
		RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): fetched packet from queue\n");

		// verify that there is enough space in the ring buffer to write the new packet
		while(!sw2hwPacketProcessingThreadEnoughSpaceForPacket(interface, newPacket))
		{
			RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): not enough space in the ring buffer for the packet, waiting for offset update signal\n");
			pthread_cond_wait(&interface->offsetUpdateCond, &interface->pointersMutex);
			RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): received offset update signal\n");
		}
		RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): there is enough space in the ring buffer for the packet\n");

		// write the packet into the ring buffer
		errCode = sw2hwPacketProcessingThreadWritePacketToRingBuffer(interface, newPacket);
		if(errCode)
			pthread_exit((int*)errCode);
		RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): written packet into ring buffer\n");
		RECONOS_NOC_PRINT_RINGBUFFER_DUMP(1, interface);

		// if we need to immediately send the write pointer to the hardware thread
		if(newPacket->latencyCritical || sw2hwPacketProcessingThreadIsAlmostFull(interface))
		{
			RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): The packet is urgent\n");

			// stop the timer if its currently running
			if(interface->timerRunning)
			{
				interface->timerRunning = 0;
				pthread_cond_signal(&interface->abortTimerCond);
			}

			// prevent the timer from starting again
			interface->startTimer = 0;

			// mark the write pointer as dirty
			interface->writePointerDirty = 1;

			// wake up the pointer exchange thread
			pthread_cond_signal(&interface->exchangePointersCond);
			RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): decided to immediately exchange write pointer\n");
		}
		else // if exchange of write pointer is not that urgent
		{
			RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): The packet is not urgent\n");

			// start the timer if it's not currently running
			if(!interface->timerRunning)
			{
				RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): decided to start timer\n");
				interface->startTimer = 1;
				pthread_cond_signal(&interface->startTimerCond);
				RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): timer started\n");
			}
		}

		// now the readPointer and writePointer may again change their value
		RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): unlocking pointers mutex\n");
		pthread_mutex_unlock(&interface->pointersMutex);

		// now the timer may again change its status
		RECONOS_NOC_PRINT("SW -> HW interface (packetProcessingThread): unlocking timer mutex\n");
		pthread_mutex_unlock(&interface->timerMutex);

		free(newPacket);
		newPacket = NULL;
	}

	pthread_cleanup_pop(0);
	return 0;
}

int sw2hwPacketProcessingThreadEnoughSpaceForPacket(reconosNoCsw2hwInterface* interface, reconosNoCPacket* newPacket)
{
	int freeSpace = ((RING_BUFFER_SIZE + interface->readOffset - interface->writeOffset -1) % RING_BUFFER_SIZE)-8;
	int packetSize = ceilToWordAddress(newPacket->payloadLength + HEADER_SIZE + 4);
	//printf("free space: %i, packet size: %i\n", freeSpace, packetSize);

	if(freeSpace > packetSize)
		return 1;

	return 0;
}

int sw2hwPacketProcessingThreadIsAlmostFull(reconosNoCsw2hwInterface* interface)
{
	int hwWriteOffsetBytes = interface->hwWriteOffset*4;
	int freeSpace = (RING_BUFFER_SIZE + hwWriteOffsetBytes - interface->writeOffset -1) % RING_BUFFER_SIZE;

	if(freeSpace >= ALMOST_FULL_TRESHOLD)
		return 0;

	return 1;
}

int sw2hwPacketProcessingThreadWritePacketToRingBuffer(reconosNoCsw2hwInterface* interface, reconosNoCPacket* newPacket)
{
	char* ringBuffer = interface->ringBufferBaseAddr;
	uint32_t writeOffset = interface->writeOffset;

	// write the packetLength
	uint32_t packetLength = newPacket->payloadLength + HEADER_SIZE;
	sw2hwPacketProcessingThreadWriteIntegerToCharArray(ringBuffer, packetLength, writeOffset, &writeOffset);

	// write header byte 1
	char headerByte1 = (newPacket->hwAddrGlobal & GLOBAL_ADDR_MASK) << GLOBAL_ADDR_OFFSET;
	headerByte1 |= (newPacket->hwAddrLocal & LOCAL_ADDR_MASK) << LOCAL_ADDR_OFFSET;
	headerByte1 |= (newPacket->priority & PRIORITY_MASK) << PRIORITY_OFFSET;
	ringBuffer[writeOffset] = headerByte1;
	writeOffset = (writeOffset + 1) % RING_BUFFER_SIZE;

	// write header byte 2
	char headerByte2 = (newPacket->direction & DIRECTION_MASK) << DIRECTION_OFFSET;
	headerByte2 |= (newPacket->latencyCritical & LATENCY_CRITICAL_MASK) << LATENCY_CRITICAL_OFFSET;
	ringBuffer[writeOffset] = headerByte2;
	writeOffset = (writeOffset + 1) % RING_BUFFER_SIZE;

	// write source IDP
	sw2hwPacketProcessingThreadWriteIntegerToCharArray(ringBuffer, newPacket->srcIdp, writeOffset, &writeOffset);

	// write destination IDP
	sw2hwPacketProcessingThreadWriteIntegerToCharArray(ringBuffer, newPacket->dstIdp, writeOffset, &writeOffset);

	// write the actual payload
	if(writeOffset + newPacket->payloadLength <= RING_BUFFER_SIZE)
	{
		memcpy(&ringBuffer[writeOffset], newPacket->payload, newPacket->payloadLength);
		writeOffset = (writeOffset + newPacket->payloadLength) % RING_BUFFER_SIZE;
	}
	else
	{
		uint32_t lengthPart1 = RING_BUFFER_SIZE - writeOffset;
		uint32_t lengthPart2 = newPacket->payloadLength - lengthPart1;
		memcpy(&ringBuffer[writeOffset], newPacket->payload, lengthPart1);
		memcpy(ringBuffer, &newPacket->payload[lengthPart1], lengthPart2);
		writeOffset = lengthPart2 % RING_BUFFER_SIZE;
	}

	// align the write offset with the beginning of the next word
	writeOffset = ceilToWordAddress(writeOffset) % RING_BUFFER_SIZE;
	interface->writeOffset = writeOffset;

	return 0;
}

int sw2hwPacketProcessingThreadWriteIntegerToCharArray(char* array, uint32_t value, uint32_t startOffset, uint32_t* endOffset)
{
	array[startOffset] = (char)(value >> 24);
	startOffset = (startOffset + 1) % RING_BUFFER_SIZE;
	array[startOffset] = (char)(value >> 16);
	startOffset = (startOffset + 1) % RING_BUFFER_SIZE;
	array[startOffset] = (char)(value >> 8);
	startOffset = (startOffset + 1) % RING_BUFFER_SIZE;
	array[startOffset] = (char)value;
	startOffset = (startOffset + 1) % RING_BUFFER_SIZE;

	*endOffset = startOffset;
	return 0;
}

void* sw2hwTimerThreadMain(void* arg)
{
	int errCode;

	reconosNoC* nocPtr = (reconosNoC*) arg;
	reconosNoCsw2hwInterface* interface = nocPtr->sw2hwInterface;
	pthread_cleanup_push(basicThreadCleanup, nocPtr);

	RECONOS_NOC_PRINT("SW -> HW interface (timerThread): attempting to lock timer mutex\n");
	pthread_mutex_lock(&interface->timerMutex);
	RECONOS_NOC_PRINT("SW -> HW interface (timerThread): attempting to lock timer mutex ...done!\n");

	while(1)
	{
		// wait for the command to start the timer
		while(1)
		{
			RECONOS_NOC_PRINT("SW -> HW interface (timerThread): timer ready to start\n");
			// do this check even when waked up by a signal because between sending event
			// and the wake up event, someone else could have allready canceled the timer start
			if(interface->startTimer)
				break;
			pthread_cond_wait(&interface->startTimerCond, &interface->timerMutex);
		}
		interface->startTimer = 0;
		RECONOS_NOC_PRINT("SW -> HW interface (timerThread): setting up timer\n");

		// make the state transition visible
		interface->timerRunning = 1;

		// calculate the time, when the timer should wake up
		struct timeval startTime;
		errCode = gettimeofday(&startTime, NULL);
		if(errCode)
			pthread_exit((int*)errCode);
		struct timeval timeoutDurationTime;
		timeoutDurationTime.tv_usec = TIMEOUT_DURATION_MICROSEC;
		timeoutDurationTime.tv_sec = TIMEOUT_DURATION_SEC;
		struct timeval endTime;
		timeradd(&startTime, &timeoutDurationTime, &endTime);
		struct timespec endTimeSpec;
		TIMEVAL_TO_TIMESPEC(&endTime, &endTimeSpec);

		// wait until the specified time
		RECONOS_NOC_PRINT("SW -> HW interface (timerThread): entering timedwait\n");
		pthread_cond_timedwait(&interface->abortTimerCond, &interface->timerMutex, &endTimeSpec);
		RECONOS_NOC_PRINT("SW -> HW interface (timerThread): leaving timedwait\n");
		if(interface->timerRunning) // if nobody has aborded the timer
		{
			RECONOS_NOC_PRINT("SW -> HW interface (timerThread): attempting to lock pointers mutex\n");
			pthread_mutex_lock(&interface->pointersMutex);
			RECONOS_NOC_PRINT("SW -> HW interface (timerThread): attempting to lock pointers mutex ...done!\n");

			// signal that the write pointer should now be written to the hardware
			interface->writePointerDirty = 1;
			RECONOS_NOC_PRINT("SW -> HW interface (timerThread): signal exchange pointers\n");
			pthread_cond_signal(&interface->exchangePointersCond);
			RECONOS_NOC_PRINT("SW -> HW interface (timerThread): unlocking pointers mutex\n");
			pthread_mutex_unlock(&interface->pointersMutex);
		}
		interface->timerRunning = 0;
	}
	// never reached
	pthread_cleanup_pop(0);
	return 0;
}

void* sw2hwPointerExchangeThreadMain(void* arg)
{
	reconosNoC* nocPtr = (reconosNoC*)arg;
	reconosNoCsw2hwInterface* interface = nocPtr->sw2hwInterface;
	pthread_cleanup_push(basicThreadCleanup, nocPtr);

	RECONOS_NOC_PRINT("SW -> HW interface (pointerExchangeThread): attempting to lock pointer mutex\n");
	pthread_mutex_lock(&interface->pointersMutex);
	RECONOS_NOC_PRINT("SW -> HW interface (pointerExchangeThread): attempting to lock pointer mutex ...done!\n");

	while(1)
	{
		RECONOS_NOC_PRINT("SW -> HW interface (pointerExchangeThread): ready to accept 'exchange pointers' command\n");
		// wait until the write offset should be written to the hardware
		if(!interface->writePointerDirty)
		{
			RECONOS_NOC_PRINT("SW -> HW interface (pointerExchangeThread): waiting for exchange pointers signal\n");
			pthread_cond_wait(&interface->exchangePointersCond, &interface->pointersMutex);
			RECONOS_NOC_PRINT("SW -> HW interface (pointerExchangeThread): received exchange pointers signal\n");
		}
		interface->writePointerDirty = 0;

		// fetch the current write offset (cast from byte to word offset)
		interface->hwWriteOffset = interface->writeOffset/4;
		RECONOS_NOC_PRINT("SW -> HW interface (pointerExchangeThread): release pointer mutex\n");
		pthread_mutex_unlock(&interface->pointersMutex);

		// write the fetched write offset to the hardware
		RECONOS_NOC_PRINT_INT("SW -> HW interface (pointerExchangeThread): sending write pointer %i to hardware\n", interface->hwWriteOffset);
		mbox_put(&interface->mb_put, interface->hwWriteOffset);

		// wait for the answer from the software (this takes relatively long)
		RECONOS_NOC_PRINT("SW -> HW interface (pointerExchangeThread): waiting for read pointer from hardware\n");
		uint32_t hwReadOffset = mbox_get(&interface->mb_get);
		RECONOS_NOC_PRINT_INT("SW -> HW interface (pointerExchangeThread): received read pointer %i from hardware\n", hwReadOffset);

		// write the received read pointer to the interface and signal the change event
		RECONOS_NOC_PRINT("SW -> HW interface (pointerExchangeThread): attempting to lock pointer mutex\n");
		pthread_mutex_lock(&interface->pointersMutex);
		RECONOS_NOC_PRINT("SW -> HW interface (pointerExchangeThread): attempting to lock pointer mutex ...done!\n");
		interface->readOffset = hwReadOffset*4;
		RECONOS_NOC_PRINT("SW -> HW interface (pointerExchangeThread): signaling that the read offset has changed\n");
		pthread_cond_signal(&interface->offsetUpdateCond);
	}
	// never reached
	pthread_cleanup_pop(0);
	return 0;
}

void basicThreadCleanup(void* arg)
{
	printf("ERROR: Thread terminated unexpected, shutting down all threads!\n");
	sem_post(&((reconosNoC*)arg)->killThreadsSem);
}

void* threadControlThreadMain(void* arg)
{
	reconosNoC* nocPtr = (reconosNoC*)arg;
	sem_wait(&nocPtr->killThreadsSem);

	threadControlThreadTerminateSw2HwThreads(nocPtr->sw2hwInterface);
	threadControlThreadTerminateHw2SwThreads(nocPtr->hw2swInterface);

	// free the ring buffers
	if(nocPtr->sw2hwInterface->ringBufferBaseAddr)
		free(nocPtr->sw2hwInterface->ringBufferBaseAddr);
	if(nocPtr->hw2swInterface->ringBufferBaseAddr)
	free(nocPtr->hw2swInterface->ringBufferBaseAddr);

	// free the interfaces
	if(nocPtr->sw2hwInterface)
		free(nocPtr->sw2hwInterface);
	if(nocPtr->hw2swInterface)
		free(nocPtr->hw2swInterface);

	if(nocPtr)
		free(nocPtr);

	return 0;
}

void threadControlThreadTerminateSw2HwThreads(reconosNoCsw2hwInterface* interface)
{
	if(!interface)
		return;

	pthread_cancel(interface->pointerExchangeThread);
	pthread_cancel(interface->timerThread);
	pthread_cancel(interface->packetProcessingThread);

	int* retval;
	pthread_join(interface->pointerExchangeThread, (void**)&retval);
	if(retval != PTHREAD_CANCELED)	{
		printf("SW -> HW interface: pointerExchangeThread terminated with error code %i\n", *retval);
	}

	pthread_join(interface->timerThread, (void**)&retval);
	if(retval != PTHREAD_CANCELED)	{
		printf("SW -> HW interface: timerThread terminated with error code %i\n", *retval);
	}

	pthread_join(interface->packetProcessingThread, (void**)&retval);
	if(retval != PTHREAD_CANCELED)	{
		printf("SW -> HW interface: packetProcessingThread terminated with error code %i\n", *retval);
	}
}

void threadControlThreadTerminateHw2SwThreads(reconosNoChw2swInterface* interface)
{
	if(!interface)
		return;

	pthread_cancel(interface->pointerExchangeThread);
	pthread_cancel(interface->packetProcessingThread);

	int* retval;
	pthread_join(interface->pointerExchangeThread, (void**)&retval);
	if(retval != PTHREAD_CANCELED)	{
		printf("HW -> SW interface: pointerExchangeThread terminated with error code %i\n", *retval);
	}

	pthread_join(interface->packetProcessingThread, (void**)&retval);
	if(retval != PTHREAD_CANCELED)	{
		printf("HW -> SW interface: packetProcessingThread terminated with error code %i\n", *retval);
	}
}

void* hw2swPointerExchangeThreadMain(void* arg)
{
	RECONOS_NOC_PRINT("HW -> SW interface (pointerExchangeThread): thread entered\n");
	reconosNoC* nocPtr = (reconosNoC*)arg;
	reconosNoChw2swInterface* interface = nocPtr->hw2swInterface;
	pthread_cleanup_push(basicThreadCleanup, nocPtr);

	while(1)
	{
		// ----------------------------------------------------------
		// Start of temporary code

		// Read the packet bytes
		int packetSize = 0;
		bytePacket* tail = NULL;
		uint32_t currentByte;
		do{
			currentByte = mbox_get(&interface->mb_get);
			bytePacket* newBytePacketElement = malloc(sizeof(bytePacket));
			newBytePacketElement->value = (char)currentByte;
			newBytePacketElement->next = tail;
			tail = newBytePacketElement;
			packetSize++;
		} while((currentByte & 0x100) == 0);

		// create array from list
		char* byteArray = malloc(packetSize);
		int i;
		for(i=packetSize-1; i>=0; i--)
		{
			bytePacket* current = tail;
			byteArray[i] = current->value;
			tail = current->next;
			free(current);
		}

		// End of temporary code
		// ----------------------------------------------------------

		// create a new packet with the read bytes
		reconosNoCPacket* newPacket;
		hw2swPointerExchangeThreadDecodePacket(byteArray, packetSize, &newPacket);
		free(byteArray);

		// add the new packet to the 'packets to process' list
		pthread_mutex_lock(&interface->packetListManipulateMutex);
		packetListAdd(&interface->packetsToProcess, newPacket);
		pthread_mutex_unlock(&interface->packetListManipulateMutex);
		sem_post(&interface->packetsToProcessSem);
	}

	// never reached
	pthread_cleanup_pop(0);
	return 0;
}

int hw2swPointerExchangeThreadDecodePacket(char* packetBytes, uint32_t packetLength, reconosNoCPacket** decodedPacket)
{
	reconosNoCPacket* newPacket = malloc(sizeof(reconosNoCPacket));
	if(!newPacket)
		return -ENOMEM;

	// header byte 1
	newPacket->hwAddrGlobal = (packetBytes[0] & GLOBAL_ADDR_MASK) >> GLOBAL_ADDR_OFFSET;
	newPacket->hwAddrLocal = (packetBytes[0] & LOCAL_ADDR_MASK) >> LOCAL_ADDR_OFFSET;
	newPacket->priority = (packetBytes[0] & PRIORITY_MASK) >> PRIORITY_OFFSET;

	// header byte 2
	newPacket->direction = (packetBytes[1] & DIRECTION_MASK) >> DIRECTION_OFFSET;
	newPacket->latencyCritical = (packetBytes[1] & LATENCY_CRITICAL_MASK) >> LATENCY_CRITICAL_OFFSET;

	// src IDP
	newPacket->srcIdp = packetBytes[2];
	int i;
	for(i=1; i<4; i++)
	{
		newPacket->srcIdp = newPacket->srcIdp << 8;
		newPacket->srcIdp |= packetBytes[i+2];
	}

	// dst IDP
	newPacket->dstIdp = packetBytes[2];
	for(i=1; i<4; i++)
	{
		newPacket->dstIdp = newPacket->dstIdp << 8;
		newPacket->dstIdp |= packetBytes[i+2];
	}

	// payload
	newPacket->payloadLength = packetLength - HEADER_SIZE;
	newPacket->payload = malloc(newPacket->payloadLength);
	memcpy(newPacket->payload, packetBytes+HEADER_SIZE, newPacket->payloadLength);

	*decodedPacket = newPacket;

	return 0;
}

void* hw2swPacketProcessingThreadMain(void* arg)
{
	int errCode;

	reconosNoC* nocPtr = (reconosNoC*)arg;
	reconosNoChw2swInterface* interface = nocPtr->hw2swInterface;
	pthread_cleanup_push(basicThreadCleanup, nocPtr);

	while(1)
	{
		sem_wait(&interface->packetsToProcessSem);

		reconosNoCPacket* currentPacket;
		pthread_mutex_lock(&interface->packetListManipulateMutex);
		errCode = packetListPoll(&interface->packetsToProcess, &currentPacket);
		if(errCode)
			pthread_exit((int*)errCode);
		pthread_mutex_unlock(&interface->packetListManipulateMutex);

		pthread_mutex_lock(&interface->packetHandlerListMutex);
		packetHandlerListElement* head = interface->packetHandlerListHead;
		while(head)
		{
			errCode = head->handler(currentPacket);
			if(errCode)
				pthread_exit((int*)errCode);
			head = head->next;
		}
		pthread_mutex_unlock(&interface->packetHandlerListMutex);
	}

	// never reached
	pthread_cleanup_pop(0);
	return 0;
}


uint32_t ceilToWordAddress(uint32_t byteAddress)
{
	uint32_t result = byteAddress;
	while(result%4 != 0)
		result = result + 1;
	return result;
}

int reconosNoCRegisterPacketReceptionHandler(reconosNoC* nocPtr, int (*newHandler)(reconosNoCPacket*))
{
	packetHandlerListElement* newElement = malloc(sizeof(packetHandlerListElement));
	if(!newElement)
		return -ENOMEM;
	newElement->handler = newHandler;

	pthread_mutex_lock(&nocPtr->hw2swInterface->packetHandlerListMutex);
	newElement->next = nocPtr->hw2swInterface->packetHandlerListHead;
	nocPtr->hw2swInterface->packetHandlerListHead = newElement;
	pthread_mutex_unlock(&nocPtr->hw2swInterface->packetHandlerListMutex);

	return 0;
}
