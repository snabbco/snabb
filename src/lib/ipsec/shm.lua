-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- shm interface to a customized version of the Strongswan IKE daemon
-- available from https://github.com/alexandergall/strongswan/tree/kernel-snabb-5.6.3
--
-- The assumption is that the IKE SA is established over a regular
-- interface and that there can be any number of Snabb processes that
-- require child-SAs for the communication between different pairs of
-- addresses.  In general, the addresses used for the IKE SAs are not
-- visible by the Snabb processes and vice versa.
--
-- The solution adopted by this implementation requires that each pair
-- of addresses to which a Snabb process applies IPsec needs to be
-- configured as a separate child-SA in the IKE daemon with traffic
-- selectors that match those addresses exactly.  In other words, such
-- a child-SA must have exactly one traffic selector per directon and
-- each selector must be for a host address, i.e. /32 or /128.
--
-- The IKE daemon places data for each SA in a shared memory region
-- conforming to this module.  The backing files for those regions are
-- located in $SNABB_SHM_ROOT/ipsec.  A subdirectory is created for
-- each pair of source and destination traffic selectors.  The name of
-- the directory is the hexadecimal representation (lower case, 8
-- characters) of the lower 32 bits of the Siphash-2-4 of the
-- concatenation of the remote and local traffic selectors in on-the
-- wire format with the static 16-byte key (0, 1, 2, 3, 4, 5, 6, 7, 8,
-- 9, 10, 11, 12, 13, 14, 15).
--
-- Each directory contains two files named "in.ipsec_sa" and
-- "out.ipsec_sa".  The former holds information for the inbound SA
-- (in IPsec nomenclature, i.e. this SA has a SPI chosen by the local
-- IKE daemon) and the latter that of the outbound SA.
--
-- Each file is structured as described in shm.h.
--
-- The file must be created by the Snabb process but is otherwise
-- write-only by the IKE daemon.  From the perspective of the daemon,
-- installation of a SA was successful if the backing file exists and
-- could be written without error.  Otherwise, the SA is discarded by
-- the daemon. Only the latest established SA is available to the
-- Snabb process.
--
-- SPIs for inbound SAs are allocated by the IKE daemon in an
-- incremental fashion starting from 256. Upon startup, a Snabb
-- process MUST unlink the file if it exists and (re-)create it.  This
-- ensures that a key used by a previous instance of the process is
-- never reused (which is a requirement for the application of the
-- AES-GCM cipher). It also initializes the SPI to zero, which
-- indicates that no SA has yet been established by the IKE daemon.
--
-- The Snabb process should periodically check the SA for changes to
-- pick up new keys negotiated by IKE.  The algorithm for this is as
-- follows.
--
--    1) On startup, initialize the "current spi" to zero, disable IPsec
--       processing in both directions
--    2) Read the "spi" and "tstamp" fields from the SA shm
--    3) If the spi is zero, disable IPsec in the relevant direction,
--       go to 2)
--    4) If the spi is different from the current spi, make it the new
--       current spi, store the tstamp, enable IPsec in the relevant
--       direction by creating an appropriate cipher object with the
--       crypto material in the SA, go to 2)
--    5) If the spi is the same as the current spi but the tstamp is different
--       from the cached tstamp, proceed as in 4)
--    6) Otherwise, go to 2)
--
-- The purpose of the time stamp (tstamp) is to detect re-used SPIs due to a
-- restart of the IKE daemon (which resets the SPI to 256).
--
-- Initiation of the IKE and child SAs needs to be done manually,
-- e.g. via "swanctl --initiate" after the IKE daemon and Snabb
-- processes have been started.
--
-- Re-keying of the IKE and child SAs can be triggered at any time via
-- "swanctl --rekey".
--
-- Sample swanctl.conf:
--
-- connections {
--   sun {
--     local_addrs = 10.0.0.1
--     remote_addrs = 10.0.1.1
--     local-sun {
--       auth = psk
--       id = sunmoon
--     }
--     remote-moon {
--       auth = psk
--       id = sunmoon
--     }
--     children {
--       v4 {
--         local_ts = 192.168.0.1/32
--         remote_ts = 192.168.1.1/32
--         esp_proposals = aes128gcm128-x25519-esn
--         mode = tunnel
--       }
--       v6 {
--         local_ts = 2001:db8:0::1/128
--         remote_ts = 2001:db8:1::1/128
--         esp_proposals = aes128gcm128-x25519-esn
--         mode = tunnel
--       }
--     }
--     proposals = aes128-sha256-x25519-esn
--     version = 2
--   }
-- }
-- secrets {
--   ike-1 {
--     id-1 = sunmoon
--     secret = 0sFpZAZqEN6Ti9sqt4ZP5EWcqx
--   }
-- }
--
-- "swanctl --initiate --child v4" and "swanctl --initiate --child v6"
-- will create one IKE SA betwenn 10.0.0.1 and 10.0.1.1 with two
-- child-SAs.  The v4 and v6 SAs will be stored in
-- $SNABB_SHM_ROOT/ipsec/ea8e2f33 and $SNABB_SHM_ROOT/1869cada,
-- respectively.
--
-- The "mode = tunnel" configuration is necessary for the traffic
-- selectors to be accepted.  In transport mode, the selectors are
-- unconditionally chosen to be the local and remote addresses of the
-- IKE SA.  Note that the Snabb process is still free to chose either
-- mode.

module(..., package.seeall)

local lib = require("core.lib")
local shm = require("core.shm")
local ffi = require("ffi")
require("lib.ipsec.shm_h")

type = shm.register('ipsec_sa', getfenv())

local ipsec_t = ffi.typeof("struct ipsec_sa")

local objects = {}

function create(name)
   if objects[name] then
      return ffi.cast("struct ipsec_sa *", objects[name])
   end
   objects[name] = shm.create(name, ipsec_t)
   return objects[name]
end

function open (name)
   if objects[name] then
      return ffi.cast("struct ipsec_sa *", objects[name])
   end
   objects[name] = shm.open(name, ipsec_t, 'readonly')
   return objects[name]
end

function delete (name)
   local o = objects[name]
   if not o then error("ipsec not found for deletion: " .. name) end
   -- Free shm object
   shm.unmap(o)
   shm.unlink(name)
   -- Free local state
   objects[name] = false
end
