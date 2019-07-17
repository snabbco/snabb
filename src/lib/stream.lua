-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

-- An API-compatible replacement and extension for Lua's stdio-based
-- streams.

module(..., package.seeall)

local buffer = require('lib.buffer')
local bit = require('bit')
local ffi = require('ffi')

local Stream = {}
local Stream_mt = {__index = Stream}

local DEFAULT_BUFFER_SIZE = 1024

function open(io, readable, writable, buffer_size)
   local ret = setmetatable(
      {io=io, line_buffering=false, random_access=false},
      Stream_mt)
   if readable ~= false then 
      ret.rx = buffer.new(buffer_size or DEFAULT_BUFFER_SIZE)
   end
   if writable ~= false then 
      ret.tx = buffer.new(buffer_size or DEFAULT_BUFFER_SIZE)
   end
   if io.seek and io:seek('cur', 0) then ret.random_access = true end
   return ret
end

function is_stream(x)
   return type(x) == 'table' and getmetatable(x) == Stream_mt
end

function Stream:nonblock() self.io:nonblock() end
function Stream:block() self.io:block() end

function Stream:fill(buf, count)
   if self.random_access then self:flush_output() end
   while true do
      local did_read = self.io:read(buf, count)
      if did_read then return did_read end
      self.io:wait_for_readable()
   end
end

function Stream:fill_rx_buffer()
   assert(self.rx:is_empty())
   self.rx:reset()
   local did_read = self:fill(self.rx.buf, self.rx.size)
   -- Note that did_read may be 0 in case of EOF.
   self.rx:advance_write(did_read)
   return did_read
end

function Stream:flush_input()
   if self.random_access and self.rx then
      local buffered = self.rx:read_avail()
      if buffered ~= 0 then
         assert(self.io:seek('cur', -buffered))
         self.rx:reset()
      end
   end
end

function Stream:flush_some_output()
   assert(not self.tx:is_empty())
   local buf, count = self.tx:peek()
   local did_write = self.io:write(buf, count)
   if did_write then
      self.tx:advance_read(did_write)
      if self.tx:is_empty() then self.tx:reset() end
   else
      self.io:wait_for_writable()
      return self:flush_some_output()
   end
end

function Stream:flush_output()
   if not self.tx then return end
   if self.tx:is_empty() then return end
   self:flush_some_output()
   if not self.tx:is_empty() then return self:flush_output() end
end

Stream.flush = Stream.flush_output

-- Read up to COUNT bytes into BUF.  Return number of bytes read.  Will
-- block until at least one byte is ready, or until EOF, in which case
-- the return value is 0.
function Stream:read_some_bytes(buf, count)
   buf = ffi.cast('uint8_t*', buf)
   if self.rx:is_empty() then
      -- If the target buffer is as large or larger than the read
      -- buffer, read into the target buffer directly -- that way we
      -- probably reduce the number of read calls.
      if count >= self.rx.size then return self:fill(buf, count) end
      -- Otherwise, fill the read buffer.
      self:fill_rx_buffer()
   end
   -- count may be 0 in case of EOF.
   count = math.min(count, self.rx:read_avail())
   self.rx:read(buf, count)
   return count
end

-- Read COUNT bytes from the stream into BUF, blocking until more bytes
-- are available.  Return number of bytes read, which may be less than
-- COUNT if the stream reaches EOF beforehand.
function Stream:read_bytes(buf, count)
   buf = ffi.cast('uint8_t*', buf)
   -- Unrolled fast-path to avoid nested loops.
   local did_read = self:read_some_bytes(buf, count)
   if did_read == count then return count end
   if did_read == 0 then return 0 end
   local offset = did_read
   while offset < count do
      local did_read = self:read_some_bytes(buf + offset, count - offset)
      if did_read == 0 then break end
      offset = offset + did_read
   end
   return offset
end

-- Read COUNT bytes into BUF, blocking until COUNT bytes are available.
-- If EOF is reached before COUNT bytes are read, signal an error.
function Stream:read_bytes_or_error(buf, count)
   if self:read_bytes(buf, count) ~= count then
      error("early EOF while reading from stream")
   end
end

function Stream:read_all_bytes()
   local head, count, block_size = nil, 0, 1024
   while true do
      local buf = ffi.new('uint8_t[?]', count + block_size)
      if head then ffi.copy(buf, head, count) end
      local did_read = self:read_bytes(buf + count, block_size)
      count = count + did_read
      if did_read < block_size then return buf, count end
      head, block_size = buf, block_size * 2
   end
end

function Stream:read_struct(buf, type)
   if buf == nil then buf = type() end
   self:read_bytes_or_error(buf, ffi.sizeof(type))
   return buf
end

local array_types = {}
local function get_array_type(t)
   local at = array_types[t]
   if not at then
      at = ffi.typeof('$[?]', t)
      array_types[t] = at
   end
   return at
