/* poll.c - Poll multiple ef_vi interfaces in one FFI call to save on FFI overhead */

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <assert.h>

#include "ef_vi.h"

/* We would like to be able to link this module to snabbswitch without
 * linking the SolarFlare libraries, which is loaded at run time by
 * the SolarFlare app.  Thus we set a pointer to the
 * ef_vi_transmit_unbundle function at run time: */

int (*transmit_unbundle)(ef_vi* ep, const ef_event*, ef_request_id* ids);

#define MAX_DEVICES 256

struct device* devices[MAX_DEVICES];
int n_devices;

void
poll_device(struct device* device) {
  int i;

  device->n_ev = device->vi->ops.eventq_poll(device->vi, device->events, EVENTS_PER_POLL);

  for (i = 0; i < device->n_ev; i++) {
    if (device->events[i].generic.type == EF_EVENT_TYPE_TX) {
      device->unbundled_tx_request_ids[i].n_tx_done = transmit_unbundle(device->vi,
                                                                        &(device->events[i]),
                                                                        device->unbundled_tx_request_ids[i].tx_request_ids);
    }
  }
}

void
poll_devices()
{
  int i;
  for (i = 0; i < n_devices; i++) {
    poll_device(devices[i]);
  }
}

void
add_device(struct device* device, void* unbundle_function)
{
  if (n_devices == MAX_DEVICES) {
    assert(0 == "could not find free device slot");
  }
  devices[n_devices++] = device;

  transmit_unbundle = unbundle_function;
  printf("added device 0x%p\n", device);
}

void
drop_device(struct device* device)
{
  int i;
  for (i = 0; i < n_devices; i++) {
    if (devices[i] == device) {
      break;
    }
  }
  if (i == n_devices) {
    assert(0 == "did not find device to be dropped in devices list");
  }

  n_devices--;
  for (; i < n_devices; i++) {
    devices[i] = devices[i + 1];
  }
  devices[i] = 0;
  printf("dropped device 0x%p\n", device);
}

