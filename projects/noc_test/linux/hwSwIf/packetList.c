#include <errno.h>
#include <stdlib.h>
#include <stdio.h>

#include "reconosNoC.h"
#include "packetList.h"

int packetListAdd(packetList* packetList, reconosNoCPacket* newPacket)
{
	if(!packetList || !newPacket)
		return -EINVAL;

	packetListElement* newElement = malloc(sizeof(packetListElement));
	if(!newElement)
		return -ENOMEM;
	newElement->packet = newPacket;
	newElement->next = NULL;

	if(isEmpty(packetList))
	{
		packetList->first = newElement;
		packetList->last = newElement;
	}
	else
	{
		packetList->last->next = newElement;
		packetList->last = newElement;
	}

	return 0;
}

int packetListPoll(packetList* packetList, reconosNoCPacket** ptrToPacketPtr)
{
	if(isEmpty(packetList))
		return -ENODATA;

	reconosNoCPacket* packet = NULL;

	packetListElement* firstElement = packetList->first;
	packet = firstElement->packet;
	packetList->first = firstElement->next;
	free(firstElement);

	*ptrToPacketPtr = packet;
	return 0;
}

int isEmpty(packetList* packetList)
{
	if(!packetList)
		return 1;
	if(!packetList->first)
		return 1;

	return 0;
}
