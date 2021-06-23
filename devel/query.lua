-- Query is a script useful for finding and reading values of data structure fields. Purposes will likely be exclusive to writing lua script code.
-- Written by Josh Cooper(cppcooper) on 2017-12-21, last modified: 2021-06-13
-- Version: 3.1.2
--luacheck:skip-entirely
local utils=require('utils')
local validArgs = utils.invert({
 'help',

 'unit',
 'item',
 'tile',
 'table',
 'getfield',

 'search',
 'findvalue',
 'maxdepth',
 'maxlength',
 'excludetype',
 'excludekind',

 'noblacklist',
 'dumb',

 'showpaths',
 'setvalue',
 'oneline',
 '1',
 'disableprint',
 'debug',
 'debugdata'
})
local args = utils.processArgs({...}, validArgs)
local selection = nil
local path_info = nil
local path_info_pattern = nil
local new_value = nil
local find_value = nil
local maxdepth = nil
local cur_depth = -1
local tilex = nil
local tiley = nil
local bool_flags = {}

local help = [====[

devel/query
===========
Query is a script useful for finding and reading values of data structure
fields. Purposes will likely be exclusive to writing lua script code,
possibly C++.

This script takes your data selection eg.{table,unit,item,tile} then recursively
iterates through it outputting names and values of what it finds.

As it iterates you can have it do other things, like search for a specific
structure pattern (see lua patterns) or set the value of fields matching the
selection and any search pattern specified.

If the script is taking too long to finish, or if it can't finish you should run
``dfhack-run kill-lua`` from a terminal.

Examples::

  devel/query -unit -getfield id
  devel/query -unit -search STRENGTH
  devel/query -unit -search physical_attrs -maxdepth 2
  devel/query -tile -search dig
  devel/query -tile -search "occup.*carv"
  devel/query -table df -maxdepth 2
  devel/query -table df -maxdepth 2 -excludekind s -excludetype fsu -oneline
  devel/query -table df.profession -findvalue FISH
  devel/query -table df.global.ui.main -maxdepth 0
  devel/query -table df.global.ui.main -maxdepth 0 -oneline
  devel/query -table df.global.ui.main -maxdepth 0 -1

**Selection options:**

``-unit``:              Selects the highlighted unit

``-item``:              Selects the highlighted item.

``-tile``:              Selects the highlighted tile's block and then attempts
                        to find the tile, and perform your queries on it.

``-table <value>``:     Selects the specified table (ie. 'value').

                        Must use dot notation to denote sub-tables.
                        (eg. ``-table df.global.world``)

``-getfield <value>``:  Gets the specified field from the selection.

                        Must use in conjunction with one of the above selection
                        options. Must use dot notation to denote sub-fields.

**Query options:**

``-search <value>``:       Searches the selection for field names with
                           substrings matching the specified value.

``-findvalue <value>``:    Searches the selection for field values matching the
                           specified value.

``-maxdepth <value>``:     Limits the field recursion depth (default: 7)

``-maxlength <value>``:    Limits the table sizes that will be walked
                           (default: 257)

``-excludetype [a|bfnstu0]``:  Excludes data types: All | Boolean, Function,
                               Number, String, Table, Userdata, nil

``-excludekind [a|bces]``:     Excludes data types: All | Bit-fields,
                               Class-type, Enum-type, Struct-type

``-noblacklist``:   Disables blacklist filtering.

``-dumb``:          Disables intelligent checking for recursive data
                    structures(loops) and increases the -maxdepth to 25 if a
                    value is not already present

**Command options:**

``-showpaths``:        Displays the full path of a field instead of indenting.

``-setvalue <value>``: Attempts to set the values of any printed fields.
                       Supported types: boolean,

``-oneline``:          Reduces output to one line, except with ``-debugdata``

``-1``:                Reduces output to one line, except with ``-debugdata``

``-disableprint``:     Disables printing. Might be useful if you are debugging
                       this script. Or to see if a query will crash (faster) but
                       not sure what else you could use it for.
                       
``-debug <value>``:    Enables debug log lines equal to or less than the value
                       provided.

``-debugdata``:        Enables debugging data. Prints type information under
                       each field.

``-help``:             Prints this help information.

]====]



