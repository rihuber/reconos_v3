CFLAGS=-O -g -Wall
CC=microblaze-unknown-linux-gnu-gcc

all: semaphore_test

semaphore_test: semaphore_test.c
	$(CC) $(CFLAGS) -L ../../../linux/libreconos -I ../../../linux/libreconos semaphore_test.c -o semaphore_test -static -lreconos -lpthread

clean:
	rm -f *.o semaphore_test 
