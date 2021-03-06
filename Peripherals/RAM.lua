--[[
Layout (96 KB)
--------------
0x0000 Meta Data (736 Bytes)
0x02E0 SpriteMap (12 KB)
0x32E0 Flags Data (288 Bytes)
0x3400 MapData (18 KB)
0x7C00 Sound Tracks (13 KB)
0xB000 Compressed Lua Code (20 KB)
0x10000 Persistant Data (2 KB)
0x10800 GPIO (128 Bytes)
0x10880 Reserved (768 Bytes)
0x10B80 Draw State (64 Bytes)
0x10BC0 Reserved (64 Bytes)
0x10C00 Free Space (1 KB)
0x11000 Reserved (4 KB)
0x12000 Label Image (12 KBytes)
0x15000 VRAM (12 KBytes)
0x18000 End of memory (Out of range)

Meta Data (1 KB)
----------------
0x0000 Data Length (6 Bytes)
0x0006 LIKO-12 Header (7 Bytes)
0x000D Color Palette (64 Bytes)
0x004D Disk Version (1 Byte)
0x004E Disk Meta (1 Byte)
0x004F Screen Width (2 Bytes)
0x0051 Screen Hight (2 Bytes)
0x0053 Reserved (1 Byte)
0x0054 SpriteMap Address (4 Bytes)
0x0058 MapData Address (4 Bytes)
0x005C Instruments Data Address (4 Bytes)
0x0060 Tracks Data Address (4 Bytes)
0x0064 Tracks Orders Address (4 Bytes)
0x0068 Compressed Lua Code Address (4 Bytes)
0x006C Author Name (16 Bytes)
0x007C Game Name (16 Bytes)
0x008C SpriteSheet Width (2 Bytes)
0x008E SpriteSheet Height (2 Bytes)
0x0090 Map Width (1 Byte)
0x0091 Map height (1 Byte)
0x0093 Reserved (594 Bytes)

Disk META:
--------------
1. Auto event loop.
2. Activate controllers.
3. Keyboad Only.
4. Mobile Friendly.
5. Static Resolution.
6. Compatibilty Mode.
7. Write Protection.
8. Licensed Under CC0.
]]

local coreg = require("Engine.coreg")