--[[ Test cases:
    These sections just have to do with when I made the tests and what their purpose at that time was.
    [safety] make sure the query doesn't crash itself or dfhack
        1. devel/query -maxdepth 3 -table df
        2. devel/query -dumb -table dfhack -search gui
        3. devel/query -dumb -table df
        4. devel/query -dumb -unit
    [validity] make sure the query output is not malformed, and does what is expected
        1. devel/query -dumb -table dfhack
        2. devel/query -dumb -table df -search job_skill
        3. devel/query -dumb -table df -getfield job_skill
]]

--Section: core logic
function query(table, name, search_term, path, bprinted_parent)
    --[[
    * print info about t
    * increment depth
    * check depth
    * recurse structure
    * decrement depth
    ]]--
    if bprinted_parent == nil then
        bprinted_parent = false
    end
    setValue(path, name, table, new_value)
    local bprinted = printField(path, name, table, bprinted_parent)
    --print("table/field printed")
    cur_depth = cur_depth + 1
    if cur_depth <= maxdepth then
        -- check that we can search
        if is_searchable(name, table) then
            -- iterate over search space
            function recurse(field, value)
                local new_tname = tostring(makeName(name, field))
                if is_tiledata(value) then
                    local indexing = string.format("%s[%d][%d]", field,tilex,tiley)
                    query(value[tilex][tiley], new_tname, search_term, appendField(path, indexing), bprinted)
                elseif not is_looping(path, new_tname) then
                    query(value, new_tname, search_term, appendField(path, field), bprinted)
                else
                    -- I don't know when this prints (if ever)
                    printField(path, field, value, bprinted)
                end
            end
            --print(name, path, "hello")
            foreach(table, name, recurse)
        end
    end
    cur_depth = cur_depth - 1
    return bprinted
end

function foreach(table, name, callback)
    local index = 0
    if getmetatable(table) and table._kind and (table._kind == "enum-type" or table._kind == "bitfield-type") then
        for idx, value in ipairs(table) do
            if is_exceeding_maxlength(index) then
                return
            end
            callback(idx, value)
            index = index + 1
        end
    elseif (name == "list" or string.find(name,"%.list")) and table["next"] then
        for field, value in utils.listpairs(table) do
            local m = tostring(field):gsub("<.*: ",""):gsub(">.*",""):gsub("%x%x%x%x%x%x","%1 ",1)
            local s = string.format("next{%d}->item", index)
            if is_exceeding_maxlength(index) then
                return
            end
            callback(s, value)
            index = index + 1
        end
    else
        for field, value in safe_pairs(table) do
            if is_exceeding_maxlength(index) then
                return
            end
            callback(field, value)
            index = index + 1
        end
    end
end

function setValue(path, field, value, new_value)
    if args.setvalue then
        if not args.search or is_match(path, field, value) then
            if type(value) == type(new_value) then
                value = new_value
            end
        end
    end
end

--Section: entry/initialization
function main()
    if args.help then
        print(help)
        return
    end
    processArguments()
    selection, path_info = table.unpack{getSelectionData()}
    debugf(0, tostring(selection), path_info)

    if selection == nil then
        qerror(string.format("Selected %s is null. Invalid selection.", path_info))
        return
    end
    query(selection, path_info, args.search, path_info)
end

