CC = microblaze-unknown-linux-gnu-gcc
CFLAGS=-O -g -Wall

APP_OBJS = 

all: clean reconosNoC

reconosNoC: $(APP_OBJS)
	$(CC) $(APP_OBJS) $(CFLAGS) -L $(RECONOS)/linux/libreconos -I $(RECONOS)/linux/libreconos reconosNoC.c packetList.c hwSwIf.c -o reconosNoC -static -lreconos -lpthread -lm -lrt

clean:
	rm -f *.o reconosNoC

%.o: %.c
	$(CC) -c $(CFLAGS) -o $@ $<