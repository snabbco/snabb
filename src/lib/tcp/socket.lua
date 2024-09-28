-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Includes code ported from smoltcp
-- (https://github.com/m-labs/smoltcp), whose copyright is the
-- following:
---
-- Copyright (C) 2016 whitequark@whitequark.org
-- 
-- Permission to use, copy, modify, and/or distribute this software for
-- any purpose with or without fee is hereby granted.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
-- WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
-- ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
-- WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
-- AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT
-- OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-- Heads up! Before working on this file you should read, at least, RFC
-- 793 and the parts of RFC 1122 that discuss TCP.  Consult RFC 7414
-- when implementing a new feature.

module(...,package.seeall)

-- NOTE TO READER ~~~
--
-- This port is currently unfinished.  It's just here as a savepoint.
--
-- I started this port of smoltcp thinking that I would want a big flat
-- ctable.  However in the end I don't think that's the right thing,
-- because the sockets can move around in memory, and if you implement a
-- TCP service, you'd like to be able for the fiber or whatever that
-- serves a connection to be able to work with the socket directly --
-- but if it can move around in memory, you're inviting problems.
--
-- So, the next step here is to refactor this to make the "socket" the
-- primary object and not the socket table.  At the same time, the
-- "proto" library changed since this code was first written; need to
-- port there.  But in general I would say (to myself, probably!), look
-- at apps/tcp/server.lua and figure out what needs to be done here to
-- make that work.

local lib = require("core.lib")
local ffi = require("ffi")
local bit = require("bit")
local tcp = require("lib.tcp")
local ctable = require("lib.ctable")
local siphash = require("lib.hash.siphash")
local buffer = require("lib.tcp.buffer")
local proto = require("lib.tcp.proto")
local reorder = require("lib.tcp.reorder")
local timer = require("lib.tcp.timer")

local ntohs, ntohl = lib.ntohs, lib.ntohl
local htons, htonl = ntohs, ntohl
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift = bit.lshift, bit.rshift

local ipv4_addr_t = ffi.typeof('uint8_t[4]')
local ipv6_addr_t = ffi.typeof('uint8_t[16]')

local function enum(names)
   local ret = {}
   for i,name in ipairs(names) do ret[name] = i end
   return ret
end

-- The state of a TCP socket, according to [RFC 793].
--
-- [RFC 793]: https://tools.ietf.org/html/rfc793
local states = enum { 'CLOSED', 'LISTEN', 'SYN_SENT', 'SYN_RECEIVED',
                      'ESTABLISHED', 'FIN_WAIT_1', 'FIN_WAIT_2', 'CLOSE_WAIT',
                      'CLOSING', 'LAST_ACK', 'TIME_WAIT' }

-- A Transmission Control Protocol socket.

local function make_tcp_socket_id_t(addr_t)
   -- A socket is identified by the four-tuple of local and remote
   -- addresses and ports.  A socket in the LISTEN state uses a zero
   -- remote address and port.
   return ffi.typeof([[
struct {
   $ local_ip;
   $ remote_ip;
   uint16_t local_port;
   uint16_t remote_port;
} __attribute__((packed));
]], addr_t, addr_t)
end

local tcp_socket_state_t = ffi.typeof([[
struct {
    uint8_t state; /* one of the tcp_state constants */
    $ timer;
    $* rx_buffer;
    $* tx_buffer;

    /* Interval after which, if no inbound packets are received, the
       connection is aborted, or -1 if not set.  */
    uint64_t timeout;

    /* Interval at which keep-alive packets will be sent, or -1 if not
       set.  */
    uint64_t keep_alive;

    /* The sequence number corresponding to the beginning of the
       transmit buffer.  I.e. an ACK(local_seq_no+n) packet removes n
       bytes from the transmit buffer. */
    uint32_t local_seq_no;

    /* The sequence number corresponding to the beginning of the receive
       buffer.  I.e. userspace reading n bytes adds n to
       remote_seq_no. */
    uint32_t remote_seq_no;

    /* The last sequence number sent.  I.e. in an idle socket,
       local_seq_no+tx_buffer.len(). */
    uint32_t remote_last_seq;

    /* The last acknowledgement number sent.  I.e. in an idle socket,
       remote_seq_no+rx_buffer.len(). */
    uint32_t remote_last_ack; // FIXME: Option<>

    /* The last window length sent. */
    uint16_t remote_last_win;

    /* The speculative remote window size.  I.e. the actual remote
       window size minus the count of in-flight octets. */
    uint32_t remote_win_len;

    /* The maximum number of data octets that the remote side may
       receive. */
    uint32_t remote_mss;

    /* The timestamp of the last packet received, or -1 if unknown.  */
    uint64_t remote_last_ts;
} __attribute__((packed));
]], timer.timer_t, socket_buffer_t, socket_buffer_t)

local default_mss = 536

local function clear_tcp_socket_state(sock)
   -- note: buffers larger than 65535 require window scaling, which is
   -- not implemented
   -- FIXME: put rx and tx buffers, if any, back on freelist
   ffi.fill(sock, ffi.sizeof(tcp_socket_state_t))
   sock.state = states.CLOSED
   sock.timer:set_none()
   sock.timeout = -1
   sock.keep_alive = -1
   -- FIXME: Initialize sock.remote_last_ack to "none"
   sock.remote_mss = default_mss
   sock.remote_last_ts = -1
end

local function state_predicate(states)
   return function(sock) return lib.bitset(states, sock.state) end
end

-- This function returns true if the socket will process incoming or
-- dispatch outgoing packets. Note that this does not mean that it is
-- possible to send or receive data through the socket; for that, use
-- [can_send](#method.can_send) or [can_recv](#method.can_recv).
local tcp_socket_is_open = state_predicate(
   bnot(lib.bits {states.CLOSED, states.TIME_WAIT}))
local tcp_socket_is_listening = state_predicate(
   lib.bits {states.LISTEN})
-- This function returns true if the socket is actively exchanging packets with
-- a remote endpoint. Note that this does not mean that it is possible to send or receive
-- data through the socket; for that, use [can_send](#method.can_send) or
-- [can_recv](#method.can_recv).
local tcp_socket_is_active = state_predicate(
   bnot(lib.bits {states.CLOSED, states.TIME_WAIT, states.LISTEN}))
-- Return whether the transmit half of the full-duplex connection is open.
--
-- This function returns true if it's possible to send data and have it
-- arrive to the remote endpoint. However, it does not make any
-- guarantees about the state of the transmit buffer, and even if it
-- returns true, [send](#method.send) may not be able to enqueue any
-- octets.
--
-- In CLOSE_WAIT, the remote endpoint has closed our receive half of the
-- connection but we still can transmit indefinitely.
local tcp_socket_may_send = state_predicate(
   lib.bits {states.ESTABLISHED, states.CLOSE_WAIT})

local SocketTable = {}

function new_socket_table(addr_t)
   local ret = {}
   ret.id_t = make_tcp_socket_id_t(addr_t)
   ret.empty_ip = addr_t()
   ret.counter = 0xffffffff -- For random_u32.
   ret.sockets = ctable.new {
      key_type = ret.id_t,
      value_type = tcp_socket_state_t,
      max_occupancy_rate = 0.4
   }
   ret.scratch_entry = ret.table.entry_type()
   return setmetatable(ret, { __index = SocketTable })
end

function new_ipv4_socket_table() return new_socket_table(ipv4_addr_t) end
function new_ipv6_socket_table() return new_socket_table(ipv6_addr_t) end

-- A socket with a timeout duration set will abort the connection if
-- either of the following occurs:
--
--   * After a [connect](#method.connect) call, the remote endpoint does
--     not respond within the specified duration;
--   * After establishing a connection, there is data in the transmit
--     buffer and the remote endpoint exceeds the specified duration
--     between any two packets it sends;
--   * After enabling [keep-alive](#method.set_keep_alive), the remote
--     endpoint exceeds the specified duration between any two packets
--     it sends.
local function tcp_socket_timeout(sock)
   if sock.timeout ~= -1 then return sock.timeout end
end
local function set_tcp_socket_timeout(sock, duration)
   sock.timeout = duration
end
local function clear_tcp_socket_timeout(sock)
   set_tcp_socket_timeout(sock, -1)
end

-- An idle socket with a keep-alive interval set will transmit a
-- "challenge ACK" packet every time it receives no communication during
-- that interval. As a result, three things may happen:
--
--   * The remote endpoint is fine and answers with an ACK packet.
--   * The remote endpoint has rebooted and answers with an RST packet.
--   * The remote endpoint has crashed and does not answer.
--
-- The keep-alive functionality together with the timeout functionality
-- allows to react to these error conditions.
local function tcp_socket_keep_alive(sock)
   if sock.keep_alive ~= -1 then return sock.keep_alive end
end
local function set_tcp_socket_keep_alive(sock, interval)
   sock.keep_alive = interval
   -- If the connection is idle and we've just set the option, it would
   -- not take effect until the next packet, unless we wind up the timer
   -- explicitly.
   sock.timer:set_keep_alive()
end
local function clear_tcp_socket_keep_alive(sock)
   sock.keep_alive = -1
   -- and the timer??
end

-- Return socket table entry (with key and value properties) or nil.
function SocketTable:lookup_socket(local_ip, remote_ip, local_port, remote_port)
   local entry = self.scratch_entry
   entry.key.local_ip, entry.key.remote_ip = local_ip, remote_ip
   entry.key.local_port, entry.key.remote_port = local_port, remote_port
   return self.sockets:lookup_ptr(entry.key)
end

function SocketTable:random_u32()
   local counter = self.random_counter
   if counter > 2e9 then
      -- Rekey every so often, but start with at least a few bits in the
      -- counter.
      counter = 0x12345678
      self.hash_u64 = siphash.make_u64_hash()
   end
   self.random_counter = counter + 1
   return self.hash_u64 
end

function SocketTable:choose_initial_sequence_number(sockent)
   -- FIXME: Consider following RFC 6528 instead.
   return bxor(sockent.hash, self:random_u32())
end

-- Return socket table entry, adding it to the table if necessary.  May
-- signal an error depending on whether the socket exists already or
-- not, according to the updates_allowed parameter; see ctable.add for
-- details.  If the socket was newly added, it will be in the
function SocketTable:add_socket(local_ip, remote_ip, local_port, remote_port,
                                updates_allowed)
   local entry = self.scratch_entry
   entry.key.local_ip, entry.key.remote_ip = local_ip, remote_ip
   entry.key.local_port, entry.key.remote_port = local_port, remote_port
   clear_tcp_socket_state(entry.value)
   return self.sockets:add(entry.key, entry.value, updates_allowed)
end

-- Add a new socket to the table.  If it exists already, return the
-- existing entry; otherwise return a freshly added entry in the closed
-- state.
function SocketTable:ensure_socket(local_ip, remote_ip, local_port, remote_port)
   return self:add_socket(local_ip, remote_ip, local_port, remote_port,
                          'preserve')
end

function SocketTable:listen(ip, port)
   assert(port ~= 0, "attempt to listen on port 0")
   local sockent = self:add_socket(ip, self.empty_ip, port, 0)
   self:set_state(sockent, states.LISTEN)
   return sockent
end   

-- The local port must be provided explicitly.  Assuming `fn
-- get_ephemeral_port() -> u16` allocates a port between 49152 and
-- 65535, a connection may be established as follows:
--
-- ```rust,ignore
-- socket.connect((IpAddress::v4(10, 0, 0, 1), 80), get_ephemeral_port())
-- ```
--
-- The local address may optionally be provided.
--
-- This function signals an error if the socket was open; see
-- [is_open](#method.is_open).  It also signals an error if the local or
-- remote port is zero, or if the remote address is unspecified.
function SocketTable:connect(local_ip, local_port, remote_ip, remote_port)
   assert(local_port ~= 0, "attempt to connect from port 0")
   assert(remote_port ~= 0, "attempt to connect to port 0")
   local sockent = self:ensure_socket(ip, self.empty_ip, port, 0)
   assert(not tcp_socket_is_open(sockent.value), "socket already open")
   clear_tcp_socket_state(sockent.value)
   sockent.value.local_seq_no = self:choose_initial_sequence_number(sockent)
   sockent.value.remote_last_seq = self.value.local_seq_no
   -- The dispatcher will actually send the packet.
   self:set_state(sockent, states.SYN_SENT)
   return sockent
end

-- Close the transmit half of the full-duplex connection.
--
-- Note that there is no corresponding function for the receive half of
-- the full-duplex connection; only the remote end can close it. If you
-- no longer wish to receive any data and would like to reuse the socket
-- right away, use [abort](#method.abort).
function SocketTable:close(sockent)
   return self.handle_close[sockent.value.state](self, sockent)
end

function SocketTable:add_handler(op, state, handler)
   local idx = assert(states[state])
   assert(self['handle_'..op])[idx] = assert(self[op..'_'..handler])
end
function SocketTable:check_handlers(op)
   for i,s in ipairs(tcp_state_names) do assert(self['handle_'..op][i]) end
end
function SocketTable:add_handlers(op, ...)
   for _,pair in ipairs({...}) do self:add_handler(op, unpack(pair)) end
   self:check_handlers(op)
end

function SocketTable:close_nop(sockent) end
function SocketTable:close_closed(sockent)
   self:set_state(sockent, states.CLOSED)
end
function SocketTable:close_fin_wait_1(sockent)
   self:set_state(sockent, states.FIN_WAIT_1)
end
function SocketTable:close_last_ack(sockent)
   self:set_state(sockent, states.LAST_ACK)
end

SocketTable:add_handlers(
   'close',
   -- In the LISTEN state there is no established connection; in
   -- SYN_SENT state the remote endpoint is not yet synchronized and,
   -- upon receiving an RST, will abort the connection.
   {'LISTEN', 'closed'}, {'SYN_SENT', 'closed' },
   -- In the SYN_RECEIVED, ESTABLISHED and CLOSE-WAIT states the
   -- transmit half of the connection is open, and needs to be
   -- explicitly closed with a FIN.
   {'SYN_RECEIVED', 'fin_wait_1'}, {'ESTABLISHED', 'fin_wait_1'},
   {'CLOSE_WAIT', 'last_ack'},
   -- In the FIN_WAIT_1, FIN_WAIT_2, CLOSING, LAST_ACK, TIME_WAIT and
   -- CLOSED states, the transmit half of the connection is already
   -- closed, and no further action is needed.
   {'FIN_WAIT_1', 'nop'}, {'FIN_WAIT_2', 'nop'}, {'CLOSING', 'nop'},
   {'TIME_WAIT', 'nop'}, {'LAST_ACK', 'nop'}, {'CLOSED', 'nop'})

-- Aborts the connection, if any.
--
-- This function instantly closes the socket. One reset packet will be
-- sent to the remote endpoint.
--
-- In terms of the TCP state machine, the socket may be in any state and
-- is moved to the `CLOSED` state.
function SocketTable:abort(sockent)
   self:set_state(sockent, states.CLOSED)
end

-- Return whether the receive half of the full-duplex connection is
-- open.
--
-- This function returns true if it's possible to receive data from the
-- remote endpoint.  It will return true while there is data in the
-- receive buffer, and if there isn't, as long as the remote endpoint
-- has not closed the connection.
--
-- In terms of the TCP state machine, the socket must be in the
-- `ESTABLISHED`, `FIN-WAIT-1`, or `FIN-WAIT-2` state, or have data in
-- the receive buffer instead.
local may_recv_states = state_partition(
   "ESTABLISHED", "FIN_WAIT_1", "FIN_WAIT_2")
local function tcp_socket_may_recv(sock)
   return may_recv_states[sock.state] or sock.rx_buffer:is_empty()
end

-- Check whether the transmit half of the full-duplex connection is open
-- (see [may_send](#method.may_send), and the transmit buffer is not full.
local function tcp_socket_can_send(sock)
   return tcp_socket_may_send(socket) and not sock.tx_buffer:is_full()
end

-- Check whether the transmit half of the full-duplex connection is open
-- (see [may_recv](#method.may_recv), and the transmit buffer is not full.
local function tcp_socket_can_recv(sock)
   return tcp_socket_may_recv(socket) and not sock.rx_buffer:is_empty()
end

-- Enqueue a sequence of octets to be sent, and fill it from a slice.
--
-- This function returns the amount of bytes actually enqueued, which is limited
-- by the amount of free space in the transmit buffer; down to zero.
function SocketTable:enqueue(sockent, buf, count)
   local sock = sockent.value
   assert(tcp_socket_may_send(sock))
   -- The connection might have been idle for a long time, and so
   -- remote_last_ts would be far in the past. Unless we clear it here,
   -- we'll abort the connection down over in dispatch() by erroneously
   -- detecting it as timed out.
   if sock.tx_buffer:is_empty() then sock.remote_last_ts = -1 end
   count = math.min(sock.tx_buffer:write_avail(), count)
   -- FIXME: trace
   sock.tx_buffer:write(buf, count)
   return count
end

-- Dequeue a sequence of received octets, and fill a slice from it.
--
-- This function returns the amount of bytes actually dequeued, which is limited
-- by the amount of free space in the transmit buffer; down to zero.
function SocketTable:dequeue(sockent, buf, count)
   local sock = sockent.value
   -- We may have received some data inside the initial SYN, but until
   -- the connection is fully open we must not dequeue any data, as it
   -- may be overwritten by e.g.  another (stale) SYN. (We do not
   -- support TCP Fast Open.)
   assert(tcp_socket_may_recv(sock))
   count = math.min(sock.rx_buffer:read_avail(), count)
   -- FIXME: trace
   sock.rx_buffer:read(buf, count)
   sock.remote_seq_no = sock.remote_seq_no + count;
   return count
end

-- Peek at a sequence of received octets without removing them from the
-- receive buffer, and return two values: the pointer and a byte count.
--
-- This function otherwise behaves identically to [recv](#method.recv).
function SocketTable:peek(sockent)
   local sock = sockent.value
   -- See dequeue() above.
   assert(tcp_socket_may_recv(sock))
   return sock.rx_buffer:peek()
end

-- Return the amount of octets queued in the transmit buffer.
--
-- Note that the Berkeley sockets interface does not have an equivalent
-- of this API.
function SocketTable:send_queue(sockent)
   return sockent.value.tx_buffer:read_avail()
end

-- Return the amount of octets queued in the receive buffer.
--
-- Note that the Berkeley sockets interface does not have an equivalent
-- of this API.
function SocketTable:recv_queue(sockent)
   return sockent.value.rx_buffer:read_avail()
end

function SocketTable:set_state(sockent, state)
   local sock = sockent.value
   if self.state ~= state then
      -- FIXME: trace.
   end
   self.state = state
end

function TCP:process_ipv4(p, timestamp)
   -- Necessary checks:
   -- ipv4 source address is unicast
   -- ipv4 checksum matches
   -- protocol is tcp
end

function TCP:process_ipv6(p, timestamp)
   -- Necessary checks:
   -- ipv6 source address is unicast
   -- protocol is tcp
end

function TCP:process_tcp(p, timestamp)
   -- Necessary checks:
   -- tcp checksum matches

   -- look up a socket.  if one found, process the packet, possibly
   -- creating a new socket, and return.
   
   -- if no socket found, then:
   local control = compute_tcp_control(tcp_flags(tcp))
   if control == tcp_control_rst then
      -- Don't reply to a TCP RST packet with another TCP RST packet;
      -- just pass.
   else
      local seq = htonl(tcp.ack)
      -- See https://www.snellman.net/blog/archive/2016-02-01-tcp-rst/
      -- for explanation of why we sometimes send an RST and sometimes
      -- an RST|ACK
      local ack = 0
      if control == tcp_control_syn then
         ack = htonl(tcp.seq) + segment_len(tcp, l4_length)
      end
      local p = self:add_headers(packet.allocate(),
                                 dst_ip, src_ip, dst_port, src_port,
                                 seq, ack, window, flags)
      -- FIXME: send P.
   end
end

function SocketTable:prepare_ack_reply(ip, tcp)
   -- From RFC 793:
   -- [...] an empty acknowledgment segment containing the current
   -- send-sequence number and an acknowledgment indicating the next
   -- sequence number expected to be received.
   local seq = sock.remote_last_seq
   local ack = sock.remote_last_ack
   local window_len = sock.window() -- apply window scaling
   local p = self:add_headers(packet.allocate(),
                              dst_ip, src_ip, dst_port, src_port,
                              seq, ack, window, flags)
   -- fixme flags
end

local default_ttl = 64
function SocketTable:add_headers(p, src_ip, dst_ip, src_port, dst_port,
                                 seq, ack, window, flags)
   -- FIXME set self.push_headers
   return self.push_headers(p, src_ip, dst_ip, default_ttl, src_port, dst_port,
                            seq, ack, window, 0, flags)
end

-- FIXME: this function is just *not* what we need.
function SocketTable:accepts(sockent, p)
   if sockent.value.state == states.CLOSED then
      return false
   end

   -- If we're still listening for SYNs and the packet has an ACK, it
   -- cannot be destined to this socket, but another one may well listen
   -- on the same local endpoint.
   if sockent.state == states.LISTEN and repr.ack ~= 0 then
      return false
   end

   -- Reject packets with a wrong destination.
   -- Reject packets from a source to which we aren't connected.

   return true
end

local function make_state_array(typ, val)
   local len = #tcp_state_names + 1
   local ret = ffi.typeof("$[?]", ffi.typeof(typ))(len)
   for i=0,len do ret[i] = val end
   return ret
end

local function adjoin_states(tab, val, ...)
   for _, state in ipairs({...}) do tab[assert(states[state])] = val end
end

local sent_syn_offsets = make_state_array("uint8_t", 0)
local sent_fin_offsets = make_state_array("uint8_t", 0)

-- In SYN-SENT or SYN-RECEIVED, we've just sent a SYN.
adjoin_states(sent_syn_offsets, 1, "SYN_SENT", "SYN_RECEIVED")
-- In FIN-WAIT-1, LAST-ACK, or CLOSING, we've just sent a FIN.
adjoin_states(sent_fin_offsets, 1, "FIN_WAIT_1", "LAST_ACK", "CLOSING")
-- In all other states we've already got acknowledgements for all of the
-- control flags we sent.

function SocketTable:process(sockent, p)
   assert(self:accepts(sockent, p))

   local state = sockent.value.state
   local control = compute_tcp_control(tcp_flags(tcp))

   -- Consider how much the sequence number space differs from the
   -- transmit buffer space.
   local sent_syn_offset = sent_syn_offsets[state]
   local sent_fin_offset = sent_fin_offsets[state]
   local control_len = sent_syn_offset + sent_fin_offset

   -- Reject unacceptable acknowledgements.
   if has_ack(tcp) then
      if state == states.SYN_SENT then
         if ack_number == sockent.value.local_seq_no + 1 then
            -- RST received SYN_SENT must acknowledge the initial SYN.
         else
            net_debug("{}:{}:{}: unacceptable RST|ACK in response to initial SYN",
                      self.meta.handle, self.local_endpoint, self.remote_endpoint)
            return drop(p)
         end
      elseif state == states.LISTEN then
         -- The initial SYN cannot contain an acknowledgement.
         error("unreachable") -- see accepts(); a FIXME to refactor
      else
         -- Every acknowledgement must be for transmitted but unacknowledged data.
         local unacknowledged = sockent.value.tx_buffer:read_avail() + control_len;

         if ack_number < self.local_seq_no then
            net_debug("{}:{}:{}: duplicate ACK ({} not in {}...{})",
                      self.meta.handle, self.local_endpoint, self.remote_endpoint,
                      ack_number, self.local_seq_no, self.local_seq_no + unacknowledged)
            -- FIXME: implement fast retransmit
            return drop(p)
         elseif ack_number > self.local_seq_no + unacknowledged then
            net_debug("{}:{}:{}: unacceptable ACK ({} not in {}...{})",
                      self.meta.handle, self.local_endpoint, self.remote_endpoint,
                      ack_number, self.local_seq_no, self.local_seq_no + unacknowledged)
            return Ok(Some(self.ack_reply(ip_repr, repr)))
         end
      end
   else
      -- Packet has no ACK; there are only a limited number of states in
      -- which this is valid.
      if control == tcp_control_rst then
         if state == states.SYN_SENT then
            -- RST received in SYN_SENT must acknowledge the initial
            -- SYN.
            net_debug("{}:{}:{}: unacceptable RST (expecting RST|ACK) in response to initial SYN",
                      self.meta.handle, self.local_endpoint, self.remote_endpoint)
            return drop(p)
         else
            -- Otherwise RST just has to have a valid sequence number.
         end
      else
         -- Every packet after the initial SYN must include ACK.
         net_debug("{}:{}:{}: expecting an ACK",
                   self.meta.handle, self.local_endpoint, self.remote_endpoint)
         return drop(p)
      end
   end

   local window_start = self.remote_seq_no + self.rx_buffer:read_avail();
   local window_end = self.remote_seq_no + self.rx_buffer.size;
   local segment_start = seq_number;
   local segment_end = seq_number + segment_len(tcp, l4_length)

   local payload_offset
   if state == states.LISTEN or state == states.SYN_SENT then
      -- In LISTEN and SYN-SENT states, we have not yet synchronized
      -- with the remote end.
      payload_offset = 0
   else
      -- In all other states, segments must occupy a valid portion of
      -- the receive window.
      local segment_in_window;

      if window_start == window_end and segment_start ~= segment_end then
         net_debug("{}:{}:{}: non-zero-length segment with zero receive window, will only send an ACK",
                   self.meta.handle, self.local_endpoint, self.remote_endpoint)
         segment_in_window = false
      elseif segment_start == segment_end and segment_end == window_start - 1 then
         net_debug("{}:{}:{}: received a keep-alive or window probe packet, will send an ACK",
                   self.meta.handle, self.local_endpoint, self.remote_endpoint)
         segment_in_window = false
      elseif not ((window_start <= segment_start and segment_start <= window_end) and
         (window_start <= segment_end and segment_end <= window_end)) then
         net_debug("{}:{}:{}: segment not in receive window ({}..{} not intersecting {}..{}), will send challenge ACK",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint,
                  segment_start, segment_end, window_start, window_end)
         segment_in_window = false
      else
         segment_in_window = true
      end

      if segment_in_window then
         -- We've checked that segment_start >= window_start above.
         payload_offset = to_uint32(segment_start - window_start)
      else
         -- If we're in the TIME-WAIT state, restart the TIME-WAIT timeout, since
         -- the remote end may not have realized we've closed the connection.
         if state == states.TIME_WAIT then
            self.timer:set_for_close(timestamp)
         end

         return self.ack_reply(ip, tcp)
      end
   end

   -- Compute the amount of acknowledged octets, removing the SYN and FIN bits
   -- from the sequence space.
   local ack_len = 0
   local ack_of_fin = false
   if control ~= tcp_control_rst then
      if has_ack(tcp) then
         local ack_number = get_ack_number(tcp)
         ack_len = ack_number - self.local_seq_no
         -- There could have been no data sent before the SYN, so we always remove it
         -- from the sequence space.
         if sent_syn then ack_len = ack_len - 1 end
         -- We could've sent data before the FIN, so only remove FIN from the sequence
         -- space if all of that data is acknowledged.
         if sent_fin and sockent.value.tx_buffer:read_avail() + 1 == ack_len then
            ack_len = ack_len - 1
            net_trace("{}:{}:{}: received ACK of FIN",
                      self.meta.handle, self.local_endpoint, self.remote_endpoint)
            ack_of_fin = true
         end
      end
   end

   if control == tcp_control_psh then
      -- Disregard control flags we don't care about or shouldn't act on
      -- yet.
      control = tcp_control_none
   elseif control == tcp_control_fin and window_start ~= segment_start then
      -- If a FIN is received at the end of the current segment but the
      -- start of the segment is not at the start of the receive window,
      -- disregard this FIN.
      control = tcp_control_none
   end

   local update_state=[[

   -- Validate and update the state.
   match (self.state, control) {
      -- RSTs are not accepted in the LISTEN state.
      (State::Listen, TcpControl::Rst) =>
         return Err(Error::Dropped),

      -- RSTs in SYN-RECEIVED flip the socket back to the LISTEN state.
      (State::SynReceived, TcpControl::Rst) => {
         net_trace!("{}:{}:{}: received RST",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
         self.local_endpoint.addr = self.listen_address;
         self.remote_endpoint    = IpEndpoint::default();
         self.set_state(State::Listen);
         return Ok(None)
      }

      -- RSTs in any other state close the socket.
      (_, TcpControl::Rst) => {
         net_trace!("{}:{}:{}: received RST",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
         self.set_state(State::Closed);
         self.local_endpoint  = IpEndpoint::default();
         self.remote_endpoint = IpEndpoint::default();
         return Ok(None)
      }

      -- SYN packets in the LISTEN state change it to SYN-RECEIVED.
      (State::Listen, TcpControl::Syn) => {
         net_trace!("{}:{}: received SYN",
                  self.meta.handle, self.local_endpoint);
         self.local_endpoint  = IpEndpoint::new(ip_repr.dst_addr(), repr.dst_port);
         self.remote_endpoint = IpEndpoint::new(ip_repr.src_addr(), repr.src_port);
         -- FIXME: use something more secure here
         self.local_seq_no   = TcpSeqNumber(-repr.seq_number.0);
         self.remote_seq_no   = repr.seq_number + 1;
         self.remote_last_seq = self.local_seq_no;
         if let Some(max_seg_size) = repr.max_seg_size {
            self.remote_mss = max_seg_size as usize
         }
         self.set_state(State::SynReceived);
         self.timer:set_for_idle(timestamp, self.keep_alive);
      }

      -- ACK packets in the SYN-RECEIVED state change it to ESTABLISHED.
      (State::SynReceived, TcpControl::None) => {
         self.set_state(State::Established);
         self.timer:set_for_idle(timestamp, self.keep_alive);
      }

      -- FIN packets in the SYN-RECEIVED state change it to CLOSE-WAIT.
      -- It's not obvious from RFC 793 that this is permitted, but
      -- 7th and 8th steps in the "SEGMENT ARRIVES" event describe this behavior.
      (State::SynReceived, TcpControl::Fin) => {
         self.remote_seq_no  += 1;
         self.set_state(State::CloseWait);
         self.timer:set_for_idle(timestamp, self.keep_alive);
      }

      -- SYN|ACK packets in the SYN-SENT state change it to ESTABLISHED.
      (State::SynSent, TcpControl::Syn) => {
         net_trace!("{}:{}:{}: received SYN|ACK",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
         self.local_endpoint  = IpEndpoint::new(ip_repr.dst_addr(), repr.dst_port);
         self.remote_seq_no   = repr.seq_number + 1;
         self.remote_last_seq = self.local_seq_no + 1;
         self.remote_last_ack = Some(repr.seq_number);
         if let Some(max_seg_size) = repr.max_seg_size {
            self.remote_mss = max_seg_size as usize;
         }
         self.set_state(State::Established);
         self.timer.set_for_idle(timestamp, self.keep_alive);
      }

      -- ACK packets in ESTABLISHED state reset the retransmit timer,
      -- except for duplicate ACK packets which preserve it.
      (State::Established, TcpControl::None) => {
         if !self.timer.is_retransmit() || ack_len != 0 {
            self.timer.set_for_idle(timestamp, self.keep_alive);
         }
      },

      -- FIN packets in ESTABLISHED state indicate the remote side has closed.
      (State::Established, TcpControl::Fin) => {
         self.remote_seq_no  += 1;
         self.set_state(State::CloseWait);
         self.timer.set_for_idle(timestamp, self.keep_alive);
      }

      -- ACK packets in FIN-WAIT-1 state change it to FIN-WAIT-2, if we've already
      -- sent everything in the transmit buffer. If not, they reset the retransmit timer.
      (State::FinWait1, TcpControl::None) => {
         if ack_of_fin {
            self.set_state(State::FinWait2);
         }
         self.timer.set_for_idle(timestamp, self.keep_alive);
      }

      -- FIN packets in FIN-WAIT-1 state change it to CLOSING, or to TIME-WAIT
      -- if they also acknowledge our FIN.
      (State::FinWait1, TcpControl::Fin) => {
         self.remote_seq_no  += 1;
         if ack_of_fin {
            self.set_state(State::TimeWait);
            self.timer.set_for_close(timestamp);
         } else {
            self.set_state(State::Closing);
            self.timer.set_for_idle(timestamp, self.keep_alive);
         }
      }

      -- FIN packets in FIN-WAIT-2 state change it to TIME-WAIT.
      (State::FinWait2, TcpControl::Fin) => {
         self.remote_seq_no  += 1;
         self.set_state(State::TimeWait);
         self.timer.set_for_close(timestamp);
      }

      -- ACK packets in CLOSING state change it to TIME-WAIT.
      (State::Closing, TcpControl::None) => {
         if ack_of_fin {
            self.set_state(State::TimeWait);
            self.timer.set_for_close(timestamp);
         } else {
            self.timer.set_for_idle(timestamp, self.keep_alive);
         }
      }

      -- ACK packets in CLOSE-WAIT state reset the retransmit timer.
      (State::CloseWait, TcpControl::None) => {
         self.timer.set_for_idle(timestamp, self.keep_alive);
      }

      -- ACK packets in LAST-ACK state change it to CLOSED.
      (State::LastAck, TcpControl::None) => {
         -- Clear the remote endpoint, or we'll send an RST there.
         self.set_state(State::Closed);
         self.local_endpoint  = IpEndpoint::default();
         self.remote_endpoint = IpEndpoint::default();
      }

      _ => {
         net_debug!("{}:{}:{}: unexpected packet {}",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint, repr);
         return Err(Error::Dropped)
      }
   }
   ]]

   -- Update remote state.
   self.remote_last_ts = timestamp
   self.remote_win_len = ntohs(tcp.window_len)

   if ack_len > 0 then
      -- Dequeue acknowledged octets.
      debug_assert(self.tx_buffer.len() >= ack_len)
      net_trace("{}:{}:{}: tx buffer: dequeueing {} octets (now {})",
                self.meta.handle, self.local_endpoint, self.remote_endpoint,
                ack_len, self.tx_buffer.len() - ack_len)
      self.tx_buffer.drop(ack_len)
   end

   if has_ack(tcp) then
      local ack_number = tcp_ack_number(tcp)
      -- We've processed everything in the incoming segment, so advance the local
      -- sequence number past it.
      self.local_seq_no = ack_number
      -- During retransmission, if an earlier segment got lost but later
      -- was successfully received, self.local_seq_no can move past
      -- self.remote_last_seq.
      --
      -- Do not attempt to retransmit the latter segments; not only this
      -- is pointless in theory but also impossible in practice, since
      -- they have been already deallocated from the buffer.
      if self.remote_last_seq < self.local_seq_no then
         self.remote_last_seq = self.local_seq_no
      end
   end

   local payload_len = tcp_payload_length(tcp, l4_length)
   if payload_len == 0 then return end

   local reordering_before = self.reorder:has_holes()
   self.reorder:write(sockent.value.rx_buffer, window_start, segment_start,
                      tcp_payload(tcp), payload_length)
   local reordering_after = self.reorder:has_holes()

   -- Now there may be some data!

   -- Per RFC 5681, we should send an immediate ACK when either:
   --  1) an out-of-order segment is received, or
   --  2) a segment arrives that fills in all or part of a gap in sequence space.
   if reordering_before or reordering_after then
      -- Note that we change the transmitter state here.  This is fine
      -- because smoltcp assumes that it can always transmit zero or one
      -- packets for every packet it receives.
      net_trace("{}:{}:{}: ACKing incoming segment",
                self.meta.handle, self.local_endpoint, self.remote_endpoint);
      self.remote_last_ack = Some(self.remote_seq_no + self.rx_buffer.len());
      Ok(Some(self.ack_reply(ip_repr, repr)))
   else
      Ok(None)
   end
end
str=[[

   fn timed_out(&self, timestamp: u64) -> bool {
      match (self.remote_last_ts, self.timeout) {
         (Some(remote_last_ts), Some(timeout)) =>
            timestamp >= remote_last_ts + timeout,
         (_, _) =>
            false
      }
   }

   fn seq_to_transmit(&self) -> bool {
      let control;
      match self.state {
         State::SynSent  | State::SynReceived =>
            control = TcpControl::Syn,
         State::FinWait1 | State::LastAck =>
            control = TcpControl::Fin,
         _ => control = TcpControl::None
      }

      if self.remote_win_len > 0 {
         self.remote_last_seq < self.local_seq_no + self.tx_buffer.len() + control.len()
      } else {
         false
      }
   }

   fn ack_to_transmit(&self) -> bool {
      if let Some(remote_last_ack) = self.remote_last_ack {
         remote_last_ack < self.remote_seq_no + self.rx_buffer.len()
      } else {
         false
      }
   }

   fn window_to_update(&self) -> bool {
      self.rx_buffer.window() as u16 > self.remote_last_win
   }

   pub(crate) fn dispatch<F>(&mut self, timestamp: u64, caps: &DeviceCapabilities,
                       emit: F) -> Result<()>
         where F: FnOnce((IpRepr, TcpRepr)) -> Result<()> {
      if !self.remote_endpoint.is_specified() { return Err(Error::Exhausted) }

      if self.remote_last_ts.is_none() {
         // We get here in exactly two cases:
         //  1) This socket just transitioned into SYN-SENT.
         //  2) This socket had an empty transmit buffer and some data was added there.
         // Both are similar in that the socket has been quiet for an indefinite
         // period of time, it isn't anymore, and the local endpoint is talking.
         // So, we start counting the timeout not from the last received packet
         // but from the first transmitted one.
         self.remote_last_ts = Some(timestamp);
      }

      // Check if any state needs to be changed because of a timer.
      if self.timed_out(timestamp) {
         // If a timeout expires, we should abort the connection.
         net_debug!("{}:{}:{}: timeout exceeded",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
         self.set_state(State::Closed);
      } else if !self.seq_to_transmit() {
         if let Some(retransmit_delta) = self.timer.should_retransmit(timestamp) {
            // If a retransmit timer expired, we should resend data starting at the last ACK.
            net_debug!("{}:{}:{}: retransmitting at t+{}ms",
                     self.meta.handle, self.local_endpoint, self.remote_endpoint,
                     retransmit_delta);
            self.remote_last_seq = self.local_seq_no;
         }
      }

      // Decide whether we're sending a packet.
      if self.seq_to_transmit() {
         // If we have data to transmit and it fits into partner's window, do it.
         net_trace!("{}:{}:{}: outgoing segment will send data or flags",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
      } else if self.ack_to_transmit() {
         // If we have data to acknowledge, do it.
         net_trace!("{}:{}:{}: outgoing segment will acknowledge",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
      } else if self.window_to_update() {
         // If we have window length increase to advertise, do it.
         net_trace!("{}:{}:{}: outgoing segment will update window",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
      } else if self.state == State::Closed {
         // If we need to abort the connection, do it.
         net_trace!("{}:{}:{}: outgoing segment will abort connection",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
      } else if self.timer.should_retransmit(timestamp).is_some() {
         // If we have packets to retransmit, do it.
         net_trace!("{}:{}:{}: retransmit timer expired",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
      } else if self.timer.should_keep_alive(timestamp) {
         // If we need to transmit a keep-alive packet, do it.
         net_trace!("{}:{}:{}: keep-alive timer expired",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
      } else if self.timer.should_close(timestamp) {
         // If we have spent enough time in the TIME-WAIT state, close the socket.
         net_trace!("{}:{}:{}: TIME-WAIT timer expired",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
         self.reset();
         return Err(Error::Exhausted)
      } else {
         return Err(Error::Exhausted)
      }

      // Construct the lowered IP representation.
      // We might need this to calculate the MSS, so do it early.
      let mut ip_repr = IpRepr::Unspecified {
         src_addr:    self.local_endpoint.addr,
         dst_addr:    self.remote_endpoint.addr,
         protocol:    IpProtocol::Tcp,
         hop_limit:   self.hop_limit.unwrap_or(64),
         payload_len:  0
      }.lower(&[])?;

      // Construct the basic TCP representation, an empty ACK packet.
      // We'll adjust this to be more specific as needed.
      let mut repr = TcpRepr {
         src_port:    self.local_endpoint.port,
         dst_port:    self.remote_endpoint.port,
         control:     TcpControl::None,
         seq_number:   self.remote_last_seq,
         ack_number:   Some(self.remote_seq_no + self.rx_buffer.len()),
         window_len:   self.rx_buffer.window() as u16,
         max_seg_size: None,
         payload:     &[]
      };

      match self.state {
         // We transmit an RST in the CLOSED state. If we ended up in the CLOSED state
         // with a specified endpoint, it means that the socket was aborted.
         State::Closed => {
            repr.control = TcpControl::Rst;
         }

         // We never transmit anything in the LISTEN state.
         State::Listen => return Err(Error::Exhausted),

         // We transmit a SYN in the SYN-SENT state.
         // We transmit a SYN|ACK in the SYN-RECEIVED state.
         State::SynSent | State::SynReceived => {
            repr.control = TcpControl::Syn;
            if self.state == State::SynSent {
               repr.ack_number = None;
            }
         }

         // We transmit data in all states where we may have data in the buffer,
         // or the transmit half of the connection is still open:
         // the ESTABLISHED, FIN-WAIT-1, CLOSE-WAIT and LAST-ACK states.
         State::Established | State::FinWait1 | State::CloseWait | State::LastAck => {
            // Extract as much data as the remote side can receive in this packet
            // from the transmit buffer.
            let offset = self.remote_last_seq - self.local_seq_no;
            let size = cmp::min(self.remote_win_len, self.remote_mss);
            repr.payload = self.tx_buffer.get_allocated(offset, size);
            // If we've sent everything we had in the buffer, follow it with the PSH or FIN
            // flags, depending on whether the transmit half of the connection is open.
            if offset + repr.payload.len() == self.tx_buffer.len() {
               match self.state {
                  State::FinWait1 | State::LastAck =>
                     repr.control = TcpControl::Fin,
                  State::Established | State::CloseWait if repr.payload.len() > 0 =>
                     repr.control = TcpControl::Psh,
                  _ => ()
               }
            }
         }

         // We do not transmit anything in the FIN-WAIT-2 state.
         State::FinWait2 => return Err(Error::Exhausted),

         // We do not transmit data or control flags in the CLOSING or TIME-WAIT states,
         // but we may retransmit an ACK.
         State::Closing | State::TimeWait => ()
      }

      // There might be more than one reason to send a packet. E.g. the keep-alive timer
      // has expired, and we also have data in transmit buffer. Since any packet that occupies
      // sequence space will elicit an ACK, we only need to send an explicit packet if we
      // couldn't fill the sequence space with anything.
      let is_keep_alive;
      if self.timer.should_keep_alive(timestamp) && repr.is_empty() {
         repr.seq_number = repr.seq_number - 1;
         repr.payload   = b"\x00"; // RFC 1122 says we should do this
         is_keep_alive = true;
      } else {
         is_keep_alive = false;
      }

      // Trace a summary of what will be sent.
      if is_keep_alive {
         net_trace!("{}:{}:{}: sending a keep-alive",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint);
      } else if repr.payload.len() > 0 {
         net_trace!("{}:{}:{}: tx buffer: sending {} octets at offset {}",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint,
                  repr.payload.len(), self.remote_last_seq - self.local_seq_no);
      }
      if repr.control != TcpControl::None || repr.payload.len() == 0 {
         let flags =
            match (repr.control, repr.ack_number) {
               (TcpControl::Syn,  None)   => "SYN",
               (TcpControl::Syn,  Some(_)) => "SYN|ACK",
               (TcpControl::Fin,  Some(_)) => "FIN|ACK",
               (TcpControl::Rst,  Some(_)) => "RST|ACK",
               (TcpControl::Psh,  Some(_)) => "PSH|ACK",
               (TcpControl::None, Some(_)) => "ACK",
               _ => "<unreachable>"
            };
         net_trace!("{}:{}:{}: sending {}",
                  self.meta.handle, self.local_endpoint, self.remote_endpoint,
                  flags);
      }

      if repr.control == TcpControl::Syn {
         // Fill the MSS option. See RFC 6691 for an explanation of this calculation.
         let mut max_segment_size = caps.max_transmission_unit;
         max_segment_size -= ip_repr.buffer_len();
         max_segment_size -= repr.header_len();
         repr.max_seg_size = Some(max_segment_size as u16);
      }

      // Actually send the packet. If this succeeds, it means the packet is in
      // the device buffer, and its transmission is imminent. If not, we might have
      // a number of problems, e.g. we need neighbor discovery.
      //
      // Bailing out if the packet isn't placed in the device buffer allows us
      // to not waste time waiting for the retransmit timer on packets that we know
      // for sure will not be successfully transmitted.
      ip_repr.set_payload_len(repr.buffer_len());
      emit((ip_repr, repr))?;

      // We've sent something, whether useful data or a keep-alive packet, so rewind
      // the keep-alive timer.
      self.timer.rewind_keep_alive(timestamp, self.keep_alive);

      // Leave the rest of the state intact if sending a keep-alive packet, since those
      // carry a fake segment.
      if is_keep_alive { return Ok(()) }

      // We've sent a packet successfully, so we can update the internal state now.
      self.remote_last_seq = repr.seq_number + repr.segment_len();
      self.remote_last_ack = repr.ack_number;
      self.remote_last_win = repr.window_len;

      if !self.seq_to_transmit() && repr.segment_len() > 0 {
         // If we've transmitted all data we could (and there was something at all,
         // data or flag, to transmit, not just an ACK), wind up the retransmit timer.
         self.timer.set_for_retransmit(timestamp);
      }

      if self.state == State::Closed {
         // When aborting a connection, forget about it after sending a single RST packet.
         self.local_endpoint  = IpEndpoint::default();
         self.remote_endpoint = IpEndpoint::default();
      }

      Ok(())
   }

   pub(crate) fn poll_at(&self) -> Option<u64> {
      // The logic here mirrors the beginning of dispatch() closely.
      if !self.remote_endpoint.is_specified() {
         // No one to talk to, nothing to transmit.
         None
      } else if self.remote_last_ts.is_none() {
         // Socket stopped being quiet recently, we need to acquire a timestamp.
         Some(0)
      } else if self.state == State::Closed {
         // Socket was aborted, we have an RST packet to transmit.
         Some(0)
      } else if self.seq_to_transmit() || self.ack_to_transmit() || self.window_to_update() {
         // We have a data or flag packet to transmit.
         Some(0)
      } else {
         let timeout_poll_at;
         match (self.remote_last_ts, self.timeout) {
            // If we're transmitting or retransmitting data, we need to poll at the moment
            // when the timeout would expire.
            (Some(remote_last_ts), Some(timeout)) =>
               timeout_poll_at = Some(remote_last_ts + timeout),
            // Otherwise we have no timeout.
            (_, _) =>
               timeout_poll_at = None
         }

         // We wait for the earliest of our timers to fire.
         [self.timer.poll_at(), timeout_poll_at]
            .iter()
            .filter_map(|x| *x)
            .min()
      }
   }
}

impl<'a> Into<Socket<'a, 'static>> for TcpSocket<'a> {
   fn into(self) -> Socket<'a, 'static> {
      Socket::Tcp(self)
   }
}

impl<'a> fmt::Write for TcpSocket<'a> {
   fn write_str(&mut self, slice: &str) -> fmt::Result {
      let slice = slice.as_bytes();
      if self.send_slice(slice) == Ok(slice.len()) {
         Ok(())
      } else {
         Err(fmt::Error)
      }
   }
}

#[cfg(test)]
mod test {
   use core::i32;
   use wire::{IpAddress, IpRepr, IpCidr};
   use wire::ip::test::{MOCK_IP_ADDR_1, MOCK_IP_ADDR_2, MOCK_IP_ADDR_3, MOCK_UNSPECIFIED};
   use super::*;

   // =========================================================================================//
   // Constants
   // =========================================================================================//

   const LOCAL_PORT:   u16        = 80;
   const REMOTE_PORT:  u16        = 49500;
   const LOCAL_END:   IpEndpoint   = IpEndpoint { addr: MOCK_IP_ADDR_1,  port: LOCAL_PORT  };
   const REMOTE_END:   IpEndpoint   = IpEndpoint { addr: MOCK_IP_ADDR_2, port: REMOTE_PORT };
   const LOCAL_SEQ:   TcpSeqNumber = TcpSeqNumber(10000);
   const REMOTE_SEQ:   TcpSeqNumber = TcpSeqNumber(-10000);

   const SEND_IP_TEMPL: IpRepr = IpRepr::Unspecified {
      src_addr: MOCK_IP_ADDR_1, dst_addr: MOCK_IP_ADDR_2,
      protocol: IpProtocol::Tcp, payload_len: 20,
      hop_limit: 64
   };
   const SEND_TEMPL: TcpRepr<'static> = TcpRepr {
      src_port: REMOTE_PORT, dst_port: LOCAL_PORT,
      control: TcpControl::None,
      seq_number: TcpSeqNumber(0), ack_number: Some(TcpSeqNumber(0)),
      window_len: 256, max_seg_size: None,
      payload: &[]
   };
   const _RECV_IP_TEMPL: IpRepr = IpRepr::Unspecified {
      src_addr: MOCK_IP_ADDR_1, dst_addr: MOCK_IP_ADDR_2,
      protocol: IpProtocol::Tcp, payload_len: 20,
      hop_limit: 64
   };
   const RECV_TEMPL:  TcpRepr<'static> = TcpRepr {
      src_port: LOCAL_PORT, dst_port: REMOTE_PORT,
      control: TcpControl::None,
      seq_number: TcpSeqNumber(0), ack_number: Some(TcpSeqNumber(0)),
      window_len: 64, max_seg_size: None,
      payload: &[]
   };

   #[cfg(feature = "proto-ipv6")]
   const BASE_MSS: u16 = 1460;
   #[cfg(all(feature = "proto-ipv4", not(feature = "proto-ipv6")))]
   const BASE_MSS: u16 = 1480;

   // =========================================================================================//
   // Helper functions
   // =========================================================================================//

   fn send(socket: &mut TcpSocket, timestamp: u64, repr: &TcpRepr) ->
         Result<Option<TcpRepr<'static>>> {
      let ip_repr = IpRepr::Unspecified {
         src_addr:   MOCK_IP_ADDR_2,
         dst_addr:   MOCK_IP_ADDR_1,
         protocol:   IpProtocol::Tcp,
         payload_len: repr.buffer_len(),
         hop_limit:   64
      };
      net_trace!("send: {}", repr);

      assert!(socket.accepts(&ip_repr, repr));
      match socket.process(timestamp, &ip_repr, repr) {
         Ok(Some((_ip_repr, repr))) => {
            net_trace!("recv: {}", repr);
            Ok(Some(repr))
         }
         Ok(None) => Ok(None),
         Err(err) => Err(err)
      }
   }

   fn recv<F>(socket: &mut TcpSocket, timestamp: u64, mut f: F)
         where F: FnMut(Result<TcpRepr>) {
      let mut caps = DeviceCapabilities::default();
      caps.max_transmission_unit = 1520;
      let result = socket.dispatch(timestamp, &caps, |(ip_repr, tcp_repr)| {
         let ip_repr = ip_repr.lower(&[IpCidr::new(LOCAL_END.addr, 24)]).unwrap();

         assert_eq!(ip_repr.protocol(), IpProtocol::Tcp);
         assert_eq!(ip_repr.src_addr(), MOCK_IP_ADDR_1);
         assert_eq!(ip_repr.dst_addr(), MOCK_IP_ADDR_2);
         assert_eq!(ip_repr.payload_len(), tcp_repr.buffer_len());

         net_trace!("recv: {}", tcp_repr);
         Ok(f(Ok(tcp_repr)))
      });
      match result {
         Ok(()) => (),
         Err(e) => f(Err(e))
      }
   }

   macro_rules! send {
      ($socket:ident, $repr:expr) =>
         (send!($socket, time 0, $repr));
      ($socket:ident, $repr:expr, $result:expr) =>
         (send!($socket, time 0, $repr, $result));
      ($socket:ident, time $time:expr, $repr:expr) =>
         (send!($socket, time $time, $repr, Ok(None)));
      ($socket:ident, time $time:expr, $repr:expr, $result:expr) =>
         (assert_eq!(send(&mut $socket, $time, &$repr), $result));
   }

   macro_rules! recv {
      ($socket:ident, [$( $repr:expr ),*]) => ({
         $( recv!($socket, Ok($repr)); )*
         recv!($socket, Err(Error::Exhausted))
      });
      ($socket:ident, $result:expr) =>
         (recv!($socket, time 0, $result));
      ($socket:ident, time $time:expr, $result:expr) =>
         (recv(&mut $socket, $time, |result| {
            // Most of the time we don't care about the PSH flag.
            let result = result.map(|mut repr| {
               repr.control = repr.control.quash_psh();
               repr
            });
            assert_eq!(result, $result)
         }));
      ($socket:ident, time $time:expr, $result:expr, exact) =>
         (recv(&mut $socket, $time, |repr| assert_eq!(repr, $result)));
   }

   macro_rules! sanity {
      ($socket1:expr, $socket2:expr) => ({
         let (s1, s2) = ($socket1, $socket2);
         assert_eq!(s1.state,         s2.state,         "state");
         assert_eq!(s1.listen_address,   s2.listen_address,  "listen_address");
         assert_eq!(s1.local_endpoint,   s2.local_endpoint,  "local_endpoint");
         assert_eq!(s1.remote_endpoint,  s2.remote_endpoint, "remote_endpoint");
         assert_eq!(s1.local_seq_no,    s2.local_seq_no,   "local_seq_no");
         assert_eq!(s1.remote_seq_no,   s2.remote_seq_no,   "remote_seq_no");
         assert_eq!(s1.remote_last_seq,  s2.remote_last_seq, "remote_last_seq");
         assert_eq!(s1.remote_last_ack,  s2.remote_last_ack, "remote_last_ack");
         assert_eq!(s1.remote_last_win,  s2.remote_last_win, "remote_last_win");
         assert_eq!(s1.remote_win_len,   s2.remote_win_len,  "remote_win_len");
         assert_eq!(s1.timer,         s2.timer,         "timer");
      })
   }

   #[cfg(feature = "log")]
   fn init_logger() {
      extern crate log;
      use std::boxed::Box;

      struct Logger(());

      impl log::Log for Logger {
         fn enabled(&self, _metadata: &log::LogMetadata) -> bool {
            true
         }

         fn log(&self, record: &log::LogRecord) {
            println!("{}", record.args());
         }
      }

      let _ = log::set_logger(|max_level| {
         max_level.set(log::LogLevelFilter::Trace);
         Box::new(Logger(()))
      });

      println!("");
   }

   fn socket() -> TcpSocket<'static> {
      #[cfg(feature = "log")]
      init_logger();

      let rx_buffer = SocketBuffer::new(vec![0; 64]);
      let tx_buffer = SocketBuffer::new(vec![0; 64]);
      TcpSocket::new(rx_buffer, tx_buffer)
   }

   fn socket_syn_received() -> TcpSocket<'static> {
      let mut s = socket();
      s.state         = State::SynReceived;
      s.local_endpoint  = LOCAL_END;
      s.remote_endpoint = REMOTE_END;
      s.local_seq_no   = LOCAL_SEQ;
      s.remote_seq_no   = REMOTE_SEQ + 1;
      s.remote_last_seq = LOCAL_SEQ;
      s.remote_win_len  = 256;
      s
   }

   fn socket_syn_sent() -> TcpSocket<'static> {
      let mut s = socket();
      s.state         = State::SynSent;
      s.local_endpoint  = IpEndpoint::new(MOCK_UNSPECIFIED, LOCAL_PORT);
      s.remote_endpoint = REMOTE_END;
      s.local_seq_no   = LOCAL_SEQ;
      s.remote_last_seq = LOCAL_SEQ;
      s
   }

   fn socket_established() -> TcpSocket<'static> {
      let mut s = socket_syn_received();
      s.state         = State::Established;
      s.local_seq_no   = LOCAL_SEQ + 1;
      s.remote_last_seq = LOCAL_SEQ + 1;
      s.remote_last_ack = Some(REMOTE_SEQ + 1);
      s.remote_last_win = 64;
      s
   }

   fn socket_fin_wait_1() -> TcpSocket<'static> {
      let mut s = socket_established();
      s.state         = State::FinWait1;
      s
   }

   fn socket_fin_wait_2() -> TcpSocket<'static> {
      let mut s = socket_fin_wait_1();
      s.state         = State::FinWait2;
      s.local_seq_no   = LOCAL_SEQ + 1 + 1;
      s.remote_last_seq = LOCAL_SEQ + 1 + 1;
      s
   }

   fn socket_closing() -> TcpSocket<'static> {
      let mut s = socket_fin_wait_1();
      s.state         = State::Closing;
      s.remote_last_seq = LOCAL_SEQ + 1 + 1;
      s.remote_seq_no   = REMOTE_SEQ + 1 + 1;
      s
   }

   fn socket_time_wait(from_closing: bool) -> TcpSocket<'static> {
      let mut s = socket_fin_wait_2();
      s.state         = State::TimeWait;
      s.remote_seq_no   = REMOTE_SEQ + 1 + 1;
      if from_closing {
         s.remote_last_ack = Some(REMOTE_SEQ + 1 + 1);
      }
      s.timer         = Timer::Close { expires_at: 1_000 + CLOSE_DELAY };
      s
   }

   fn socket_close_wait() -> TcpSocket<'static> {
      let mut s = socket_established();
      s.state         = State::CloseWait;
      s.remote_seq_no   = REMOTE_SEQ + 1 + 1;
      s.remote_last_ack = Some(REMOTE_SEQ + 1 + 1);
      s
   }

   fn socket_last_ack() -> TcpSocket<'static> {
      let mut s = socket_close_wait();
      s.state         = State::LastAck;
      s
   }

   fn socket_recved() -> TcpSocket<'static> {
      let mut s = socket_established();
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..SEND_TEMPL
      });
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6),
         window_len: 58,
         ..RECV_TEMPL
      }]);
      s
   }

   // =========================================================================================//
   // Tests for the CLOSED state.
   // =========================================================================================//
   #[test]
   fn test_closed_reject() {
      let s = socket();
      assert_eq!(s.state, State::Closed);

      let tcp_repr = TcpRepr {
         control: TcpControl::Syn,
         ..SEND_TEMPL
      };
      assert!(!s.accepts(&SEND_IP_TEMPL, &tcp_repr));
   }

   #[test]
   fn test_closed_reject_after_listen() {
      let mut s = socket();
      s.listen(LOCAL_END).unwrap();
      s.close();

      let tcp_repr = TcpRepr {
         control: TcpControl::Syn,
         ..SEND_TEMPL
      };
      assert!(!s.accepts(&SEND_IP_TEMPL, &tcp_repr));
   }

   #[test]
   fn test_closed_close() {
      let mut s = socket();
      s.close();
      assert_eq!(s.state, State::Closed);
   }

   // =========================================================================================//
   // Tests for the LISTEN state.
   // =========================================================================================//
   fn socket_listen() -> TcpSocket<'static> {
      let mut s = socket();
      s.state         = State::Listen;
      s.local_endpoint  = IpEndpoint::new(IpAddress::default(), LOCAL_PORT);
      s
   }

   #[test]
   fn test_listen_sanity() {
      let mut s = socket();
      s.listen(LOCAL_PORT).unwrap();
      sanity!(s, socket_listen());
   }

   #[test]
   fn test_listen_validation() {
      let mut s = socket();
      assert_eq!(s.listen(0), Err(Error::Unaddressable));
   }

   #[test]
   fn test_listen_twice() {
      let mut s = socket();
      assert_eq!(s.listen(80), Ok(()));
      assert_eq!(s.listen(80), Err(Error::Illegal));
   }

   #[test]
   fn test_listen_syn() {
      let mut s = socket_listen();
      send!(s, TcpRepr {
         control:   TcpControl::Syn,
         seq_number: REMOTE_SEQ,
         ack_number: None,
         ..SEND_TEMPL
      });
      sanity!(s, socket_syn_received());
   }

   #[test]
   fn test_listen_syn_reject_ack() {
      let s = socket_listen();

      let tcp_repr = TcpRepr {
         control: TcpControl::Syn,
         seq_number: REMOTE_SEQ,
         ack_number: Some(LOCAL_SEQ),
         ..SEND_TEMPL
      };
      assert!(!s.accepts(&SEND_IP_TEMPL, &tcp_repr));

      assert_eq!(s.state, State::Listen);
   }

   #[test]
   fn test_listen_rst() {
      let mut s = socket_listen();
      send!(s, TcpRepr {
         control: TcpControl::Rst,
         seq_number: REMOTE_SEQ,
         ack_number: None,
         ..SEND_TEMPL
      }, Err(Error::Dropped));
   }

   #[test]
   fn test_listen_close() {
      let mut s = socket_listen();
      s.close();
      assert_eq!(s.state, State::Closed);
   }

   // =========================================================================================//
   // Tests for the SYN-RECEIVED state.
   // =========================================================================================//

   #[test]
   fn test_syn_received_ack() {
      let mut s = socket_syn_received();
      recv!(s, [TcpRepr {
         control: TcpControl::Syn,
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         max_seg_size: Some(BASE_MSS),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::Established);
      sanity!(s, socket_established());
   }

   #[test]
   fn test_syn_received_fin() {
      let mut s = socket_syn_received();
      recv!(s, [TcpRepr {
         control: TcpControl::Syn,
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         max_seg_size: Some(BASE_MSS),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload: &b"abcdef"[..],
         ..SEND_TEMPL
      });
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6 + 1),
         window_len: 58,
         ..RECV_TEMPL
      }]);
      assert_eq!(s.state, State::CloseWait);
      sanity!(s, TcpSocket {
         remote_last_ack: Some(REMOTE_SEQ + 1 + 6 + 1),
         remote_last_win: 58,
         ..socket_close_wait()
      });
   }

   #[test]
   fn test_syn_received_rst() {
      let mut s = socket_syn_received();
      recv!(s, [TcpRepr {
         control: TcpControl::Syn,
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         max_seg_size: Some(BASE_MSS),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         control: TcpControl::Rst,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::Listen);
      assert_eq!(s.local_endpoint, IpEndpoint::new(IpAddress::Unspecified, LOCAL_END.port));
      assert_eq!(s.remote_endpoint, IpEndpoint::default());
   }

   #[test]
   fn test_syn_received_close() {
      let mut s = socket_syn_received();
      s.close();
      assert_eq!(s.state, State::FinWait1);
   }

   // =========================================================================================//
   // Tests for the SYN-SENT state.
   // =========================================================================================//

   #[test]
   fn test_connect_validation() {
      let mut s = socket();
      assert_eq!(s.connect((IpAddress::Unspecified, 80), LOCAL_END),
               Err(Error::Unaddressable));
      assert_eq!(s.connect(REMOTE_END, (MOCK_UNSPECIFIED, 0)),
               Err(Error::Unaddressable));
      assert_eq!(s.connect((MOCK_UNSPECIFIED, 0), LOCAL_END),
               Err(Error::Unaddressable));
      assert_eq!(s.connect((IpAddress::Unspecified, 80), LOCAL_END),
               Err(Error::Unaddressable));
   }

   #[test]
   fn test_connect() {
      let mut s = socket();
      s.local_seq_no = LOCAL_SEQ;
      s.connect(REMOTE_END, LOCAL_END.port).unwrap();
      assert_eq!(s.local_endpoint, IpEndpoint::new(MOCK_UNSPECIFIED, LOCAL_END.port));
      recv!(s, [TcpRepr {
         control:   TcpControl::Syn,
         seq_number: LOCAL_SEQ,
         ack_number: None,
         max_seg_size: Some(BASE_MSS),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         control:   TcpControl::Syn,
         seq_number: REMOTE_SEQ,
         ack_number: Some(LOCAL_SEQ + 1),
         max_seg_size: Some(BASE_MSS - 80),
         ..SEND_TEMPL
      });
      assert_eq!(s.local_endpoint, LOCAL_END);
   }

   #[test]
   fn test_connect_unspecified_local() {
      let mut s = socket();
      assert_eq!(s.connect(REMOTE_END, (MOCK_UNSPECIFIED, 80)),
               Ok(()));
      s.abort();
      assert_eq!(s.connect(REMOTE_END, (IpAddress::Unspecified, 80)),
               Ok(()));
      s.abort();
   }

   #[test]
   fn test_connect_specified_local() {
      let mut s = socket();
      assert_eq!(s.connect(REMOTE_END, (MOCK_IP_ADDR_2, 80)),
               Ok(()));
   }

   #[test]
   fn test_connect_twice() {
      let mut s = socket();
      assert_eq!(s.connect(REMOTE_END, (IpAddress::Unspecified, 80)),
               Ok(()));
      assert_eq!(s.connect(REMOTE_END, (IpAddress::Unspecified, 80)),
               Err(Error::Illegal));
   }

   #[test]
   fn test_syn_sent_sanity() {
      let mut s = socket();
      s.local_seq_no   = LOCAL_SEQ;
      s.connect(REMOTE_END, LOCAL_END).unwrap();
      sanity!(s, socket_syn_sent());
   }

   #[test]
   fn test_syn_sent_syn_ack() {
      let mut s = socket_syn_sent();
      recv!(s, [TcpRepr {
         control:   TcpControl::Syn,
         seq_number: LOCAL_SEQ,
         ack_number: None,
         max_seg_size: Some(BASE_MSS),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         control:   TcpControl::Syn,
         seq_number: REMOTE_SEQ,
         ack_number: Some(LOCAL_SEQ + 1),
         max_seg_size: Some(BASE_MSS - 80),
         ..SEND_TEMPL
      });
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }]);
      recv!(s, time 1000, Err(Error::Exhausted));
      assert_eq!(s.state, State::Established);
      sanity!(s, socket_established());
   }

   #[test]
   fn test_syn_sent_rst() {
      let mut s = socket_syn_sent();
      send!(s, TcpRepr {
         control: TcpControl::Rst,
         seq_number: REMOTE_SEQ,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::Closed);
   }

   #[test]
   fn test_syn_sent_rst_no_ack() {
      let mut s = socket_syn_sent();
      send!(s, TcpRepr {
         control: TcpControl::Rst,
         seq_number: REMOTE_SEQ,
         ack_number: None,
         ..SEND_TEMPL
      }, Err(Error::Dropped));
      assert_eq!(s.state, State::SynSent);
   }

   #[test]
   fn test_syn_sent_rst_bad_ack() {
      let mut s = socket_syn_sent();
      send!(s, TcpRepr {
         control: TcpControl::Rst,
         seq_number: REMOTE_SEQ,
         ack_number: Some(TcpSeqNumber(1234)),
         ..SEND_TEMPL
      }, Err(Error::Dropped));
      assert_eq!(s.state, State::SynSent);
   }

   #[test]
   fn test_syn_sent_close() {
      let mut s = socket();
      s.close();
      assert_eq!(s.state, State::Closed);
   }

   // =========================================================================================//
   // Tests for the ESTABLISHED state.
   // =========================================================================================//

   #[test]
   fn test_established_recv() {
      let mut s = socket_established();
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload: &b"abcdef"[..],
         ..SEND_TEMPL
      });
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6),
         window_len: 58,
         ..RECV_TEMPL
      }]);
      assert_eq!(s.rx_buffer.dequeue_many(6), &b"abcdef"[..]);
   }

   #[test]
   fn test_established_send() {
      let mut s = socket_established();
      // First roundtrip after establishing.
      s.send_slice(b"abcdef").unwrap();
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload: &b"abcdef"[..],
         ..RECV_TEMPL
      }]);
      assert_eq!(s.tx_buffer.len(), 6);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6),
         ..SEND_TEMPL
      });
      assert_eq!(s.tx_buffer.len(), 0);
      // Second roundtrip.
      s.send_slice(b"foobar").unwrap();
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload: &b"foobar"[..],
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6 + 6),
         ..SEND_TEMPL
      });
      assert_eq!(s.tx_buffer.len(), 0);
   }

   #[test]
   fn test_established_send_no_ack_send() {
      let mut s = socket_established();
      s.send_slice(b"abcdef").unwrap();
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload: &b"abcdef"[..],
         ..RECV_TEMPL
      }]);
      s.send_slice(b"foobar").unwrap();
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload: &b"foobar"[..],
         ..RECV_TEMPL
      }]);
   }

   #[test]
   fn test_established_send_buf_gt_win() {
      let mut data = [0; 32];
      for (i, elem) in data.iter_mut().enumerate() {
         *elem = i as u8
      }

      let mut s = socket_established();
      s.remote_win_len = 16;
      s.send_slice(&data[..]).unwrap();
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload: &data[0..16],
         ..RECV_TEMPL
      }, TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 16,
         ack_number: Some(REMOTE_SEQ + 1),
         payload: &data[16..32],
         ..RECV_TEMPL
      }]);
   }

   #[test]
   fn test_established_send_wrap() {
      let mut s = socket_established();
      let local_seq_start = TcpSeqNumber(i32::MAX - 1);
      s.local_seq_no = local_seq_start + 1;
      s.remote_last_seq = local_seq_start + 1;
      s.send_slice(b"abc").unwrap();
      recv!(s, time 1000, Ok(TcpRepr {
         seq_number: local_seq_start + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abc"[..],
         ..RECV_TEMPL
      }));
   }

   #[test]
   fn test_established_no_ack() {
      let mut s = socket_established();
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: None,
         ..SEND_TEMPL
      }, Err(Error::Dropped));
   }

   #[test]
   fn test_established_bad_ack() {
      let mut s = socket_established();
      // Already acknowledged data.
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(TcpSeqNumber(LOCAL_SEQ.0 - 1)),
         ..SEND_TEMPL
      }, Err(Error::Dropped));
      assert_eq!(s.local_seq_no, LOCAL_SEQ + 1);
      // Data not yet transmitted.
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 10),
         ..SEND_TEMPL
      }, Ok(Some(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      })));
      assert_eq!(s.local_seq_no, LOCAL_SEQ + 1);
   }

   #[test]
   fn test_established_bad_seq() {
      let mut s = socket_established();
      // Data outside of receive window.
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 256,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      }, Ok(Some(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      })));
      assert_eq!(s.remote_seq_no, REMOTE_SEQ + 1);
   }

   #[test]
   fn test_established_fin() {
      let mut s = socket_established();
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
      assert_eq!(s.state, State::CloseWait);
      sanity!(s, socket_close_wait());
   }

   #[test]
   fn test_established_fin_after_missing() {
      let mut s = socket_established();
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1 + 6,
         ack_number: Some(LOCAL_SEQ + 1),
         payload: &b"123456"[..],
         ..SEND_TEMPL
      }, Ok(Some(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      })));
      assert_eq!(s.state, State::Established);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload: &b"abcdef"[..],
         ..SEND_TEMPL
      }, Ok(Some(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6 + 6),
         window_len: 52,
         ..RECV_TEMPL
      })));
      assert_eq!(s.state, State::Established);
   }

   #[test]
   fn test_established_send_fin() {
      let mut s = socket_established();
      s.send_slice(b"abcdef").unwrap();
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::CloseWait);
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         payload: &b"abcdef"[..],
         ..RECV_TEMPL
      }]);
   }

   #[test]
   fn test_established_rst() {
      let mut s = socket_established();
      send!(s, TcpRepr {
         control: TcpControl::Rst,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::Closed);
   }

   #[test]
   fn test_established_rst_no_ack() {
      let mut s = socket_established();
      send!(s, TcpRepr {
         control: TcpControl::Rst,
         seq_number: REMOTE_SEQ + 1,
         ack_number: None,
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::Closed);
   }

   #[test]
   fn test_established_close() {
      let mut s = socket_established();
      s.close();
      assert_eq!(s.state, State::FinWait1);
      sanity!(s, socket_fin_wait_1());
   }

   #[test]
   fn test_established_abort() {
      let mut s = socket_established();
      s.abort();
      assert_eq!(s.state, State::Closed);
      recv!(s, [TcpRepr {
         control: TcpControl::Rst,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }]);
   }

   // =========================================================================================//
   // Tests for the FIN-WAIT-1 state.
   // =========================================================================================//

   #[test]
   fn test_fin_wait_1_fin_ack() {
      let mut s = socket_fin_wait_1();
      recv!(s, [TcpRepr {
         control: TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::FinWait2);
      sanity!(s, socket_fin_wait_2());
   }

   #[test]
   fn test_fin_wait_1_fin_fin() {
      let mut s = socket_fin_wait_1();
      recv!(s, [TcpRepr {
         control: TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::Closing);
      sanity!(s, socket_closing());
   }

   #[test]
   fn test_fin_wait_1_fin_with_data_queued() {
      let mut s = socket_established();
      s.remote_win_len = 6;
      s.send_slice(b"abcdef123456").unwrap();
      s.close();
      recv!(s, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }));
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::FinWait1);
   }

   #[test]
   fn test_fin_wait_1_close() {
      let mut s = socket_fin_wait_1();
      s.close();
      assert_eq!(s.state, State::FinWait1);
   }

   // =========================================================================================//
   // Tests for the FIN-WAIT-2 state.
   // =========================================================================================//

   #[test]
   fn test_fin_wait_2_fin() {
      let mut s = socket_fin_wait_2();
      send!(s, time 1_000, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::TimeWait);
      sanity!(s, socket_time_wait(false));
   }

   #[test]
   fn test_fin_wait_2_close() {
      let mut s = socket_fin_wait_2();
      s.close();
      assert_eq!(s.state, State::FinWait2);
   }

   // =========================================================================================//
   // Tests for the CLOSING state.
   // =========================================================================================//

   #[test]
   fn test_closing_ack_fin() {
      let mut s = socket_closing();
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
      send!(s, time 1_000, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::TimeWait);
      sanity!(s, socket_time_wait(true));
   }

   #[test]
   fn test_closing_close() {
      let mut s = socket_closing();
      s.close();
      assert_eq!(s.state, State::Closing);
   }

   // =========================================================================================//
   // Tests for the TIME-WAIT state.
   // =========================================================================================//

   #[test]
   fn test_time_wait_from_fin_wait_2_ack() {
      let mut s = socket_time_wait(false);
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
   }

   #[test]
   fn test_time_wait_from_closing_no_ack() {
      let mut s = socket_time_wait(true);
      recv!(s, []);
   }

   #[test]
   fn test_time_wait_close() {
      let mut s = socket_time_wait(false);
      s.close();
      assert_eq!(s.state, State::TimeWait);
   }

   #[test]
   fn test_time_wait_retransmit() {
      let mut s = socket_time_wait(false);
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
      send!(s, time 5_000, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 1),
         ..SEND_TEMPL
      }, Ok(Some(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      })));
      assert_eq!(s.timer, Timer::Close { expires_at: 5_000 + CLOSE_DELAY });
   }

   #[test]
   fn test_time_wait_timeout() {
      let mut s = socket_time_wait(false);
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
      assert_eq!(s.state, State::TimeWait);
      recv!(s, time 60_000, Err(Error::Exhausted));
      assert_eq!(s.state, State::Closed);
   }

   // =========================================================================================//
   // Tests for the CLOSE-WAIT state.
   // =========================================================================================//

   #[test]
   fn test_close_wait_ack() {
      let mut s = socket_close_wait();
      s.send_slice(b"abcdef").unwrap();
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         payload: &b"abcdef"[..],
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6),
         ..SEND_TEMPL
      });
   }

   #[test]
   fn test_close_wait_close() {
      let mut s = socket_close_wait();
      s.close();
      assert_eq!(s.state, State::LastAck);
      sanity!(s, socket_last_ack());
   }

   // =========================================================================================//
   // Tests for the LAST-ACK state.
   // =========================================================================================//
   #[test]
   fn test_last_ack_fin_ack() {
      let mut s = socket_last_ack();
      recv!(s, [TcpRepr {
         control: TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
      assert_eq!(s.state, State::LastAck);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::Closed);
   }

   #[test]
   fn test_last_ack_close() {
      let mut s = socket_last_ack();
      s.close();
      assert_eq!(s.state, State::LastAck);
   }

   // =========================================================================================//
   // Tests for transitioning through multiple states.
   // =========================================================================================//

   #[test]
   fn test_listen() {
      let mut s = socket();
      s.listen(IpEndpoint::new(IpAddress::default(), LOCAL_PORT)).unwrap();
      assert_eq!(s.state, State::Listen);
   }

   #[test]
   fn test_three_way_handshake() {
      let mut s = socket_listen();
      send!(s, TcpRepr {
         control: TcpControl::Syn,
         seq_number: REMOTE_SEQ,
         ack_number: None,
         ..SEND_TEMPL
      });
      assert_eq!(s.state(), State::SynReceived);
      assert_eq!(s.local_endpoint(), LOCAL_END);
      assert_eq!(s.remote_endpoint(), REMOTE_END);
      recv!(s, [TcpRepr {
         control: TcpControl::Syn,
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         max_seg_size: Some(BASE_MSS),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state(), State::Established);
      assert_eq!(s.local_seq_no, LOCAL_SEQ + 1);
      assert_eq!(s.remote_seq_no, REMOTE_SEQ + 1);
   }

   #[test]
   fn test_remote_close() {
      let mut s = socket_established();
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::CloseWait);
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
      s.close();
      assert_eq!(s.state, State::LastAck);
      recv!(s, [TcpRepr {
         control: TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::Closed);
   }

   #[test]
   fn test_local_close() {
      let mut s = socket_established();
      s.close();
      assert_eq!(s.state, State::FinWait1);
      recv!(s, [TcpRepr {
         control: TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::FinWait2);
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::TimeWait);
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
   }

   #[test]
   fn test_simultaneous_close() {
      let mut s = socket_established();
      s.close();
      assert_eq!(s.state, State::FinWait1);
      recv!(s, [TcpRepr { // due to reordering, this is logically located...
         control: TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::Closing);
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
      // ... at this point
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::TimeWait);
      recv!(s, []);
   }

   #[test]
   fn test_simultaneous_close_combined_fin_ack() {
      let mut s = socket_established();
      s.close();
      assert_eq!(s.state, State::FinWait1);
      recv!(s, [TcpRepr {
         control: TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::TimeWait);
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
   }

   #[test]
   fn test_fin_with_data() {
      let mut s = socket_established();
      s.send_slice(b"abcdef").unwrap();
      s.close();
      recv!(s, [TcpRepr {
         control:   TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }])
   }

   #[test]
   fn test_mutual_close_with_data_1() {
      let mut s = socket_established();
      s.send_slice(b"abcdef").unwrap();
      s.close();
      assert_eq!(s.state, State::FinWait1);
      recv!(s, [TcpRepr {
         control: TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6 + 1),
         ..SEND_TEMPL
      });
   }

   #[test]
   fn test_mutual_close_with_data_2() {
      let mut s = socket_established();
      s.send_slice(b"abcdef").unwrap();
      s.close();
      assert_eq!(s.state, State::FinWait1);
      recv!(s, [TcpRepr {
         control: TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6 + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state, State::FinWait2);
      send!(s, TcpRepr {
         control: TcpControl::Fin,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6 + 1),
         ..SEND_TEMPL
      });
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6 + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }]);
      assert_eq!(s.state, State::TimeWait);
   }

   // =========================================================================================//
   // Tests for retransmission on packet loss.
   // =========================================================================================//

   #[test]
   fn test_duplicate_seq_ack() {
      let mut s = socket_recved();
      // remote retransmission
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..SEND_TEMPL
      }, Ok(Some(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6),
         window_len: 58,
         ..RECV_TEMPL
      })));
   }

   #[test]
   fn test_data_retransmit() {
      let mut s = socket_established();
      s.send_slice(b"abcdef").unwrap();
      recv!(s, time 1000, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }));
      recv!(s, time 1050, Err(Error::Exhausted));
      recv!(s, time 1100, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }));
   }

   #[test]
   fn test_data_retransmit_bursts() {
      let mut s = socket_established();
      s.remote_win_len = 6;
      s.send_slice(b"abcdef012345").unwrap();

      recv!(s, time 0, Ok(TcpRepr {
         control:   TcpControl::None,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }), exact);
      s.remote_win_len = 6;
      recv!(s, time 0, Ok(TcpRepr {
         control:   TcpControl::Psh,
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"012345"[..],
         ..RECV_TEMPL
      }), exact);
      s.remote_win_len = 6;
      recv!(s, time 0, Err(Error::Exhausted));

      recv!(s, time 50, Err(Error::Exhausted));

      recv!(s, time 100, Ok(TcpRepr {
         control:   TcpControl::None,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }), exact);
      s.remote_win_len = 6;
      recv!(s, time 150, Ok(TcpRepr {
         control:   TcpControl::Psh,
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"012345"[..],
         ..RECV_TEMPL
      }), exact);
      s.remote_win_len = 6;
      recv!(s, time 200, Err(Error::Exhausted));
   }

   #[test]
   fn test_send_data_after_syn_ack_retransmit() {
      let mut s = socket_syn_received();
      recv!(s, time 50, Ok(TcpRepr {
         control:   TcpControl::Syn,
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         max_seg_size: Some(BASE_MSS),
         ..RECV_TEMPL
      }));
      recv!(s, time 150, Ok(TcpRepr { // retransmit
         control:   TcpControl::Syn,
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         max_seg_size: Some(BASE_MSS),
         ..RECV_TEMPL
      }));
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.state(), State::Established);
      s.send_slice(b"abcdef").unwrap();
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }])
   }

   #[test]
   fn test_established_retransmit_for_dup_ack() {
      let mut s = socket_established();
      // Duplicate ACKs do not replace the retransmission timer
      s.send_slice(b"abc").unwrap();
      recv!(s, time 1000, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abc"[..],
         ..RECV_TEMPL
      }));
      // Retransmit timer is on because all data was sent
      assert_eq!(s.tx_buffer.len(), 3);
      // ACK nothing new
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      // Retransmit
      recv!(s, time 4000, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abc"[..],
         ..RECV_TEMPL
      }));
   }

   #[test]
   fn test_established_retransmit_reset_after_ack() {
      let mut s = socket_established();
      s.remote_win_len = 6;
      s.send_slice(b"abcdef").unwrap();
      s.send_slice(b"123456").unwrap();
      s.send_slice(b"ABCDEF").unwrap();
      recv!(s, time 1000, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }));
      send!(s, time 1005, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6),
         window_len: 6,
         ..SEND_TEMPL
      });
      recv!(s, time 1010, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"123456"[..],
         ..RECV_TEMPL
      }));
      send!(s, time 1015, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6 + 6),
         window_len: 6,
         ..SEND_TEMPL
      });
      recv!(s, time 1020, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"ABCDEF"[..],
         ..RECV_TEMPL
      }));
   }

   #[test]
   fn test_established_queue_during_retransmission() {
      let mut s = socket_established();
      s.remote_mss = 6;
      s.send_slice(b"abcdef123456ABCDEF").unwrap();
      recv!(s, time 1000, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      })); // this one is dropped
      recv!(s, time 1005, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"123456"[..],
         ..RECV_TEMPL
      })); // this one is received
      recv!(s, time 1010, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"ABCDEF"[..],
         ..RECV_TEMPL
      })); // also dropped
      recv!(s, time 2000, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      })); // retransmission
      send!(s, time 2005, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6 + 6),
         ..SEND_TEMPL
      }); // acknowledgement of both segments
      recv!(s, time 2010, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"ABCDEF"[..],
         ..RECV_TEMPL
      })); // retransmission of only unacknowledged data
   }

   #[test]
   fn test_close_wait_retransmit_reset_after_ack() {
      let mut s = socket_close_wait();
      s.remote_win_len = 6;
      s.send_slice(b"abcdef").unwrap();
      s.send_slice(b"123456").unwrap();
      s.send_slice(b"ABCDEF").unwrap();
      recv!(s, time 1000, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }));
      send!(s, time 1005, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6),
         window_len: 6,
         ..SEND_TEMPL
      });
      recv!(s, time 1010, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         payload:   &b"123456"[..],
         ..RECV_TEMPL
      }));
      send!(s, time 1015, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6 + 6),
         window_len: 6,
         ..SEND_TEMPL
      });
      recv!(s, time 1020, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6 + 6,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         payload:   &b"ABCDEF"[..],
         ..RECV_TEMPL
      }));
   }

   #[test]
   fn test_fin_wait_1_retransmit_reset_after_ack() {
      let mut s = socket_established();
      s.remote_win_len = 6;
      s.send_slice(b"abcdef").unwrap();
      s.send_slice(b"123456").unwrap();
      s.send_slice(b"ABCDEF").unwrap();
      s.close();
      recv!(s, time 1000, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }));
      send!(s, time 1005, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6),
         window_len: 6,
         ..SEND_TEMPL
      });
      recv!(s, time 1010, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"123456"[..],
         ..RECV_TEMPL
      }));
      send!(s, time 1015, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 6 + 6),
         window_len: 6,
         ..SEND_TEMPL
      });
      recv!(s, time 1020, Ok(TcpRepr {
         control:   TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1 + 6 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"ABCDEF"[..],
         ..RECV_TEMPL
      }));
   }

   // =========================================================================================//
   // Tests for window management.
   // =========================================================================================//

   #[test]
   fn test_maximum_segment_size() {
      let mut s = socket_listen();
      s.tx_buffer = SocketBuffer::new(vec![0; 32767]);
      send!(s, TcpRepr {
         control: TcpControl::Syn,
         seq_number: REMOTE_SEQ,
         ack_number: None,
         max_seg_size: Some(1000),
         ..SEND_TEMPL
      });
      recv!(s, [TcpRepr {
         control: TcpControl::Syn,
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         max_seg_size: Some(BASE_MSS),
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         window_len: 32767,
         ..SEND_TEMPL
      });
      s.send_slice(&[0; 1200][..]).unwrap();
      recv!(s, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload: &[0; 1000][..],
         ..RECV_TEMPL
      }));
   }

   // =========================================================================================//
   // Tests for flow control.
   // =========================================================================================//

   #[test]
   fn test_psh_transmit() {
      let mut s = socket_established();
      s.remote_win_len = 6;
      s.send_slice(b"abcdef").unwrap();
      s.send_slice(b"123456").unwrap();
      recv!(s, time 0, Ok(TcpRepr {
         control:   TcpControl::None,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }), exact);
      recv!(s, time 0, Ok(TcpRepr {
         control:   TcpControl::Psh,
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"123456"[..],
         ..RECV_TEMPL
      }), exact);
   }

   #[test]
   fn test_psh_receive() {
      let mut s = socket_established();
      send!(s, TcpRepr {
         control:   TcpControl::Psh,
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..SEND_TEMPL
      });
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6),
         window_len: 58,
         ..RECV_TEMPL
      }]);
   }

   #[test]
   fn test_zero_window_ack() {
      let mut s = socket_established();
      s.rx_buffer = SocketBuffer::new(vec![0; 6]);
      s.assembler = Assembler::new(s.rx_buffer.capacity());
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..SEND_TEMPL
      });
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6),
         window_len: 0,
         ..RECV_TEMPL
      }]);
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 6,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"123456"[..],
         ..SEND_TEMPL
      }, Ok(Some(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6),
         window_len: 0,
         ..RECV_TEMPL
      })));
   }

   #[test]
   fn test_zero_window_ack_on_window_growth() {
      let mut s = socket_established();
      s.rx_buffer = SocketBuffer::new(vec![0; 6]);
      s.assembler = Assembler::new(s.rx_buffer.capacity());
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..SEND_TEMPL
      });
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6),
         window_len: 0,
         ..RECV_TEMPL
      }]);
      recv!(s, time 0, Err(Error::Exhausted));
      s.recv(|buffer| {
         assert_eq!(&buffer[..3], b"abc");
         (3, ())
      }).unwrap();
      recv!(s, time 0, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6),
         window_len: 3,
         ..RECV_TEMPL
      }));
      recv!(s, time 0, Err(Error::Exhausted));
      s.recv(|buffer| {
         assert_eq!(buffer, b"def");
         (buffer.len(), ())
      }).unwrap();
      recv!(s, time 0, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6),
         window_len: 6,
         ..RECV_TEMPL
      }));
   }

   #[test]
   fn test_fill_peer_window() {
      let mut s = socket_established();
      s.remote_mss = 6;
      s.send_slice(b"abcdef123456!@#$%^").unwrap();
      recv!(s, [TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }, TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"123456"[..],
         ..RECV_TEMPL
      }, TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 6 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"!@#$%^"[..],
         ..RECV_TEMPL
      }]);
   }

   // =========================================================================================//
   // Tests for timeouts.
   // =========================================================================================//

   #[test]
   fn test_listen_timeout() {
      let mut s = socket_listen();
      s.set_timeout(Some(100));
      assert_eq!(s.poll_at(), None);
   }

   #[test]
   fn test_connect_timeout() {
      let mut s = socket();
      s.local_seq_no = LOCAL_SEQ;
      s.connect(REMOTE_END, LOCAL_END.port).unwrap();
      s.set_timeout(Some(100));
      recv!(s, time 150, Ok(TcpRepr {
         control:   TcpControl::Syn,
         seq_number: LOCAL_SEQ,
         ack_number: None,
         max_seg_size: Some(BASE_MSS),
         ..RECV_TEMPL
      }));
      assert_eq!(s.state, State::SynSent);
      assert_eq!(s.poll_at(), Some(250));
      recv!(s, time 250, Ok(TcpRepr {
         control:   TcpControl::Rst,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(TcpSeqNumber(0)),
         ..RECV_TEMPL
      }));
      assert_eq!(s.state, State::Closed);
   }

   #[test]
   fn test_established_timeout() {
      let mut s = socket_established();
      s.set_timeout(Some(200));
      recv!(s, time 250, Err(Error::Exhausted));
      assert_eq!(s.poll_at(), Some(450));
      s.send_slice(b"abcdef").unwrap();
      assert_eq!(s.poll_at(), Some(0));
      recv!(s, time 255, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }));
      assert_eq!(s.poll_at(), Some(355));
      recv!(s, time 355, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..RECV_TEMPL
      }));
      assert_eq!(s.poll_at(), Some(455));
      recv!(s, time 500, Ok(TcpRepr {
         control:   TcpControl::Rst,
         seq_number: LOCAL_SEQ + 1 + 6,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }));
      assert_eq!(s.state, State::Closed);
   }

   #[test]
   fn test_established_keep_alive_timeout() {
      let mut s = socket_established();
      s.set_keep_alive(Some(50));
      s.set_timeout(Some(100));
      recv!(s, time 100, Ok(TcpRepr {
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &[0],
         ..RECV_TEMPL
      }));
      recv!(s, time 100, Err(Error::Exhausted));
      assert_eq!(s.poll_at(), Some(150));
      send!(s, time 105, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.poll_at(), Some(155));
      recv!(s, time 155, Ok(TcpRepr {
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &[0],
         ..RECV_TEMPL
      }));
      recv!(s, time 155, Err(Error::Exhausted));
      assert_eq!(s.poll_at(), Some(205));
      recv!(s, time 200, Err(Error::Exhausted));
      recv!(s, time 205, Ok(TcpRepr {
         control:   TcpControl::Rst,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }));
      recv!(s, time 205, Err(Error::Exhausted));
      assert_eq!(s.state, State::Closed);
   }

   #[test]
   fn test_fin_wait_1_timeout() {
      let mut s = socket_fin_wait_1();
      s.set_timeout(Some(200));
      recv!(s, time 100, Ok(TcpRepr {
         control:   TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }));
      assert_eq!(s.poll_at(), Some(200));
      recv!(s, time 400, Ok(TcpRepr {
         control:   TcpControl::Rst,
         seq_number: LOCAL_SEQ + 1 + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }));
      assert_eq!(s.state, State::Closed);
   }

   #[test]
   fn test_last_ack_timeout() {
      let mut s = socket_last_ack();
      s.set_timeout(Some(200));
      recv!(s, time 100, Ok(TcpRepr {
         control:   TcpControl::Fin,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }));
      assert_eq!(s.poll_at(), Some(200));
      recv!(s, time 400, Ok(TcpRepr {
         control:   TcpControl::Rst,
         seq_number: LOCAL_SEQ + 1 + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 1),
         ..RECV_TEMPL
      }));
      assert_eq!(s.state, State::Closed);
   }

   #[test]
   fn test_closed_timeout() {
      let mut s = socket_established();
      s.set_timeout(Some(200));
      s.remote_last_ts = Some(100);
      s.abort();
      assert_eq!(s.poll_at(), Some(0));
      recv!(s, time 100, Ok(TcpRepr {
         control:   TcpControl::Rst,
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      }));
      assert_eq!(s.poll_at(), None);
   }

   // =========================================================================================//
   // Tests for keep-alive.
   // =========================================================================================//

   #[test]
   fn test_responds_to_keep_alive() {
      let mut s = socket_established();
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      }, Ok(Some(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      })));
   }

   #[test]
   fn test_sends_keep_alive() {
      let mut s = socket_established();
      s.set_keep_alive(Some(100));

      // drain the forced keep-alive packet
      assert_eq!(s.poll_at(), Some(0));
      recv!(s, time 0, Ok(TcpRepr {
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &[0],
         ..RECV_TEMPL
      }));

      assert_eq!(s.poll_at(), Some(100));
      recv!(s, time 95, Err(Error::Exhausted));
      recv!(s, time 100, Ok(TcpRepr {
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &[0],
         ..RECV_TEMPL
      }));

      assert_eq!(s.poll_at(), Some(200));
      recv!(s, time 195, Err(Error::Exhausted));
      recv!(s, time 200, Ok(TcpRepr {
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &[0],
         ..RECV_TEMPL
      }));

      send!(s, time 250, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         ..SEND_TEMPL
      });
      assert_eq!(s.poll_at(), Some(350));
      recv!(s, time 345, Err(Error::Exhausted));
      recv!(s, time 350, Ok(TcpRepr {
         seq_number: LOCAL_SEQ,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"\x00"[..],
         ..RECV_TEMPL
      }));
   }

   // =========================================================================================//
   // Tests for time-to-live configuration.
   // =========================================================================================//

   #[test]
   fn test_set_hop_limit() {
      let mut s = socket_syn_received();
      let mut caps = DeviceCapabilities::default();
      caps.max_transmission_unit = 1520;

      s.set_hop_limit(Some(0x2a));
      assert_eq!(s.dispatch(0, &caps, |(ip_repr, _)| {
         assert_eq!(ip_repr.hop_limit(), 0x2a);
         Ok(())
      }), Ok(()));
   }

   #[test]
   #[should_panic(expected = "the time-to-live value of a packet must not be zero")]
   fn test_set_hop_limit_zero() {
      let mut s = socket_syn_received();
      s.set_hop_limit(Some(0));
   }

   // =========================================================================================//
   // Tests for reassembly.
   // =========================================================================================//

   #[test]
   fn test_out_of_order() {
      let mut s = socket_established();
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 3,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"def"[..],
         ..SEND_TEMPL
      }, Ok(Some(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         ..RECV_TEMPL
      })));
      s.recv(|buffer| {
         assert_eq!(buffer, b"");
         (buffer.len(), ())
      }).unwrap();
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..SEND_TEMPL
      }, Ok(Some(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1 + 6),
         window_len: 58,
         ..RECV_TEMPL
      })));
      s.recv(|buffer| {
         assert_eq!(buffer, b"abcdef");
         (buffer.len(), ())
      }).unwrap();
   }

   #[test]
   fn test_buffer_wraparound_rx() {
      let mut s = socket_established();
      s.rx_buffer = SocketBuffer::new(vec![0; 6]);
      s.assembler = Assembler::new(s.rx_buffer.capacity());
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"abc"[..],
         ..SEND_TEMPL
      });
      s.recv(|buffer| {
         assert_eq!(buffer, b"abc");
         (buffer.len(), ())
      }).unwrap();
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1 + 3,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"defghi"[..],
         ..SEND_TEMPL
      });
      let mut data = [0; 6];
      assert_eq!(s.recv_slice(&mut data[..]), Ok(6));
      assert_eq!(data, &b"defghi"[..]);
   }

   #[test]
   fn test_buffer_wraparound_tx() {
      let mut s = socket_established();
      s.tx_buffer = SocketBuffer::new(vec![0; 6]);
      assert_eq!(s.send_slice(b"abc"), Ok(3));
      recv!(s, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"abc"[..],
         ..RECV_TEMPL
      }));
      send!(s, TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1 + 3),
         ..SEND_TEMPL
      });
      assert_eq!(s.send_slice(b"defghi"), Ok(6));
      recv!(s, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 3,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"def"[..],
         ..RECV_TEMPL
      }));
      // "defghi" not contiguous in tx buffer
      recv!(s, Ok(TcpRepr {
         seq_number: LOCAL_SEQ + 1 + 3 + 3,
         ack_number: Some(REMOTE_SEQ + 1),
         payload:   &b"ghi"[..],
         ..RECV_TEMPL
      }));
   }

   // =========================================================================================//
   // Tests for packet filtering.
   // =========================================================================================//

   #[test]
   fn test_doesnt_accept_wrong_port() {
      let mut s = socket_established();
      s.rx_buffer = SocketBuffer::new(vec![0; 6]);
      s.assembler = Assembler::new(s.rx_buffer.capacity());

      let tcp_repr = TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         dst_port:   LOCAL_PORT + 1,
         ..SEND_TEMPL
      };
      assert!(!s.accepts(&SEND_IP_TEMPL, &tcp_repr));

      let tcp_repr = TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         src_port:   REMOTE_PORT + 1,
         ..SEND_TEMPL
      };
      assert!(!s.accepts(&SEND_IP_TEMPL, &tcp_repr));
   }

   #[test]
   fn test_doesnt_accept_wrong_ip() {
      let s = socket_established();

      let tcp_repr = TcpRepr {
         seq_number: REMOTE_SEQ + 1,
         ack_number: Some(LOCAL_SEQ + 1),
         payload:   &b"abcdef"[..],
         ..SEND_TEMPL
      };

      let ip_repr = IpRepr::Unspecified {
         src_addr:   MOCK_IP_ADDR_2,
         dst_addr:   MOCK_IP_ADDR_1,
         protocol:   IpProtocol::Tcp,
         payload_len: tcp_repr.buffer_len(),
         hop_limit:   64
      };
      assert!(s.accepts(&ip_repr, &tcp_repr));

      let ip_repr_wrong_src = IpRepr::Unspecified {
         src_addr:   MOCK_IP_ADDR_3,
         dst_addr:   MOCK_IP_ADDR_1,
         protocol:   IpProtocol::Tcp,
         payload_len: tcp_repr.buffer_len(),
         hop_limit:   64
      };
      assert!(!s.accepts(&ip_repr_wrong_src, &tcp_repr));

      let ip_repr_wrong_dst = IpRepr::Unspecified {
         src_addr:   MOCK_IP_ADDR_2,
         dst_addr:   MOCK_IP_ADDR_3,
         protocol:   IpProtocol::Tcp,
         payload_len: tcp_repr.buffer_len(),
         hop_limit:   64
      };
      assert!(!s.accepts(&ip_repr_wrong_dst, &tcp_repr));
   }
}
]]