function getSelectionData()
    local selection = nil
    local path_info = nil
    if args.table then
        debugf(0,"table selection")
        selection = findTable(args.table)
        path_info = args.table
        path_info_pattern = path_info
    elseif args.unit then
        debugf(0,"unit selection")
        selection = dfhack.gui.getSelectedUnit()
        path_info = "unit"
        path_info_pattern = path_info
    elseif args.item then
        debugf(0,"item selection")
        selection = dfhack.gui.getSelectedItem()
        path_info = "item"
        path_info_pattern = path_info
    elseif args.tile then
        debugf(0,"tile selection")
        local pos = copyall(df.global.cursor)
        selection = dfhack.maps.ensureTileBlock(pos.x,pos.y,pos.z)
        path_info = string.format("block[%d][%d][%d]",pos.x,pos.y,pos.z)
        path_info_pattern = string.format("block%%[%d%%]%%[%d%%]%%[%d%%]",pos.x,pos.y,pos.z)
        tilex = pos.x%16
        tiley = pos.y%16
    else
        print(help)
    end
    if args.getfield then
        selection = findPath(selection,args.getfield)
        path_info = path_info .. "." .. args.getfield
        path_info_pattern = path_info_pattern .. "." .. args.getfield
        print(path_info_pattern)
    end
    --print(selection, path_info)
    return selection, path_info
end

function processArguments()
    if args["1"] then
        args.oneline = true
    end
    --Table Recursion
    if args.maxdepth then
        maxdepth = tonumber(args.maxdepth)
        if not maxdepth then
            qerror(string.format("Must provide a number with -depth"))
        end
    elseif args.dumb then
        maxdepth = 25
    else
        maxdepth = 7
    end
    args.maxdepth = maxdepth

    --Table Length
    if not args.maxlength then
        --[[ Table length is inversely proportional to how useful the data is.
        257 was chosen with the intent of capturing all enums. Or hopefully most of them.
        ]]
        args.maxlength = 257
    else
        args.maxlength = tonumber(args.maxlength)
    end

    new_value = toType(args.setvalue)
    find_value = toType(args.findvalue)

    args.excludetype = args.excludetype and args.excludetype or ""
    args.excludekind = args.excludekind and args.excludekind or ""
    if string.find(args.excludetype, 'a') then
        bool_flags["boolean"] = true
        bool_flags["function"] = true
        bool_flags["number"] = true
        bool_flags["string"] = true
        bool_flags["table"] = true
        bool_flags["userdata"] = true
    else
        bool_flags["boolean"] = string.find(args.excludetype, 'b') and true or false
        bool_flags["function"] = string.find(args.excludetype, 'f') and true or false
        bool_flags["number"] = string.find(args.excludetype, 'n') and true or false
        bool_flags["string"] = string.find(args.excludetype, 's') and true or false
        bool_flags["table"] = string.find(args.excludetype, 't') and true or false
        bool_flags["userdata"] = string.find(args.excludetype, 'u') and true or false
    end

    if string.find(args.excludekind, 'a') then
        bool_flags["bitfield-type"] = true
        bool_flags["class-type"] = true
        bool_flags["enum-type"] = true
        bool_flags["struct-type"] = true
    else
        bool_flags["bitfield-type"] = string.find(args.excludekind, 'b') and true or false
        bool_flags["class-type"] = string.find(args.excludekind, 'c') and true or false
        bool_flags["enum-type"] = string.find(args.excludekind, 'e') and true or false
        bool_flags["struct-type"] = string.find(args.excludekind, 's') and true or false
    end
end

local bRunOnce={}
function runOnce(caller)
    if bRunOnce[caller] == true then
        return false
    end
    bRunOnce[caller] = true
    return true
end

function toType(str)
    if str ~= nil then
        if str == "true" then
            return true
        elseif str == "false" then
            return false
        elseif str == "nil" then
            return nil
        elseif tonumber(str) then
            return tonumber(str)
        else
            return tostring(str)
        end
    end
    return nil
end

--Section: filters
function is_searchable(field, value)
    if not is_blacklisted(field, value) and not df.isnull(value) then
        debugf(3,string.format("is_searchable( %s ): type: %s, length: %s, count: %s", value,type(value),getTableLength(value), countTableLength(value)))
        if not isEmpty(value) then
            if getmetatable(value) then
                if value._kind == "primitive" then
                    return false
                elseif value._kind == "struct" then
                    if args.safer then
                        return false
                    else
                        return true
                    end
                end
                debugf(3,string.format("_kind: %s, _type: %s", value._kind, value._type))
            end
            for _,_ in safe_pairs(value) do
                return true
            end
        end
    end
    return false
