module(..., package.seeall)
local app = require("core.app")
local pcap = require("apps.pcap.pcap")


function selftest ()
   print("Keyed IPv6 tunnel selftest")
   local ok = true

   local input_file = "apps/keyed_ipv6_tunnel/selftest.cap.input"
   local output_file = "apps/keyed_ipv6_tunnel/selftest.cap.output"
   local tunnel_config = {
      local_address = "00::2:1",
      remote_address = "00::2:1",
      local_cookie = "12345678",
      remote_cookie = "12345678",
      default_gateway_MAC = "a1:b2:c3:d4:e5:f6"
   } -- should be symmetric for local "loop-back" test

   local c = config.new()
   config.app(c, "source", pcap.PcapReader, input_file)
   config.app(c, "tunnel", 'apps.keyed_ipv6_tunnel.tunnel', tunnel_config)
   config.app(c, "sink", pcap.PcapWriter, output_file)
   config.link(c, "source.output -> tunnel.decapsulated")
   config.link(c, "tunnel.encapsulated -> tunnel.encapsulated")
   config.link(c, "tunnel.decapsulated -> sink.input")
   app.configure(c)

   app.main({duration = 0.25}) -- should be long enough...
   -- Check results
   if io.open(input_file):read('*a') ~=
      io.open(output_file):read('*a')
   then
      print ('bad compare')
      ok = false
   end

   app.configure (config.new())

   local c = config.new()
   config.app(c, "source", 'apps.basic.source')
   config.app(c, "tunnel", 'apps.keyed_ipv6_tunnel.tunnel', tunnel_config)
   config.app(c, "sink", 'apps.basic.sink')
   config.link(c, "source.output -> tunnel.decapsulated")
   config.link(c, "tunnel.encapsulated -> tunnel.encapsulated")
   config.link(c, "tunnel.decapsulated -> sink.input")
   app.configure(c)

   print("run simple one second benchmark ...")
   app.main{duration = 1, report={showlinks=true}}

   if not ok then
      print("selftest failed")
      os.exit(1)
   end
   print("selftest passed")

end