end

function Stream:read_array(buf, type, count)
   if buf == nil then buf = get_array_type(type)(count) end
   self:read_bytes_or_error(buf, ffi.sizeof(type) * count)
   return buf
end

function Stream:read_scalar(buf, type)
   return self:read_array(buf, type, 1)[0]
end

function Stream:peek_byte()
   if self.rx:is_empty() then
      -- Return nil on EOF.
      if self:fill_rx_buffer() == 0 then return nil end
   end
   return self.rx.buf[self.rx:read_pos()]
end

function Stream:peek_char()
   local byte = self:peek_byte()
   if byte == nil then return nil end
   return string.char(byte)
end

function Stream:read_byte()
   local byte = self:peek_byte()
   if byte ~= nil then self.rx:advance_read(1) end
   return byte
end

function Stream:read_char()
   local byte = self:read_byte()
   if byte ~= nil then return string.char(byte) end
end

-- Read up to COUNT characters from a stream and return them as a
-- string.  Blocks until at least one character is available, or the
-- stream reaches EOF, in which case return nil instead.  If COUNT is
-- not given, it defaults to the current read buffer size.
function Stream:read_some_chars(count)
   if count == nil then count = self.rx.size end
   if self.rx:is_empty() then
      if self:fill_rx_buffer() == 0 then return nil end
   end
   local buf, avail = self.rx:peek()
   count = math.min(count, avail)
   local ret = ffi.string(buf, count)
   self.rx:advance_read(count)
   return ret
end

-- Unlike read_bytes, always reads COUNT bytes.
function Stream:read_chars(count)
   local buf = ffi.new('uint8_t[?]', count)
   self:read_bytes_or_error(buf, count)
   return ffi.string(buf, count)
end

function Stream:read_all_chars()
   return ffi.string(self:read_all_bytes())
end

function Stream:write_bytes(buf, count)
   if self.tx:read_avail() == 0 then self:flush_input() end
   buf = ffi.cast('uint8_t*', buf)
   if count >= self.tx.size then
      -- Write directly.
      self:flush_output()
      local did_write = self.io:write(buf, count)
      if did_write then
         buf, count = buf + did_write, count - did_write
      else
         self.io:wait_for_writable()
      end
   else
      -- Write via buffer.
      local to_put = math.min(self.tx:write_avail(), count)
      self.tx:write(buf, to_put)
      buf, count = buf + to_put, count - to_put
      if self.tx:is_full() then self:flush_some_output() end
   end
   if count > 0 then return self:write_bytes(buf, count) end
end

