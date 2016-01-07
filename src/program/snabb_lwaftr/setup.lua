module(..., package.seeall)

local config     = require("core.config")
local Intel82599 = require("apps.intel.intel_app").Intel82599
local lwaftr     = require("apps.lwaftr.lwaftr")
local basic_apps = require("apps.basic.basic_apps")
local pcap       = require("apps.pcap.pcap")
local ipv4_apps  = require("apps.lwaftr.ipv4_apps")
local ipv6_apps  = require("apps.lwaftr.ipv6_apps")

function lwaftr_app(c, conf)
   assert(type(conf) == 'table')

   config.app(c, "reassemblerv4", ipv4_apps.Reassembler,
              { vlan_tagging=conf.vlan_tagging })
   config.app(c, "reassemblerv6", ipv6_apps.Reassembler,
              { vlan_tagging=conf.vlan_tagging })
   config.app(c, 'lwaftr', lwaftr.LwAftr, conf)
   config.app(c, "fragmenterv4", ipv4_apps.Fragmenter,
              { vlan_tagging=conf.vlan_tagging,
                mtu=conf.ipv4_mtu })
   config.app(c, "fragmenterv6", ipv6_apps.Fragmenter,
              { vlan_tagging=conf.vlan_tagging,
                mtu=conf.ipv6_mtu })

   config.link(c, "reassemblerv4.output -> lwaftr.v4")
   config.link(c, "reassemblerv6.output -> lwaftr.v6")
   config.link(c, 'lwaftr.v6 -> fragmenterv6.input')
   config.link(c, 'lwaftr.v4 -> fragmenterv4.input')
end

function link_source(c, v4_in, v6_in)
   config.link(c, v4_in..' -> reassemblerv4.input')
   config.link(c, v6_in..' -> reassemblerv6.input')
end

function link_sink(c, v4_out, v6_out)
   config.link(c, 'fragmenterv4.output -> '..v4_out)
   config.link(c, 'fragmenterv6.output -> '..v6_out)
end

function load_phy(c, conf, v4_nic_name, v4_nic_pci, v6_nic_name, v6_nic_pci)
   lwaftr_app(c, conf)

   config.app(c, v4_nic_name, Intel82599, {
      pciaddr=v4_nic_pci,
      macaddr = ethernet:ntop(conf.aftr_mac_inet_side)})
   config.app(c, v6_nic_name, Intel82599, {
      pciaddr=v6_nic_pci,
      macaddr = ethernet:ntop(conf.aftr_mac_b4_side)})

   link_source(c, v4_nic_name..'.tx', v6_nic_name..'.tx')
   link_sink(c, v4_nic_name..'.rx', v6_nic_name..'.rx')
end

function load_bench(c, conf, v4_pcap, v6_pcap, v4_sink, v6_sink)
   lwaftr_app(c, conf)

   config.app(c, "capturev4", pcap.PcapReader, v4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, v6_pcap)
   config.app(c, "repeaterv4", basic_apps.Repeater)
   config.app(c, "repeaterv6", basic_apps.Repeater)
   config.app(c, v4_sink, basic_apps.Sink)
   config.app(c, v6_sink, basic_apps.Sink)

   config.link(c, "capturev4.output -> repeaterv4.input")
   config.link(c, "capturev6.output -> repeaterv6.input")

   link_source(c, 'repeaterv4.output', 'repeaterv6.output')
   link_sink(c, v4_sink..'.input', v6_sink..'.input')
end

function load_check(c, conf, inv4_pcap, inv6_pcap, outv4_pcap, outv6_pcap)
   lwaftr_app(c, conf)

   config.app(c, "capturev4", pcap.PcapReader, inv4_pcap)
   config.app(c, "capturev6", pcap.PcapReader, inv6_pcap)
   config.app(c, "output_filev4", pcap.PcapWriter, outv4_pcap)
   config.app(c, "output_filev6", pcap.PcapWriter, outv6_pcap)

   link_source(c, 'capturev4.output', 'capturev6.output')
   link_sink(c, 'output_filev4.input', 'output_filev6.input')
end