return function(config)
  local ramsize = config.size or 96*1024 --Defaults to 96 KBytes.
  local lastaddr = string.format("0x%X",ramsize-1)
  local lastaddr4 = string.format("0x%X",(ramsize-1)*2) --For peek4 and poke4
  local ram = string.rep("\0",ramsize)
  
  local eHandlers = config.handlers or {} --The ram handlers provided by the engine peripherals.
  local handlers = {} --The active ran handlers system
  
  local devkit = {}
  
  --function to convert a number into a hex string.
  local function tohex(a) return string.format("0x%X",a or 0) end
  
  --Will be removed
  function devkit.addHandler(startAddress, endAddress, handler)
    if type(startAddress) ~= "number" then return error("Start address must be a number, provided: "..type(startAddress)) end
    if type(endAddress) ~= "number" then return error("End address must be a number, provided: "..type(endAddress)) end
    if type(handler) ~= "function" then return error("Handler must be a function, provided: "..type(handler)) end
    
    if (startAddress < 0) or (startAddress > ramsize-1) then return error("Start Address out of range ("..tohex(startAddress)..") Must be [0,"..tohex(ramsize-1).."]") end
    if (endAddress < 0) or (endAddress > ramsize-1) then return error("End Address out of range ("..tohex(endAddress)..") Must be [0,"..tohex(ramsize-1).."]") end
    
    table.insert(handlers,{startAddr = startAddress, endAddr = endAddress, handler = handler})
    table.sort(handlers, function(t1,t2)
      return (t1.startAddr < t2.startAddr)
    end)
  end
  
  --Writes and reads from the RAM string.
  function devkit.defaultHandler(mode,startAddress,...)
    local args = {...}
    if mode == "poke" then
      local address, value = unpack(args)
      ram = ram:sub(0,address) .. string.char(value) .. ram:sub(address+2,-1)
    elseif mode == "poke4" then
      local address4, value = unpack(args)
      local address = math.floor(address4 / 2)
      local char = ram:sub(address+1,address+1)
      local byte = string.byte(char)
      
      if address4 % 2 == 0 then --left nibble
        byte = bit.band(byte,0x0F)
        value = bit.rshift(value,4)
        byte = bit.bor(byte,value)
      else --right nibble
        byte = bit.band(byte,0xF0)
        byte = bit.bor(byte,value)
      end
      
      ram = ram:sub(0,address) .. string.char(byte) .. ram:sub(address+2,-1)
    elseif mode == "peek" then
      local address = args[1]
      return string.byte(ram:sub(address+1,address+1))
    elseif mode == "peek4" then-----------
      local address4 = args[1]
      local address = math.floor(address4 / 2)
      local byte = string.byte(ram:sub(address+1,address+1))
      
      if address4 % 2 == 0 then --left nibble
        byte = bit.lshift(byte,4)
      else --right nibble
        byte = bit.band(byte,0x0F)
      end
      
      return byte
    elseif mode == "memcpy" then
      local from, to, len = unpack(args)
      local str = ram:sub(from+1,from+len)
      ram = ram:sub(0,to) .. str .. ram:sub(to+len+1,-1)
    elseif mode == "memset" then
      local address, value = unpack(args)
      local len = value:len()
      ram = ram:sub(0,address) .. value .. ram:sub(address+len+1,-1)
    elseif mode == "memget" then
      local address, len = unpack(args)
      return ram:sub(address+1,address+len)
    end
  end
  
  eHandlers["memory"] = devkit.defaultHandler
  
  local api = {}
  
  local indirect = { --The functions that must be called via coroutine.yield
    "poke", "poke4", "peek", "peek4", "memset", "memget", "memcpy"
  }
  
  local sectionEnd = -1
  function api._newSection(size,hand)
    local hand = hand or "memory"
    
    if type(size) ~= "number" then return false, "Section size must be a number, provided: "..type(size) end
    if type(hand) ~= "string" and type(hand) ~= "function" then return false, "Section handler can be a string or a function, provided: "..type(hand) end
    
    size = math.floor(size)
    
    if sectionEnd + size > ramsize-1 then return false, "No enough unallocated memory left." end
    local startAddr = sectionEnd +1
    local endAddr = sectionEnd + size
    sectionEnd = sectionEnd+size
    
    if type(hand) == "string" then
      if not eHandlers[hand] then return false, "Engine handler '"..hand.."' not found." end
      hand = eHandlers[hand]
    else
      print("Custom Handler #"..(#handlers + 1))
    end
    
    devkit.addHandler(startAddr,endAddr,hand)
    return true, #handlers
  end
  
  function api._resizeSection(id,size)
    if type(id) ~= "number" then return false, "Section ID must be a number, provided: "..type(id) end
    if type(size) ~= "number" then return false, "Section size must be a number, provided: "..type(size) end
    
    id, size = math.floor(id), math.floor(size)
    
    if (id < 1) or (id > #handlers) then return false, "Section ID is out of range ("..id..") [1,"..#handlers.."]" end
    if size < 0 then return false, "Section size can't be a negative number ("..size..")" end
    
    local hand = handlers[id]
    if hand.startAddr+size >= ramsize then return false, "Section size is too big" end
    
    hand.endAddr = hand.startAddr + size -1
    local endAddr = hand.endAddr
    
    for i=id+1,#handlers do
      local h=handlers[id]
      if h.startAddr <= endAddr then
        h.startAddr = endAddr+1
        
        if h.endAddr < h.startAddr-1 then
          h.endAddr = h.startAddr-1
        end
      else
        break
      end
    end
    
    return true
  end
  
  function api._removeSection()
    if #handlers < 1 then return false, "There are no RAM sections to remove" end
    
    sectionEnd = sectionEnd - (handlers[#handlers].endAddr - handlers[#handlers].startAddr +1) --Add the space back into the unallocated one.
    
    handlers[#handlers] = nil
    
    return true
  end
  
  function api._setHandler(id,hand)
    if type(id) ~= "number" then return false, "Section ID must be a number, provided: "..type(id) end
    local id,hand = math.floor(id), hand or "memory"
    
    if (id < 1) or (id > #handlers) then return false, "Section ID is out of range ("..id..") [1,"..#handlers.."]" end
    if type(hand) ~= "string" and type(hand) ~= "function" then return false, "Section handler can be a string or a function, provided: "..type(hand) end
    
    if type(hand) == "string" then
      if not eHandlers[hand] then return false, "Engine handler '"..hand.."' not found." end
      hand = eHandlers[hand]
    end
    
    handlers[id].handler = hand
    
    return true
  end
  
  function api._getSections()
    local list = {}
    for k,h in pairs(handlers) do
      list[k] = {}
      for k1,v1 in pairs(h) do
        list[k][k1] = v1
      end
    end
    return true, list
  end
  
  function api._getRAMSize()
    return true, ramsize
  end
  
  function api._getUnallocatedSpace()
    return true, ramsize-sectionEnd+1
  end
  
  function api.poke4(...)
    coreg:subCoroutine(devkit.poke4)
    return true, ...
  end
  
  function api.poke(...)
    coreg:subCoroutine(devkit.poke)
    return true, ...
  end
  
  function api.peek4(...)
    coreg:subCoroutine(devkit.peek4)
    return true, ...
  end
  
  function api.peek(...)
    coreg:subCoroutine(devkit.peek)
    return true, ...
  end
  
  function api.memget(...)
    coreg:subCoroutine(devkit.memget)
    return true, ...
  end
  
  function api.memset(...)
    coreg:subCoroutine(devkit.memset)
    return true, ...
  end
  
  function api.memcpy(...)
    coreg:subCoroutine(devkit.memcpy)
    return true, ...
  end
  
  function devkit.poke4(_,address,value)
    if type(address) ~= "number" then return false, "Address must be a number, provided: "..type(address) end
    if type(value) ~= "number" then return false, "Value must be a number, provided: "..type(value) end
    address, value = math.floor(address), math.floor(value)
    if address < 0 or address > (ramsize-1)*2 then return false, "Address out of range ("..tohex(address*2).."), must be in range [0x0,"..lastaddr4.."]" end
    if value < 0 or value > 15 then return false, "Value out of range ("..value..") must be in range [0,15]" end
    
    for k,h in ipairs(handlers) do
      if address <= h.endAddr*2+1 then
        h.handler("poke4",h.startAddr*2,address,value)
        return true --It ran successfully.
      end
    end
  end
  
  function devkit.poke(_,address,value)
    if type(address) ~= "number" then return false, "Address must be a number, provided: "..type(address) end
    if type(value) ~= "number" then return false, "Value must be a number, provided: "..type(value) end
    address, value = math.floor(address), math.floor(value)
    if address < 0 or address > ramsize-1 then return false, "Address out of range ("..tohex(address).."), must be in range [0x0,"..lastaddr.."]" end
    if value < 0 or value > 255 then return false, "Value out of range ("..value..") must be in range [0,255]" end
    
    for k,h in ipairs(handlers) do
      if address <= h.endAddr then
        h.handler("poke",h.startAddr,address,value)
        return true --It ran successfully.
      end
    end
  end
  
  function devkit.peek4(_,address)
    if type(address) ~= "number" then return false, "Address must be a number, provided: "..type(address) end
    address = math.floor(address)
    if address < 0 or address > (ramsize-1)*2 then return false, "Address out of range ("..tohex(address*2).."), must be in range [0x0,"..lastaddr4.."]" end
    
    for k,h in ipairs(handlers) do
      if address <= h.endAddr*2+1 then
        local v = h.handler("peek4",h.startAddr*2,address)
        return true, v --It ran successfully
      end
    end
    
    return true, 0 --No handler is found
  end
  
  function devkit.peek(_,address)
    if type(address) ~= "number" then return false, "Address must be a number, provided: "..type(address) end
    address = math.floor(address)
    if address < 0 or address > ramsize-1 then return false, "Address out of range ("..tohex(address).."), must be in range [0x0,"..lastaddr.."]" end
    
    for k,h in ipairs(handlers) do
      if address <= h.endAddr then
        local v = h.handler("peek",h.startAddr,address)
        return true, v --It ran successfully
      end
    end
    
    return true, 0 --No handler is found
  end
  
  function devkit.memget(_,address,length)
    if type(address) ~= "number" then return false, "Address must be a number, provided: "..type(address) end
    if type(length) ~= "number" then return false, "Length must be a number, provided: "..type(length) end
    address, length = math.floor(address), math.floor(length)
    if address < 0 or address > ramsize-1 then return false, "Address out of range ("..tohex(address).."), must be in range [0x0,"..lastaddr.."]" end
    if length <= 0 then return false, "Length must be bigger than 0" end
    if address+length > ramsize then return false, "Length out of range ("..length..")" end
    local endAddress = address+length-1
    
    local str = ""
    for k,h in ipairs(handlers) do
      if endAddress >= h.startAddr then
        if address <= h.endAddr then
          local sa, ea = address, endAddress
          if sa < h.startAddr then sa = h.startAddr end
          if ea > h.endAddr then ea = h.endAddr end
          local data = h.handler("memget",h.startAddr,sa,ea-sa+1)
          str = str .. data
        end
      end
    end
    
    return true, str
  end
  
  function devkit.memset(_,address,data)
    if type(address) ~= "number" then return false, "Address must be a number, provided: "..type(address) end
    if type(data) ~= "string" then return false, "Data must be a string, provided: "..type(data) end
    address = math.floor(address)
    if address < 0 or address > ramsize-1 then return false, "Address out of range ("..tohex(address).."), must be in range [0x0,"..lastaddr.."]" end
    local length = data:len()
    if length == 0 then return false, "Cannot set empty string" end
    if address+length > ramsize then return false, "Data too long to fit in the memory ("..length.." character)" end
    local endAddress = address+length-1
    
    for k,h in ipairs(handlers) do
      if endAddress >= h.startAddr then
        if address <= h.endAddr then
          local sa, ea, d = address, endAddress, data
          if sa < h.startAddr then sa = h.startAddr end
          if ea > h.endAddr then ea = h.endAddr end
          d = data:sub(sa-address+1,ea-address+1)
          h.handler("memset",h.startAddr,sa,d)
        end
      end
    end
    
    return true
  end
  
  function devkit.memcpy(_,from_address,to_address,length)
    if type(from_address) ~= "number" then return false, "Source Address must be a number, provided: "..type(from_address) end
    if type(to_address) ~= "number" then return false, "Destination Address must be a number, provided: "..type(to_address) end
    if type(length) ~= "number" then return false,"Length must be a number, provided: "..type(length) end
    from_address, to_address, length = math.floor(from_address), math.floor(to_address), math.floor(length)
    if from_address < 0 or from_address > ramsize-1 then return false, "Source Address out of range ("..tohex(from_address).."), must be in range [0x0,"..tohex(ramsize-2).."]" end
    if to_address < 0 or to_address > ramsize then return false, "Destination Address out of range ("..tohex(to_address).."), must be in range [0x0,"..lastaddr.."]" end
    if length <= 0 then return false, "Length should be bigger than 0" end
    if from_address+length > ramsize then return false, "Length out of range ("..length..")" end
    if to_address+length > ramsize then length = ramsize-to_address end
    local from_end = from_address+length-1
    local to_end = to_address+length-1
    
    for k1,h1 in ipairs(handlers) do
      if from_end >= h1.startAddr and from_address <= h1.endAddr then
        local sa1, ea1 = from_address, from_end
        if sa1 < h1.startAddr then sa1 = h1.startAddr end
        if ea1 > h1.endAddr then ea1 = h1.endAddr end
        local to_address = to_address + (sa1 - from_address)
        local to_end = to_end + (ea1 - from_end)
        for k2,h2 in ipairs(handlers) do
          if to_end >= h2.startAddr and to_address <= h2.endAddr then
            local sa2, ea2 = to_address, to_end
            if sa2 < h2.startAddr then sa2 = h2.startAddr end
            if ea2 > h2.endAddr then ea2 = h2.endAddr end
            
            local sa1 = sa1 + (sa2 - to_address)
            local ea1 = sa1 + (ea2 - to_end)
            
            if h1.handler == h2.handler then --Direct Copy
              h1.handler("memcpy",h1.startAddr,sa1,sa2,ea2-sa2+1)
            else --InDirect Copy
              local d = h1.handler("memget",h1.startAddr,sa1,ea2-sa2+1)
              h2.handler("memset",h2.startAddr,sa2,d)
            end
          end
        end
      end
    end
    
    return true
  end
  
  devkit.ramsize = ramsize
  setmetatable(devkit,{
    __index = function(t,k)
      if k == "ram" then return ram end
    end
  })
  devkit.tohex = tohex
  devkit.layout = layout
  devkit.handlers = handlers
  devkit.api = api
  
  return api, devkit, indirect
end