function Stream:write_chars(str)
   assert(type(str) == 'string', 'argument not a string')
   local needs_flush = false
   if self.line_buffering and str:match('\n') then needs_flush = true end
   self:write_bytes(str, #str)
   if needs_flush then self:flush_output() end
end

function Stream:write_struct(type, ptr)
   self:write_bytes(ptr, ffi.sizeof(type))
end

function Stream:write_array(type, ptr, count)
   self:write_bytes(ptr, ffi.sizeof(type) * count)
end

function Stream:write_scalar(type, value)
   local ptr = get_array_type(type)(1)
   ptr[0] = value
   assert(ptr[0] == value, "value out of range")
   self:write_array(type, ptr, 1)
end

function Stream:close()
   self:flush_output(); self.rx, self.tx = nil, nil
   self.io:close(); self.io = nil
end

function Stream:lines(...)
   -- Returns an iterator function that, each time it is called, reads
   -- the file according to the given formats.
   local formats = { ... }
   if #formats == 0 then
      return function() return self:read_line('discard') end -- Fast path.
   end
   return function() return self:read(unpack(formats)) end
end

function Stream:read_number()
   error('unimplemented')
end

function Stream:read_line(eol_style) -- 'discard' or 'keep'
   local head = {}
   local add_lf = assert(({discard=0, keep=1})[eol_style or 'discard'])
   while true do
      if self.rx:is_empty() then
         if self:fill_rx_buffer() == 0 then
            -- EOF.
            if #head == 0 then return nil end
            return table.concat(head)
         end
      end
      local buf, avail = self.rx:peek()
      local lf = string.byte("\n")
      for i=0, avail-1 do
         if buf[i] == lf then
            local tail = ffi.string(buf, i + add_lf)
            self.rx:advance_read(i+1)
            if #head == 0 then return tail end
            table.insert(head, tail)
            return table.concat(head)
         end
      end
      local tail = ffi.string(buf, avail)
      self.rx:advance_read(avail)
      table.insert(head, tail)
   end
end

local function read1(stream, format)
   if format == '*n' then
      -- "*n": reads a number; this is the only format that returns a
      -- number instead of a string.
      return stream:read_number()
   elseif format == '*a' then
      -- "*a": reads the whole file, starting at the current
      -- position. On end of file, it returns the empty string.
      return stream:read_all_chars()
   elseif format == '*l' then
      -- "*l": reads the next line (skipping the end of line), returning
      -- nil on end of file.
      return stream:read_line('discard')
   elseif format == '*L' then
      -- "*L": reads the next line keeping the end of line (if present),
      -- returning nil on end of file.  (Lua 5.2, present in LuaJIT.)
      return stream:read_line('keep')
   else
      -- /number/: reads a string with up to this number of characters,
      -- returning nil on end of file.
      assert(type(format) == 'number', 'bad format')
      local number = format
      if number == 0 then
         -- If number is zero, it reads nothing and returns an empty
         -- string, or nil on end of file.
         if not stream.rx.buf:is_empty() then return '' end
         if stream:fill_rx_buffer() == 0 then return nil end -- EOF.
         return ''
      end
      assert(number > 0 and number == math.floor(number))
      local buf = ffi.new('char[?]', number)
      -- The Lua read() method is based on fread() which only returns a
      -- short read on EOF or error, therefore we use read_bytes.
      local did_read = stream:read_bytes(buf, number)
      return ffi.string(buf, did_read)
   end
end

-- Lua 5.1's file:read() method.
function Stream:read(...)
   -- Reads the file file, according to the given formats, which specify
   -- what to read.  For each format, the function returns a string (or
   -- a number) with the characters read, or nil if it cannot read data
   -- with the specified format.  When called without formats, it uses a
   -- default format that reads the entire next line.
   assert(self.rx, "expected a readable stream")
   local args = { ... }
   if #args == 0 then return self:read_line('discard') end -- Default format.
   if #args == 1 then return read1(self, args[1]) end -- Fast path.
   local res = {}
   for _, format in ipairs(args) do table.insert(res, read1(self, format)) end
   return unpack(res)
end

function Stream:seek(whence, offset)
   -- Sets and gets the file position, measured from the beginning of
   -- the file, to the position given by offset plus a base specified by
   -- the string whence, as follows:
   if not self.random_access then return nil, 'stream is not seekable' end
   if whence == nil then whence = 'cur' end
   if offset == nil then offset = 0 end
   if whence == 'cur' and offset == 0 then
      -- Just a position query.
      local ret, err = self.io:seek('cur', 0)
      if ret == nil then return ret, err end
      if self.tx and self.tx:read_avail() ~= 0 then
         return ret + self.tx:read_avail()
      end
      if self.rx and self.rx:read_avail() ~= 0 then
         return ret - self.rx:read_avail()
      end
      return ret
   end
   self:flush_input(); self:flush_output()
   return self.io:seek(whence, offset)
end

local function transfer_buffered_bytes(old, new)
   while old:read_avail() > 0 do
      local buf, count = old:peek()
      new:write(buf, count)
      old:advance_read(count)
   end
end

function Stream:setvbuf(mode, size)
   -- Sets the buffering mode for an output file.
   if mode == 'no' then self.line_buffering, size = false, 1
   elseif mode == 'line' then self.line_buffering = true
   elseif mode == 'full' then self.line_buffering = false
   else error('bad mode', mode) end

   if size == nil then size = DEFAULT_BUFFER_SIZE end
   if self.rx and self.rx.size ~= size then
      if self.rx:read_avail() > size then
         error('existing buffered input is too much for new buffer size')
      end
      local new_rx = buffer.new(size)
      transfer_buffered_bytes(self.rx, new_rx)
      self.rx = new_rx
   end
   if self.tx and self.tx.size ~= size then
      -- Note >= rather than > as we never leave tx buffers full.
      while self.tx:read_avail() >= size do self:flush_some_output() end
      local new_tx = buffer.new(size)
      transfer_buffered_bytes(self.tx, new_tx)
      self.tx = new_tx
   end
end

local function write1(stream, arg)
   if type(arg) == 'number' then arg = tostring(arg) end
   stream:write_chars(arg)
end

function Stream:write(...)
   -- Writes the value of each of its arguments to the file. The
   -- arguments must be strings or numbers. To write other values, use
   -- tostring or string.format before write.
   for _, arg in ipairs({ ... }) do write1(self, arg) end
end

-- The result may be nil.
function Stream:filename() return self.io.filename end

function selftest()
   print('selftest: lib.stream')

   local rd_io, wr_io = {}, {}
   local rd, wr = open(rd_io, true, false), open(wr_io, false, true)

   function rd_io:close() end
   function rd_io:read() return 0 end
   function wr_io:write(buf, count)
      rd.rx:write(buf, count)
      return count
   end
   function wr_io:close() end

   local message = "hello, world\n"
   wr:setvbuf('line')
   wr:write(message)
   local message2 = rd:read_some_chars()
   assert(message == message2)
   assert(rd:read_some_chars() == nil)

   rd:close(); wr:close()

   print('selftest: ok')
end