end

function is_match(path, field, value)
    if not args.search or string.find(tostring(field),args.search) or string.find(path,args.search) then
        if not args.findvalue or (not type(value) == "string" and value == find_value) or string.find(value,find_value) then
            return true
        end
    end
    return false
end

function is_looping(path, field)
    return not args.dumb and string.find(path, tostring(field))
end

function is_blacklisted(field, t)
    field = tostring(field)
    if not args.noblacklist then
        if string.find(field,"script") then
            return true
        elseif string.find(field,"saves") then
            return true
        elseif string.find(field,"movie") then
            return true
        elseif string.find(field,"font") then
            return true
        elseif string.find(field,"texpos") then
            return true
        end
    end
    return false
end

function is_tiledata(value)
    if args.tile and string.find(tostring(value),"%[16%]") then
        if type(value) and string.find(tostring(value[tilex]),"%[16%]") then
            return true
        end
    end
    return false
end

function is_excluded(value)
    return bool_flags[type(value)] or not isEmpty(value) and getmetatable(value) and bool_flags[value._kind]
end

function is_exceeding_maxlength(index)
    return args.maxlength and not (index < args.maxlength)
end

--Section: table helpers
function safe_pairs(t, keys_only)
    if keys_only then
        local mt = debug.getmetatable(t)
        if mt and mt._index_table then
            local idx = 0
            return function()
                idx = idx + 1
                if mt._index_table[idx] then
                    return mt._index_table[idx]
                end
            end
        end
    end
    local ret = table.pack(pcall(function() return pairs(t) end))
    local ok = ret[1]
    table.remove(ret, 1)
    if ok then
        return table.unpack(ret)
    else
        return function() end
    end
end

function isEmpty(t)
    for _,_ in safe_pairs(t) do
        return false
    end
    return true
end

function countTableLength(t)
    local count = 0
    for _,_ in safe_pairs(t) do
        count = count + 1
    end
    debugf(1,string.format("countTableEntries( %s ) = %d",t,count))
    return count
end

function getTableLength(t)
    if type(t) == "table" then
        local count=#t
        debugf(1,string.format("----getTableLength( %s ) = %d",t,count))
        return count
    end
    return 0
end

function findPath(t, path)
    debugf(0,string.format("findPath(%s, %s)",t, path))
    curTable = t
    keyParts = {}
    for word in string.gmatch(path, '([^.]+)') do --thanks stack overflow
        table.insert(keyParts, word)
    end
    if not curTable then
        qerror("Looks like we're borked somehow.")
    end
    for _,v in pairs(keyParts) do
        if v and curTable[v] ~= nil then
            debugf(1,"found something",v,curTable,curTable[v])
            curTable = curTable[v]
        else
            qerror("Table" .. v .. " does not exist.")
        end
    end
    --debugf(1,"returning",curTable)
    return curTable
end

function findTable(path) --this is the tricky part
    tableParts = {}
    for word in string.gmatch(path, '([^.]+)') do --thanks stack overflow
        table.insert(tableParts, word)
    end
    curTable = nil
    for k,v in pairs(tableParts) do
        if curTable == nil then
            if _G[v] ~= nil then
                curTable = _G[v]
            else
                qerror("Table" .. v .. " does not exist.")
            end
        else
            if curTable[v] ~= nil then
                curTable = curTable[v]
            else
                qerror("Table" .. v .. " does not exist.")
            end
        end
    end
    return curTable
end

function hasMetadata(value)
    if not isEmpty(value) then
        if getmetatable(value) and value._kind and value._kind ~= nil then
            return true
        end
    end
    return false
end

--Section: output helpers
function makeName(tname, field)
    if tonumber(field) then
        return string.format("%s[%s]", tname, field)
    end
    return field
end

function appendField(parent, field)
    newParent=""
    if tonumber(field) then
        newParent=string.format("%s[%s]",parent,field)
    else
        newParent=string.format("%s.%s",parent,field)
    end
    debugf(2, string.format("new parent: %s", newParent))
    return newParent
