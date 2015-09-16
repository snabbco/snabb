module(..., package.seeall)

local ethernet = require("lib.protocol.ethernet")
local ipv4 = require("lib.protocol.ipv4")
local ipv6 = require("lib.protocol.ipv6")

local bt = require("apps.lwaftr.binding_table")

policies = {
   DROP = 1,
   ALLOW = 2,
   DISCARD_PLUS_ICMP = 3,
   DISCARD_PLUS_ICMPv6 = 4
}

local aftrconf

-- TODO: rewrite this after netconf integration
local function read_conf(conf_file)
  local input = io.open(conf_file)
  local conf_vars = input:read('*a')
  local conf_prolog = "function _conff(policies, ipv4, ipv6, ethernet, bt)\n return {"
  local conf_epilog = "   }\nend\nreturn _conff\n"
  local full_config = conf_prolog .. conf_vars .. conf_epilog
  local conf = assert(loadstring(full_config))()
  return conf(policies, ipv4, ipv6, ethernet, bt)
end

function get_aftrconf(conf_file)
   if not aftrconf then
      aftrconf = read_conf(conf_file)
   end
   return aftrconf
end
