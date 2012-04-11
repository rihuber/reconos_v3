#include "reconos.h"
#include "mbox.h"

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <assert.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <limits.h>
#include <string.h>


#define MAX_THREADS 32
#define MBOX_SIZE 20

// software threads
pthread_t swt[MAX_THREADS];
pthread_attr_t swt_attr[MAX_THREADS];

// hardware threads
struct reconos_resource res[2];
struct reconos_hwt hwt[MAX_THREADS];


// mailboxes
struct mbox mb_start;
struct mbox mb_stop;

int main(int argc, char ** argv)
{
	int i;
	int hw_threads;

	// we have exactly 3 arguments now...
	hw_threads = 4;

	// init mailboxes
	mbox_init(&mb_start,MBOX_SIZE);
	mbox_init(&mb_stop ,MBOX_SIZE);

	// init reconos and communication resources
	reconos_init_autodetect();

	res[0].type = RECONOS_TYPE_MBOX;
	res[0].ptr  = &mb_start;
	res[1].type = RECONOS_TYPE_MBOX;
	res[1].ptr  = &mb_stop;

	printf("Creating %i hw-threads: ", hw_threads);
	fflush(stdout);
	for (i = 0; i < hw_threads; i++)
	{
	  printf(" %i",i);fflush(stdout);
	  reconos_hwt_setresources(&(hwt[i]),res,2);
	  reconos_hwt_create(&(hwt[i]),i,NULL);
	}
	printf("\n");

	int addresses[4];
	addresses[0] = 0;
	addresses[1] = 1;
	addresses[2] = 16;
	addresses[3] = 17;
	i = 0;
	while(1)
	{
		i = (i+1) % 4;

		printf("Waiting");
		fflush(stdout);
		int j;
		for(j=0; j<5; j++)
		{
			printf(".");
			fflush(stdout);
			sleep(1);
		}
		printf("\n");

		printf("Sending command\n");
		fflush(stdout);
		mbox_put(&mb_start,addresses[i]);

		printf("Waiting for answer\n");
		fflush(stdout);
		mbox_get(&mb_stop);
		printf("Answer received\n");

		printf("Waiting for answer\n");
		fflush(stdout);
		mbox_get(&mb_stop);
		printf("Answer received\n");
	}
	
	return 0;
}

