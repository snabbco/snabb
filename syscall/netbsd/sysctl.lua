--types for NetBSD sysctl, incomplete at present

local require = require

local c = require "syscall.netbsd.constants"

-- TODO we need to support more levels, and simplify a bit
-- TODO maybe we put these into the table below eg "kern" = c.KERN, "kern.pipe" = c.KERN_PIPE
-- note also some of the node constants do not have names, will just have to put numbers in
local map = {
  [c.CTL.KERN] = c.KERN,
  [c.CTL.HW] = c.HW,
  [c.CTL.VM] = c.VM,
}

local map2 = {
  [c.CTL.KERN] = {
    [c.KERN.PIPE] = c.KERN_PIPE,
    [c.KERN.TKSTAT] = c.KERN_TKSTAT,
  }
}

-- new top level
--[[
  "unspec" = CTL.UNSPEC,
  "kern" = CTL.KERN,
  "vm" = CTL.VM,
  "vfs" = CTL.VFS,
  "net" = CTL.NET,
  "debug" = CTL.DEBUG,
  "hw" = CTL.HW,
  "machdep" = CTL.MACHDEP,
  "user" = CTL.USER,
  "ddb" = CTL.DDB,
  "proc" = CTL.PROC,
  "vendor" = CTL.VENDOR,
  "emul" = CTL.EMUL,
  "security" = CTL.SECURITY,
]]

-- TODO these have no constant names
--[[
{ -- CTL_NET_NAMES
  "[net.local]" = 1,
  "[net.inet]" = 2,
  "[net.implink]" = 3,
  "[net.pup]" = 4,
  "[net.chaos]" = 5,
  "[net.xerox_ns]" = 6,
  "[net.iso]" = 7,
  "[net.emca]" = 8,
  "[net.datakit]" = 9,
  "[net.ccitt]", 10,
  "[net.ibm_sna]" = 11,
  "[net.decnet]" = 12,
  "[net.dec_dli]" = 13,
  "[net.lat]" = 14,
  "[net.hylink]" = 15,
  "[net.appletalk]" = 16,
  "[net.oroute]" = 17,
  "[net.link_layer]" = 18,
  "[net.xtp]" = 19,
  "[net.coip]" = 20,
  "[net.cnt]" = 21,
  "[net.rtip]" = 22,
  "[net.ipx]" = 23,
  "[net.inet6]" = 24,
  "[net.pip]" = 25,
  "[net.isdn]" = 26,
  "[net.natm]" = 27,
  "[net.arp]" = 28,
  "[net.key]" = 29,
  "[net.ieee80211]" = 30,
  "[net.mlps]" = 31,
  "[net.route]" = 32,
}
]]

