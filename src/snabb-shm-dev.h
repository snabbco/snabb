/*
 *  Shared memory network adapter.
 *  Copyright (C) 2012 Snabb GmbH
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU General Public License for more details.
 */

/*
 * NOTE: This header file is written in the LuaJIT-friendly C subset.
 */

enum {
    SHM_RING_SIZE = 8,
    SHM_PACKET_SIZE = 1600
};

struct shm_packet
{
    char data[SHM_PACKET_SIZE];
    uint32_t length;
} __attribute__((packed));

struct shm_ring
{
    uint32_t head;
    uint32_t tail;
    struct shm_packet packets[SHM_RING_SIZE];
} __attribute__((packed));

struct snabb_shm_dev
{
    uint32_t magic;
    uint32_t version;
    struct shm_ring vm2host;
    struct shm_ring host2vm;
} __attribute__((packed));

