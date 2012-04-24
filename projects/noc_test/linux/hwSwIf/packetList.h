#ifndef PACKETLIST_H
#define PACKETLIST_H

#include "reconosNoC.h"

typedef struct packetListElement{
	reconosNoCPacket* packet;
	struct packetListElement* next;
}packetListElement;

typedef struct packetList{
	packetListElement* first;
	packetListElement* last;
}packetList;

int packetListAdd(packetList* packetList, reconosNoCPacket* newPacket);
int packetListPoll(packetList* packetList, reconosNoCPacket** ptrToPacketPtr);
int isEmpty(packetList* packetList);

#endif /* PACKETLIST_H */
