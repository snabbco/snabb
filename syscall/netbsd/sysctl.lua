--types for NetBSD sysctl, incomplete at present

local require = require

local c = require "syscall.netbsd.constants"

-- TODO note might be considered bool, CTLTYPE_BOOL is defined.

-- TODO we should traverse tree and read types instead of predefined values

local types = {
  unspec   = c.CTL.UNSPEC,
  kern     = {c.CTL.KERN, c.KERN}, -- TODO maybe change to preferred form where end node has {c.KERN.OSTYPE, "string"}
  vm       = {c.CTL.VM, c.VM},
  vfs      = c.CTL.VFS,
  net      = c.CTL.NET,
  debug    = c.CTL.DEBUG,
  hw       = {c.CTL.HW, c.HW},
  machdep  = c.CTL.MACHDEP,
  user     = {c.CTL.USER, c.USER},
  ddb      = c.CTL.DDB,
  proc     = c.CTL.PROC,
  vendor   = c.CTL.VENDOR,
  emul     = c.CTL.EMUL,
  security = c.CTL.SECURITY,

  ["kern.ostype"]    = "string",
  ["kern.osrelease"] = "string",
  ["kern.osrevision"]= {c.KERN.OSREV, "int"},
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
  ["kern.pipe"] = {c.KERN.PIPE, c.KERN_PIPE},
  ["kern.pipe.maxkvasz"] = "int",
  ["kern.pipe.maxloankvasz"] = "int",
  ["kern.pipe.maxbigpipes"] = "int",
  ["kern.pipe.nbigpipes"] = "int",
  ["kern.pipe.kvasize"] = "int",
  ["kern.maxphys"] = "int",
  ["kern.sbmax"] = "int",
  ["kern.tkstat"] = {c.KERN.TKSTAT, c.KERN_TKSTAT},
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
  ["hw.drivenames"] = {c.HW.DISKNAMES, "string"},
--["hw.drivestats"] = {c.HW.IOSTATS, "iostat[]"},
  ["hw.machine_arch"] = "string",
  ["hw.alignbytes"] = "int",
  ["hw.cnmagic"] = "string",
  ["hw.physmem64"] = "int64",
  ["hw.usermem64"] = "int64",
  ["hw.ncpuonline"] = "int",

  ["vm.vmmeter"] = {c.VM.METER, "vmtotal"},
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

-- net.*, no constant names
  ["net.local"] = 1,
  ["net.inet"] = 2,
  ["net.implink"] = 3,
  ["net.pup"] = 4,
  ["net.chaos"] = 5,
  ["net.xerox_ns"] = 6,
  ["net.iso"] = 7,
  ["net.emca"] = 8,
  ["net.datakit"] = 9,
  ["net.ccitt"] = 10,
  ["net.ibm_sna"] = 11,
  ["net.decnet"] = 12,
  ["net.dec_dli"] = 13,
  ["net.lat"] = 14,
  ["net.hylink"] = 15,
  ["net.appletalk"] = 16,
  ["net.oroute"] = 17,
  ["net.link_layer"] = 18,
  ["net.xtp"] = 19,
  ["net.coip"] = 20,
  ["net.cnt"] = 21,
  ["net.rtip"] = 22,
  ["net.ipx"] = 23,
  ["net.inet6"] = 24,
  ["net.pip"] = 25,
  ["net.isdn"] = 26,
  ["net.natm"] = 27,
  ["net.arp"] = 28,
  ["net.key"] = 29,
  ["net.ieee80211"] = 30,
  ["net.mlps"] = 31,
  ["net.route"] = 32,
-- inet protocol names CTL_IPPROTO_NAMES
  ["net.inet.ip"] = {0, c.IPCTL},
  ["net.inet.icmp"] = 1,
  ["net.inet.igmp"] = 2,
  ["net.inet.ggp"] = 3,
  ["net.inet.tcp"] = 6,
  ["net.inet.egp"] = 8,
  ["net.inet.pup"] = 12,
  ["net.inet.udp"] = 17,
  ["net.inet.idp"] = 22,
  ["net.inet.ipsec"] = 51,
  ["net.inet.pim"] = 103,

-- ip IPCTL_NAMES
  ["net.inet.ip.forwarding"] = "int",
  ["net.inet.ip.redirect"] = {c.IPCTL.SENDREDIRECTS, "int"},
  ["net.inet.ip.ttl"] = {c.IPCTL.DEFTTL, "int"},
--["net.inet.ip.mtu"] = {c.IPCTL.DEFMTU, "int"},
  ["net.inet.ip.forwsrcrt"] = "int",
  ["net.inet.ip.directed-broadcast"] = {c.IPCTL.DIRECTEDBCAST, "int"},
  ["net.inet.ip.allowsrcrt"] = "int",
  ["net.inet.ip.subnetsarelocal"] = "int",
  ["net.inet.ip.mtudisc"] = "int",
  ["net.inet.ip.anonportmin"] = "int",
  ["net.inet.ip.anonportmax"] = "int",
  ["net.inet.ip.mtudisctimeout"] = "int",
  ["net.inet.ip.maxflows"] = "int",
  ["net.inet.ip.hostzerobroadcast"] = "int",
  ["net.inet.ip.gifttl"] = {c.IPCTL.GIF_TTL, "int"},
  ["net.inet.ip.lowportmin"] = "int",
  ["net.inet.ip.lowportmax"] = "int",
  ["net.inet.ip.maxfragpackets"] = "int",
  ["net.inet.ip.grettl"] = {c.IPCTL.GRE_TTL, "int"},
  ["net.inet.ip.checkinterface"] = "int",
--["net.inet.ip.ifq"], CTLTYPE_NODE
  ["net.inet.ip.random_id"] = {c.IPCTL.RANDOMID, "int"},
  ["net.inet.ip.do_loopback_cksum"] = {c.IPCTL.LOOPBACKCKSUM, "int"},
--["net.inet.ip.stats", CTLTYPE_STRUCT

-- ipv6
-- TODO rest of values
  ["net.inet6.tcp6"] = 6,
  ["net.inet6.udp6"] = 17,
  ["net.inet6.ip6"] = {41, c.IPV6CTL},
  ["net.inet6.ipsec6"] = 51,
  ["net.inet6.icmp6"] = 58,
  ["net.inet6.pim6"] = 103,

  ["net.inet6.ip6.forwarding"] = "int",
  ["net.inet6.ip6.redirect"] = {c.IPV6CTL.SENDREDIRECTS, "int"},
  ["net.inet6.ip6.hlim"] = {c.IPV6CTL.DEFHLIM, "int"},
--["net.inet6.ip6.mtu"] = {c.IPV6CTL.DEFMTU, "int"},
  ["net.inet6.ip6.forwsrcrt"] = "int",
  ["net.inet6.ip6.stats"] = "int",
  ["net.inet6.ip6.mrtproto"] = "int",
  ["net.inet6.ip6.maxfragpackets"] = "int",
  ["net.inet6.ip6.sourcecheck"] = "int",
  ["net.inet6.ip6.sourcecheck_logint"] = "int",
  ["net.inet6.ip6.accept_rtadv"] = "int",
  ["net.inet6.ip6.keepfaith"] = "int",
  ["net.inet6.ip6.log_interval"] = "int",
  ["net.inet6.ip6.hdrnestlimit"] = "int",
  ["net.inet6.ip6.dad_count"] = "int",
  ["net.inet6.ip6.auto_flowlabel"] = "int",
  ["net.inet6.ip6.defmcasthlim"] = "int",
  ["net.inet6.ip6.gifhlim"] = {c.IPV6CTL.GIF_HLIM, "int"},
  ["net.inet6.ip6.kame_version"] = "int",
  ["net.inet6.ip6.use_deprecated"] = "int",
  ["net.inet6.ip6.rr_prune"] = "int",
  ["net.inet6.ip6.v6only"] = "int",
  ["net.inet6.ip6.anonportmin"] = "int",
  ["net.inet6.ip6.anonportmax"] = "int",
  ["net.inet6.ip6.lowportmin"] = "int",
  ["net.inet6.ip6.lowportmax"] = "int",
  ["net.inet6.ip6.maxfrags"] = "int",
--["net.inet6.ip6.ifq"], CTLTYPE_NODE }, \
  ["net.inet6.ip6.rtadv_maxroutes"] = "int",
  ["net.inet6.ip6.rtadv_numroutes"] = "int",

-- these are provided by libc, so we don't get any values from syscall on rump
  ["user.cs_path"] = "string",
  ["user.bc_base_max"] = "int",
  ["user.bc_dim_max"] = "int",
  ["user.bc_scale_max"] = "int",
  ["user.bc_string_max"] = "int",
  ["user.coll_weights_max"] = "int",
  ["user.expr_nest_max"] = "int",
  ["user.line_max"] = "int",
  ["user.re_dup_max"] = "int",
  ["user.posix2_version"] = "int",
  ["user.posix2_c_bind"] = "int",
  ["user.posix2_c_dev"] = "int",
  ["user.posix2_char_term"] = "int",
  ["user.posix2_fort_dev"] = "int",
  ["user.posix2_fort_run"] = "int",
  ["user.posix2_localedef"] = "int",
  ["user.posix2_sw_dev"] = "int",
  ["user.posix2_upe"] = "int",
  ["user.stream_max"] = "int",
  ["user.tzname_max"] = "int",
  ["user.atexit_max"] = "int",
}

return types

