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
#include "config.h"

#define PAGE_SIZE 4096
#define PAGE_WORDS 1024
#define PAGE_MASK 0xFFFFF000
#define PAGES_PER_THREAD 2

#define BLOCK_SIZE PAGE_SIZE*PAGES_PER_THREAD

#define MAX_BURST_SIZE 1023
#define MAX_THREADS 32

#define TO_WORDS(x) ((x)/4)
#define TO_PAGES(x) ((x)/PAGE_SIZE)
#define TO_BLOCKS(x) ((x)/(PAGE_SIZE*PAGES_PER_THREAD))

// hardware threads
struct reconos_resource res[2];
struct reconos_hwt hwt[2];


// mailboxes
struct mbox mb_report;
struct mbox mb_command;

unsigned int* malloc_page_aligned(unsigned int pages)
{
	unsigned int * temp = malloc ((pages+1)*PAGE_SIZE);
	unsigned int * data = (unsigned int*)(((unsigned int)temp / PAGE_SIZE + 1) * PAGE_SIZE);
	return data;
}

// size is given in words, not bytes!
void print_data(unsigned int* data, unsigned int size)
{
	int i;
	for (i=0; i<size; i++)
	{
		printf("(%04d) %04d \t", i, data[i]);
		if ((i+1)%4 == 0) printf("\n");
	}
	printf("\n");
}

void print_mmu_stats()
{
	uint32 hits,misses,pgfaults;

	reconos_mmu_stats(&hits,&misses,&pgfaults);

	printf("MMU stats: TLB hits: %d    TLB misses: %d    page faults: %d\n",hits,misses,pgfaults);
}


int main(int argc, char ** argv)
{
	int i;
	int ret;
	int hw_threads;
	int sw_threads;
	int running_threads;
	int buffer_size;
	int slice_size;

	// we have exactly 3 arguments now...
	hw_threads = 4;
	sw_threads = 0;

	// Base unit is bytes. Use macros TO_WORDS, TO_PAGES and TO_BLOCKS for conversion.
	buffer_size = PAGE_SIZE*PAGES_PER_THREAD;
	slice_size  = PAGE_SIZE*PAGES_PER_THREAD;

	running_threads = hw_threads + sw_threads;

	// init mailboxes
	mbox_init(&mb_command ,20);
	mbox_init(&mb_report,20);

	// init reconos and communication resources
	reconos_init_autodetect();

	res[0].type = RECONOS_TYPE_MBOX;
	res[0].ptr  = &mb_report;
    res[1].type = RECONOS_TYPE_MBOX;
	res[1].ptr  = &mb_command;

	printf("Creating %i hw-threads: ", hw_threads);
	fflush(stdout);
	for (i = 0; i < hw_threads; i++)
	{
	  printf(" %i",i);fflush(stdout);
	  reconos_hwt_setresources(&(hwt[i]),res,2);
	  reconos_hwt_create(&(hwt[i]),i,NULL);
	}
	printf("\n");

	while(1)
	{
		printf("Sending Token");
		fflush(stdout);
		mbox_put(&mb_command, 0);
		mbox_get(&mb_report);
		printf("Received Token");
		fflush(stdout);
		sleep(1);
	}

	// terminate all threads
	printf("Sending terminate message to %i threads:", running_threads);
	fflush(stdout);
	for (i=0; i<running_threads; i++)
	{
	  printf(" %i",i);fflush(stdout);
	  mbox_put(&mb_report,UINT_MAX);
	}
	printf("\n");

	printf("Waiting for termination...\n");
	for (i=0; i<hw_threads; i++)
	{
	  pthread_join(hwt[i].delegate,NULL);
	}
	

	printf("done!\n");
	
	
	return 0;
}