-- TODO some of the friendly names do not map exactly to the constants, add an alias map.
--[[
local aliases = {
  ["hw.drivenames"] = "hw.disknames",
  ["hw.drivestats"] = "hw.iostats",
  ["vm.vmmeter"] = "vm.meter",
}

-- TODO note some could be considered bool not int eg KERN_FSYNC
local types = {
  ["kern.ostype"]    = "string",
  ["kern.osrelease"] = "string",
  ["kern.osrev"]     = "int",
  ["kern.version"]   = "string",
  ["kern.maxvnodes"] = "int",
  ["kern.maxproc"]   = "int",
  ["kern.maxfiles"]  = "int",
  ["kern.argmax"]    = "int",
  ["kern.securelvl"] = "int",
  ["kern.hostname"]  = "string",
  ["kern.hostid"]    = "int",
  ["kern.clockrate"] = "clockinfo",
-- KERN_VNODE              13      /* struct: vnode structures */
-- KERN_PROC               14      /* struct: process entries */
-- KERN_FILE               15      /* struct: file entries */
-- KERN_PROF               16      /* node: kernel profiling info */
  ["kern.posix1"]    = "int",
  ["kern.ngroups"]   = "int",
  ["kern.job_control"] = "int",
  ["kern.saved_ids"] = "int",
-- KERN_OBOOTTIME          21      /* struct: time kernel was booted */
  ["kern.domainname"] = "string",
  ["kern.maxpartitions"] = "int",
  ["kern.rawpartition"] = "int",
-- KERN_NTPTIME            25      /* struct: extended-precision time */
-- KERN_TIMEX              26      /* struct: ntp timekeeping state */
  ["kern.autonicetime"] = "int",
  ["kern.autoniceval"] = "int",
  ["kern.rtc_offset"] = "int",
  ["kern.root_device"] = "string",
  ["kern.msgbufsize"] = "int",
  ["kern.fsync"] = "int",
  ["kern.synchronized_io"] = "int",
  ["kern.iov_max"] = "int",
-- KERN_MBUF               39      /* node: mbuf parameters */
  ["kern.mapped_files"] = "int",
  ["kern.memlock"] = "int",
  ["kern.memlock_range"] = "int",
  ["kern.memory_protection"] = "int",
  ["kern.login_name_max"] = "int",
  ["kern.logsigexit"] = "int",
-- KERN_PROC2              47      /* struct: process entries */
-- KERN_PROC_ARGS          48      /* struct: process argv/env */
  ["kern.fscale"] = "int",
-- KERN_CP_TIME            51      /* struct: CPU time counters */
-- KERN_MSGBUF             53      /* kernel message buffer */
-- KERN_CONSDEV            54      /* dev_t: console terminal device */
  ["kern.maxptys"] = "int",
  ["kern.pipe.maxkvasz"] = "int",
  ["kern.pipe.maxloankvasz"] = "int",
  ["kern.pipe.maxbigpipes"] = "int",
  ["kern.pipe.nbigpipes"] = "int",
  ["kern.pipe.kvasize"] = "int",
  ["kern.maxphys"] = "int",
  ["kern.sbmax"] = "int",
  ["kern.tkstat.nin"] = "int64",
  ["kern.tkstat.nout"] = "int64",
  ["kern.tkstat.cancc"] = "int64",
  ["kern.tkstat.rawcc"] = "int64",
  ["kern.monotonic_clock"] = "int",
  ["kern.urnd"] = "int",
  ["kern.labelsector"] = "int",
  ["kern.labeloffset"] = "int",
-- KERN_LWP                64      /* struct: lwp entries */
  ["kern.forkfsleep"] = "int",
  ["kern.posix_threads"] = "int",
  ["kern.posix_semaphores"] = "int",
  ["kern.posix_barriers"] = "int",
  ["kern.posix_timers"] = "int",
  ["kern.posix_spin_locks"] = "int",
  ["kern.posix_reader_writer_locks"] = "int",
  ["kern.dump_on_panic"] = "int",
  ["kern.somaxkva"] = "int",
  ["kern.root_partition"] = "int",
-- KERN_DRIVERS            75      /* struct: driver names and majors #s */
-- KERN_BUF                76      /* struct: buffers */
-- KERN_FILE2              77      /* struct: file entries */
-- KERN_VERIEXEC           78      /* node: verified exec */
-- KERN_CP_ID              79      /* struct: cpu id numbers */
  ["kern.hardclock_ticks"] = "int",
-- KERN_ARND               81      /* void *buf, size_t siz random */
-- KERN_SYSVIPC            82      /* node: SysV IPC parameters */
-- KERN_BOOTTIME           83      /* struct: time kernel was booted */
-- KERN_EVCNT              84      /* struct: evcnts */

  ["hw.machine"] = "string",
  ["hw.model"] = "string",
  ["hw.ncpu"] = "int",
  ["hw.byteorder"] = "int",
  ["hw.physmem"] = "int",
  ["hw.usermem"] = "int",
  ["hw.pagesize"] = "int",
  ["hw.disknames"] = "string",
--["hw.iostats"] = "iostat[]"
  ["hw.machine_arch"] = "string",
  ["hw.alignbytes"] = "int",
  ["hw.cnmagic"] = "string",
  ["hw.physmem64"] = "int64",
  ["hw.usermem64"] = "int64",
  ["hw.ncpuonline"] = "int",

  ["vm.meter"] = "vmtotal",
  ["vm.loadavg"] = "loadavg",
--["vm.uvmexp" = "uvmexp",
  ["vm.nkmempages"] = "int",
--["vm.uvmexp2"] = "uvmexp_sysctl",
  ["vm.anonmin"] = "int",
  ["vm.execmin"] = "int",
  ["vm.filemin"] = "int",
  ["vm.maxslp"] = "int",
  ["vm.uspace"] = "int",
  ["vm.anonmax"] = "int",
  ["vm.execmax"] = "int",
  ["vm.filemax"] = "int",

-- ip IPCTL_NAMES
--[[
  ["net.inet.forwarding"] = "int",
  ["net.inet.redirect"] = "int",
  ["net.inet.ttl"] = "int",
  ["net.inet.mtu"] = "int",
  ["net.inet.forwsrcrt"] = "int",
  ["net.inet.directed-broadcast"] = "int",
  ["net.inet.allowsrcrt"] = "int",
  ["net.inet.subnetsarelocal"] = "int",
  ["net.inet.mtudisc"] = "int",
  ["net.inet.anonportmin"] = "int",
  ["net.inet.anonportmax"] = "int",
  ["net.inet.mtudisctimeout"] = "int",
  ["net.inet.maxflows"] = "int",
  ["net.inet.hostzerobroadcast"] = "int",
  ["net.inet.gifttl"] = "int",
  ["net.inet.lowportmin"] = "int",
  ["net.inet.lowportmax"] = "int",
  ["net.inet.maxfragpackets"] = "int",
  ["net.inet.grettl"] = "int",
  ["net.inet.checkinterface"] = "int",
--["net.inet.ifq"], CTLTYPE_NODE
  ["net.inet.random_id"] = "int",
  ["net.inet.do_loopback_cksum"] = "int",
--["net.inet.stats", CTLTYPE_STRUCT
--]]

-- ipv6
--[[
  ["net.inet6.forwarding"] = "int",
  ["net.inet6.redirect"] = "int",
  ["net.inet6.hlim"] = "int",
  ["net.inet6.mtu"] = "int",
  ["net.inet6.forwsrcrt"] = "int",
  ["net.inet6.stats"] = "int",
  ["net.inet6.mrtproto"] = "int",
  ["net.inet6.maxfragpackets"] = "int",
  ["net.inet6.sourcecheck"] = "int",
  ["net.inet6.sourcecheck_logint"] = "int",
  ["net.inet6.accept_rtadv"] = "int",
  ["net.inet6.keepfaith"] = "int",
  ["net.inet6.log_interval"] = "int",
  ["net.inet6.hdrnestlimit"] = "int",
  ["net.inet6.dad_count"] = "int",
  ["net.inet6.auto_flowlabel"] = "int",
  ["net.inet6.defmcasthlim"] = "int",
  ["net.inet6.gifhlim"] = "int",
  ["net.inet6.kame_version"] = "int",
  ["net.inet6.use_deprecated"] = "int",
  ["net.inet6.rr_prune"] = "int",
  ["net.inet6.v6only"] = "int",
  ["net.inet6.anonportmin"] = "int",
  ["net.inet6.anonportmax"] = "int",
  ["net.inet6.lowportmin"] = "int",
  ["net.inet6.lowportmax"] = "int",
  ["net.inet6.maxfrags"] = "int",
--["net.inet6.ifq"], CTLTYPE_NODE }, \
  ["net.inet6.rtadv_maxroutes"] = "int",
  ["net.inet6.rtadv_numroutes"] = "int",
--]]
}

return {types = types, map = map, map2 = map2}