end

function makeIndentation()
    local base="| "
    local indent=""
    for i=0,(cur_depth) do
        indent=indent .. string.format("%s",base)
    end
    --indent=string.format("%s ",base)
    return indent
end

function makeIndentedField(path, field, value)
    if is_tiledata(value) then
        value = value[tilex][tiley]
        field = string.format("%s[%d][%d]", field,tilex,tiley)
    end
    local indent = not args.showpaths and makeIndentation() or ""
    local indented_field = string.format("%-40s ", tostring(args.showpaths and path or field) .. ":")

    if args.debugdata or not args.oneline or bToggle then
        indented_field = string.gsub(indented_field,"  "," ~")
        bToggle = false
    else
        bToggle = true
    end
    indented_field = indent .. indented_field
    local output = nil
    if hasMetadata(value) then
        --print simple meta data
        if args.oneline then
            output = string.format("%s %s [%s]", indented_field, value, value._kind)
        else
            local N = math.min(90, string.len(indented_field))
            indent = string.format("%" .. N .. "s", "")
            output = string.format("%s %s\n%s [has metatable; _kind: %s]", indented_field, value, indent, value._kind)
        end
    else
        --print regular field and value
        if args.debugdata then
            --also print value type
            output = string.format("%s %s; type(%s) = %s", indented_field, value, field, type(value))
        else
            output = string.format("%s %s", indented_field, value)
        end
    end
    if args.debugdata then
        local N = math.min(90, string.len(indented_field))
        indent = string.format("%" .. N .. "s", "")
        if hasMetadata(value) then
            --print lots of meta data
            if not args.search and args.oneline then
                output = output .. string.format("\n%s type(%s): %s, _kind: %s, _type: %s",
                        indent, field, type(value), field._kind, field._type)
            else
                output = output .. string.format("\n%s type(%s): %s\n%s _kind: %s\n%s _type: %s",
                        indent, field, type(value), indent, field._kind, indent, field._type)
            end
        end
    end
    return output
end

function printOnce(key, msg)
    if runOnce(key) then
        print(msg)
    end
end

--sometimes used to print fields, always used to print parents of fields
function printParents(path, field, value)
    --print("tony!", path, field, path_info_pattern)
    local value_printed = false
    path = string.gsub(path, path_info_pattern, "")
    field = string.gsub(field, path_info_pattern, "")
    local cd = cur_depth
    cur_depth = 0
    local cur_path = path_info
    local words = {}
    local index = 1

    for word in string.gmatch(path, '([^.]+)') do
        words[index] = word
        index = index + 1
    end
    local last_index = index - 1
    for i,word in ipairs(words) do
        if i ~= last_index then
            cur_path = appendField(cur_path, word)
            printOnce(cur_path, string.format("%s%s", makeIndentation(),word))
        elseif string.find(word,"%a+%[%d+%]%[%d+%]") then
            value_printed = true
            cur_path = appendField(cur_path, word)
            print(makeIndentedField(path, word, value))
        end
        cur_depth = cur_depth + 1
    end
    cur_depth = cd
    return value_printed
end

bToggle = true
function printField(path, field, value, bprinted_parent)
    if runOnce(printField) then
        printOnce(path,string.format("%s: %s", path, value))
        return
    end
    if not args.disableprint and not is_excluded(value) then
        if not args.search and not args.findvalue or is_match(path, field, value) then
            local bprinted_field = false
            if not args.showpaths and not bprinted_parent then
                bprinted_field = printParents(path, field, value)
            end
            if not bprinted_field then
                print(makeIndentedField(path, field, value))
            end
            return true
        end
    end
    return false
end

function debugf(level,...)
    if args.debug and level <= tonumber(args.debug) then
        local str=string.format(" #  %s",select(1, ...))
        for i = 2, select('#', ...) do
            str=string.format("%s\t%s",str,select(i, ...))
        end
        print(str)
    end
end

main()
print()