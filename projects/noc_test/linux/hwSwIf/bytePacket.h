#ifndef BYTEPACKET_H
#define BYTEPACKET_H

typedef struct bytePacket{
	char value;
	struct bytePacket* next;
}bytePacket;

#endif /* BYTEPACKET_H */
