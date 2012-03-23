CC = microblaze-unknown-linux-gnu-gcc
CFLAGS=-O -g -Wall

APP_OBJS = 

all: functional_block

functional_block: $(APP_OBJS)
	$(CC) $(APP_OBJS) $(CFLAGS) -L $(RECONOS)/linux/libreconos -I $(RECONOS)/linux/libreconos functional_block.c -o functional_block -static -lreconos -lpthread -lm -lrt

clean:
	rm -f *.o functional_block 

%.o: %.c
	$(CC) -c $(CFLAGS) -o $@ $<



	
