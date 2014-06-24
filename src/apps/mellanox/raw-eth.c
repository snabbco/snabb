
#include <stdlib.h>
#include <string.h>

#include <infiniband/verbs.h>

static struct ibv_device *
ib_find_device(const char *name)
{
  struct ibv_device **devices;

  devices = ibv_get_device_list(NULL);
  if (!devices) {
    return NULL;
  }

  if (!name) {
    return devices[0];
  }

  for (int i = 0; devices[i]; i++) {
    printf("%s\n", devices[i]->name);
    if (!strcmp(devices[i]->name, name)) {
      return devices[i];
    }
  }

  return NULL;
}

struct mlnx_eth_context {
  struct ibv_context* context;
  struct ibv_comp_channel* channel;
};

struct mlnx_eth_context*
mlnx_eth_allocate_context(const char* device_name)
{
  struct ibv_device* dev = ib_find_device(device_name);

  if (!dev) {
    return 0;
  }
  
  struct mlnx_eth_context* context = calloc(sizeof(*context), 1);
}

void
mlnx_eth_free_context(const struct mlnx_eth_context* context)
{
  free((void*) context);
}
  

int
main(int argc, char **argv)
{
  if (argc != 2) {
    fprintf(stderr, "usage: %s <device>\n", argv[0]);
    exit(1);
  }

  {
    char* device_name = argv[1];
    struct mlnx_eth_context* ctx = mlnx_eth_allocate_context(device_name);
  }
}
