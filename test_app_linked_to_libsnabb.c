#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>

/*

We should compile this code with flag -dynamic! It's mandatory for exporting symbols to FFI! 
gcc test_app_linked_to_libsnabb.c -rdynamic -Lsrc -lsnabb -lpthread

And run it this way:
LD_LIBRARY_PATH=src ./a.out

*/

uint64_t received_packets = 0;

// This code defined in SnabbSwitch
int start_snabb_switch(int snabb_argc, char **snabb_argv);

inline void firehose_packet(const char *pciaddr, char *data, int length);


/* Intel 82599 "Legacy" receive descriptor format.
 * See Intel 82599 data sheet section 7.1.5.
 * http://www.intel.com/content/dam/www/public/us/en/documents/datasheets/82599-10-gbe-controller-datasheet.pdf
 */
struct firehose_rdesc {
  uint64_t address;
  uint16_t length;
  uint16_t cksum;
  uint8_t status;
  uint8_t errors;
  uint16_t vlan;
} __attribute__((packed));

//typedef int (*firehose_callback_v1_pointer)(const char *pciaddr, char **packets, struct firehose_rdesc *rxring, int ring_size, int index);
//firehose_callback_v1_pointer firehose_callback_v1_ptr;

int firehose_callback_v1(const char *pciaddr,
                         char **packets,
                         struct firehose_rdesc *rxring,
                         int ring_size,
                         int index) {
  while (rxring[index].status & 1) {
    int next_index = (index + 1) & (ring_size-1);
    __builtin_prefetch(packets[next_index]);
    firehose_packet(pciaddr, packets[index], rxring[index].length);
    rxring[index].status = 0; /* reset descriptor for reuse */
    index = next_index;
  }
  return index;
}

void firehose_packet(const char *pciaddr, char *data, int length) {
    __sync_fetch_and_add(&received_packets, 1);
}

void* speed_printer(void* ptr) {
    while (1) {
        uint64_t packets_before = received_packets;
    
        sleep(1);
    
        uint64_t packets_after = received_packets;
        uint64_t pps = packets_after - packets_before;
 
        printf("We process: %llu pps\n", pps);
    }   
}

int main() {
    // We init global variable for passing to LUA core
    // firehose_callback_v1_ptr = &firehose_callback_v1;

    char* cli_arguments[] = {
        "snabb", // emulate call of standard application
        "firehose",
        "--input",
        "0000:02:00.0",
        "--input",
        "0000:02:00.1",
        "weird_data"
    };

    int cli_numbar_of_arguments = sizeof(cli_arguments) / sizeof(char*);

    pthread_t thread;
    pthread_create(&thread, NULL, speed_printer, NULL);
    pthread_detach(thread);

    start_snabb_switch(cli_numbar_of_arguments, cli_arguments);
}
