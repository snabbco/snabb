-- error messages
-- we could get these from libc strerror, but aalows eg localisation, and makes things clearer. Only loaded if you use them.

local E = require("syscall.constants").E

local msg = {
  ILSEQ      = "Illegal byte sequence", 
  DOM        = "Domain error", 
  RANGE      = "Result not representable", 

  NOTTY      = "Not a tty", 
  ACCES      = "Permission denied", 
  PERM       = "Operation not permitted", 
  NOENT      = "No such file or directory", 
  SRCH       = "No such process", 
  EXIST      = "File exists", 

  OVERFLOW   = "Value too large for data type", 
  NOSPC      = "No space left on device", 
  NOMEM      = "Out of memory", 

  BUSY       = "Resource busy", 
  INTR       = "Interrupted system call", 
  AGAIN      = "Resource temporarily unavailable", 
  SPIPE      = "Invalid seek", 

  XDEV       = "Cross-device link", 
  ROFS       = "Read-only file system", 
  NOTEMPTY   = "Directory not empty", 

  CONNRESET  = "Connection reset by peer", 
  TIMEDOUT   = "Operation timed out", 
  CONNREFUSED= "Connection refused", 
  HOSTDOWN   = "Host is down", 
  HOSTUNREACH= "Host is unreachable", 
  ADDRINUSE  = "Address in use", 

  PIPE       = "Broken pipe", 
  IO         = "I/O error", 
  NXIO       = "No such device or address", 
  NOTBLK     = "Block device required", 
  NODEV      = "No such device", 
  NOTDIR     = "Not a directory", 
  ISDIR      = "Is a directory", 
  TXTBSY     = "Text file busy", 
  NOEXEC     = "Exec format error", 

  INVAL      = "Invalid argument", 

  ["2BIG"]   = "Argument list too long", 
  LOOP       = "Symbolic link loop", 
  NAMETOOLONG= "Filename too long", 
  NFILE      = "Too many open files in system", 
  MFILE      = "No file descriptors available", 
  BADF       = "Bad file descriptor", 
  CHILD      = "No child process", 
  FAULT      = "Bad address", 
  FBIG       = "File too large", 
  MLINK      = "Too many links", 
  NOLCK      = "No locks available", 

  DEADLK     = "Resource deadlock would occur", 
  NOTRECOVERABLE="State not recoverable", 
  OWNERDEAD  = "Previous owner died", 
  CANCELED   = "Operation canceled", 
  NOSYS      = "Function not implemented", 
  NOMSG      = "No message of desired type", 
  IDRM       = "Identifier removed", 
  NOSTR      = "Device not a stream", 
  NODATA     = "No data available", 
  TIME       = "Device timeout", 
  NOSR       = "Out of streams resources", 
  NOLINK     = "Link has been severed", 
  PROTO      = "Protocol error", 
  BADMSG     = "Bad message", 
  BADFD      = "File descriptor in bad state", 
  NOTSOCK    = "Not a socket", 
  DESTADDRREQ= "Destination address required", 
  MSGSIZE    = "Message too large", 
  PROTOTYPE  = "Protocol wrong type for socket", 
  NOPROTOOPT = "Protocol not available", 
  PROTONOSUPPORT="Protocol not supported", 
  SOCKTNOSUPPORT="Socket type not supported", 
  OPNOTSUPP  = "Not supported", 
  PFNOSUPPORT= "Protocol family not supported", 
  AFNOSUPPORT= "Address family not supported by protocol", 
  ADDRNOTAVAIL="Address not available", 
  NETDOWN    = "Network is down", 
  NETUNREACH = "Network unreachable", 
  NETRESET   = "Connection reset by network", 
  CONNABORTED= "Connection aborted", 
  NOBUFS     = "No buffer space available", 
  ISCONN     = "Socket is connected", 
  NOTCONN    = "Socket not connected", 
  SHUTDOWN   = "Cannot send after socket shutdown", 
  ALREADY    = "Operation already in progress", 
  INPROGRESS = "Operation in progress", 
  STALE      = "Stale file handle", 
  REMOTEIO   = "Remote I/O error", 
  DQUOT      = "Quota exceeded", 
  NOMEDIUM   = "No medium found", 
  MEDIUMTYPE = "Wrong medium type", 
}

local errors = setmetatable({}, {
  __index = function(err, errno) return "No error information (error " .. errno .. ")" end,
  __call = function(err, errno) return err[errno] end,
})

for k, v in pairs(msg) do
  if E[k] then errors[E[k]] = v end
end

return errors

