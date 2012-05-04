#ifndef PACKETHANDLERLIST_H
#define PACKETHANDLERLIST_H

#include "reconosNoC.h"

typedef struct packetHandlerListElement{
	int (*handler)(reconosNoCPacket*);
	struct packetHandlerListElement* next;
}packetHandlerListElement;


#endif /* PACKETHANDLERLIST_H */
