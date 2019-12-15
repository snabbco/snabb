-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- Simple TCP echo service.

module(..., package.seeall)

local lib        = require("core.lib")
local packet     = require("core.packet")
local link       = require("core.link")
local tcp        = require("lib.tcp.tcp")
local proto      = require("lib.tcp.proto")
local scheduler  = require("lib.fiber.scheduler")
local fiber      = require("lib.fiber.fiber")

Server = {}
local config_params = {
   -- Address or list of addresses to which to bind, as strings of the
   -- format ADDR:PORT, where ADDR is either an IPv4 or IPv6 address.
   bind = { required=true },
}

local function parse_ipv4_address(str)
   local head, tail = str:match("^([%d.]*):([1-9][0-9]*)$")
   if not head then return end
   local parsed = ipv4:pton(head)
   if not parsed then return end
   return { type='ipv4', addr=parsed, port=tonumber(tail) }
end

local function parse_ipv6_address(str)
   local head, tail = str:match("^([%x:]*):([1-9][0-9]*)$")
   if not head then return end
   local parsed = ipv6:pton(head)
   if not parsed then return end
   return { type='ipv6', addr=parsed, port=tonumber(tail) }
end

function Server:new(conf)
   conf = lib.parse(conf, config_params)

   local o = setmetatable({}, {__index = Server})
   o.tcp = tcp.new()

   if type(conf.bind) == 'string' then o:bind(conf.bind)
   else for _,str in ipairs(conf.bind) do o:bind(str) end end

   return o
end

local function echo(fam, sock)
   while fibers.wait_readable(sock) do
      fibers.write(sock, sock:peek())
   end
end

-- Override me!
Server.accept_fn = echo

function Server:bind(addr_and_port)
   local addr, port = parse_ipv4_address(addr_and_port)
   local function accept_ipv4(sock) fiber.spawn(self.accept_fn, 'ipv4', sock) end
   if addr then self.tcp:listen_ipv4(addr, port, accept); return end
   local addr, port = parse_ipv6_address(addr_and_port)
   local function accept_ipv6(sock) fiber.spawn(self.accept_fn, 'ipv6', sock) end
   if addr then self.tcp:listen_ipv6(addr, port, accept); return end
   error('Invalid bind address for server, expected ADDR:PORT: '..tostring(str))
end

function Server:push()
   local now = engine.now()
   self.tcp:advance_clock(now)

   for _ = 1, link.nreadable(self.input.input) do
      local p = link.receive(self.input.input)
      if proto.is_ipv4(p) then
         local ip, tcp, payload_length = proto.parse_ipv4_tcp(p)
         if ip then self.tcp:handle_ipv4(ip, tcp, payload_length) end
      elseif proto.is_ipv6(p) then
         local ip, tcp, payload_length = proto.parse_ipv6_tcp(p)
         if ip then self.tcp:handle_ipv6(ip, tcp, payload_length) end
      end
      packet.free(pkt)
   end

   self.scheduler:advance_clock(now)
   self.scheduler:run_tasks()
end
