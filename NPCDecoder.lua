_addon.name = 'NPCDecoder'
_addon.author = 'Ghosty'
_addon.command = 'npcdecoder'
_addon.commands = {'npcd'}
_addon.version = '0.2'

require('luau')
files = require('files')
json = require('json2')
packets = require('packets')
bit = require('bit')
res = require('resources')

res.races[1].dat = 'ROM/27/82.DAT' -- Hume M
res.races[2].dat = 'ROM/32/58.DAT' -- Hume F
res.races[3].dat = 'ROM/37/31.DAT' -- Elvaan M
res.races[4].dat = 'ROM/42/4.DAT' -- Elvaan F
res.races[5].dat = 'ROM/46/93.DAT' -- Tarutaru M
res.races[6].dat = 'ROM/46/93.DAT' -- Tarutaru F
res.races[7].dat = 'ROM/51/89.DAT' -- Mithra
res.races[8].dat = 'ROM/56/59.DAT' -- Galka
res.races[29].dat = 'ROM/61/110.DAT' -- Mithra Child
res.races[30].dat = 'ROM/61/58.DAT' -- Hume/Elvaan Child F
res.races[31].dat = 'ROM/61/85.DAT' -- Hume/Elvaan Child M
res.races[32].dat = 'ROM/169/11.DAT' -- Chocobo
res.races[33].dat = 'ROM/169/11.DAT' -- Chocobo
res.races[34].dat = 'ROM/169/11.DAT' -- Chocobo
res.races[35].dat = 'ROM/169/11.DAT' -- Chocobo
res.races[36].dat = 'ROM/169/11.DAT' -- Chocobo

res.races[1].json_dir = 'Hume Male'
res.races[2].json_dir = 'Hume Female'
res.races[3].json_dir = 'Elvaan Male'
res.races[4].json_dir = 'Elvaan Female'
res.races[5].json_dir = 'Tarutaru'
res.races[6].json_dir = 'Tarutaru'
res.races[7].json_dir = 'Mithra'
res.races[8].json_dir = 'Galka'

local npc_db = config.load('npc_db.xml')

local _last_zone_id = 0

function read_json(path)
    if not files.exists(path) then
        return nil
    end
    local j = files.read(path)
    local t = json.decode(j)
    t = table.rekey(t, 'ModelID')
    return t
end

windower.register_event('load',function()
    for id, race in pairs(res.races) do
        if race.json_dir then
            local race_json = 'json/'..race.json_dir
            res.races[id].faces = read_json(race_json..'/Faces.json')
            res.races[id].head = read_json(race_json..'/Heads.json')
            res.races[id].body = read_json(race_json..'/Body.json')
            res.races[id].hands = read_json(race_json..'/Hands.json')
            res.races[id].legs = read_json(race_json..'/Legs.json')
            res.races[id].feet = read_json(race_json..'/Feet.json')
            res.races[id].main = read_json(race_json..'/Main.json')
            res.races[id].sub = read_json(race_json..'/Sub.json')
            --it seems like NPCs don't get ranged gear - todo: need to check if sub or ranged is the missing one
            --res.races[id].ranged = read_json(race_json..'/Ranged.json')
        end
    end
end)

windower.register_event('incoming chunk', function(id,data,modified,injected,blocked)
    -- write out the previous zone list when changing zones
    if id == 0x0B then
        write_zone_ini(_last_zone_id)
        config.save(npc_db, 'npc_db.xml')
    end

    -- we're only interested in NPC update packets
    if id ~= 0x0E then return end

    process_npc_data(data)
end)

function unpack_gear_id(gear_id)
    local id = string.byte(gear_id:sub(1,1)) + bit.lshift(string.byte(gear_id:sub(2,2)), 8)
    local id_masked = bit.band(id, 0x0FFF)
    return id_masked
end

function process_npc_data(data)
    local dir = 'incoming'
    local packet = packets.parse(dir, data)
    -- we only care about model information
    if not packet or packet.Model == 0 then return end
    -- non-precomposed flag
    -- todo: also handle precomposed NPCs
    if packet._unknown5 == 0 then return end

    local npc_obj = windower.ffxi.get_mob_by_id(packet.NPC)
    if not npc_obj then return end
    if S{'', '???'}[npc_obj.name:trim()] then return end

    local info = windower.ffxi.get_info()
    if not info.logged_in then return end

    local gear = data:sub(16*3 + 5, 16*3 + 5 + 14)

    if not bit.band(string.byte(gear:sub(2, 2)), 0x10)
    or not bit.band(string.byte(gear:sub(4, 4)), 0x20)
    or not bit.band(string.byte(gear:sub(6, 6)), 0x30)
    or not bit.band(string.byte(gear:sub(8, 8)), 0x40)
    or not bit.band(string.byte(gear:sub(10, 10)), 0x50)
    or not bit.band(string.byte(gear:sub(12, 12)), 0x60)
    or not bit.band(string.byte(gear:sub(14, 14)), 0x70) then return end

    local npc = {
        name = npc_obj.name,
        id = packet.NPC,
        index = packet.Index,
        race_id = bit.band(bit.rshift(packet.Model, 8), 0xFF),
        face_id = bit.band(packet.Model, 0xFF),
        gear_ids = {
            head = unpack_gear_id(gear:sub(1, 2)),
            body = unpack_gear_id(gear:sub(3, 4)),
            hands = unpack_gear_id(gear:sub(5, 6)),
            legs = unpack_gear_id(gear:sub(7, 8)),
            feet = unpack_gear_id(gear:sub(9, 10)),
            main = unpack_gear_id(gear:sub(11, 12)),
            sub = unpack_gear_id(gear:sub(13, 14)),
            --ranged = unpack_gear_id(gear:sub(15, 16)),
        },
    }

    -- log precomposed NPCs that apparently have gear anyway?
    if npc.race_id == 0 then
        log("precomposed NPC with gear detected: "..npc.name..", gear hex: "..gear:hex())
        return
    end

    _last_zone_id = info.zone

    local zone_id = info.zone
    local zone_table = res.zones[zone_id]
    local zone_name = 'unknown'
    if zone_table ~= nil then
        zone_name = zone_table.en
    end

    npc.zone_id = zone_id
    npc.zone_name = zone_name
    npc.dats = {}
    npc.dats.race = res.races[npc.race_id].dat
    if res.races[npc.race_id].faces and res.races[npc.race_id].faces[npc.face_id] then
        npc.dats.face = res.races[npc.race_id].faces[npc.race_id == 5 and (npc.face_id + 100) or npc.face_id].Path
    else
        npc.dats.face = nil
    end
    for slot, gear_id in pairs(npc.gear_ids) do
        repeat
            if not res.races[npc.race_id][slot] then
                npc.dats[slot] = 'null-'..gear_id
                do break end
            end
            local gear_t = res.races[npc.race_id][slot][gear_id]
            npc.dats[slot] = gear_t and gear_t.Path or 'null-'..gear_id
        until true
    end

    if not npc_db[zone_id] then
        npc_db[zone_id] = {}
    end
    if not npc_db[zone_id][packet.NPC] or npc_db[zone_id][packet.NPC].name ~= npc.name then
        npc_db[zone_id][packet.NPC] = npc
    end

    write_npc(npc, ini_format)
    write_npc(npc, noesis_format)
end

function replace_gender_symbols(str)
    return str:gsub('♂', 'Male'):gsub('♀', 'Female')
end

function npc_path(npc)
    return npc.zone_name..'/'..replace_gender_symbols(res.races[npc.race_id].en)..'/'..npc.name..'-'..npc.id
end

function write_npc(npc, format_fn)
    local formatted, root_dir, extension = format_fn(npc)
    local path = root_dir..'/'..npc_path(npc)..'.'..extension
    if files.exists(path) then return end

    local f = files.new(path)
    f:write(formatted)
end

function ini_format(npc)
    local ini_template =
[[[%s]
Race=%s
Face=%s
Head=%s
Body=%s
Hands=%s
Legs=%s
Feet=%s
Main=%s
Sub=%s
Ranged=%s]]

    local function convert_path(dat_path)
        if not dat_path then return nil end
        return string.gsub(dat_path, '^ROM/', '1/')
    end

    local ini = ini_template:format(
        npc.name..'-'..npc.id,
        convert_path(npc.dats.race) or 'null',
        convert_path(npc.dats.face) or ('null-'..npc.face_id),
        convert_path(npc.dats.head) or 'null',
        convert_path(npc.dats.body) or 'null',
        convert_path(npc.dats.hands) or 'null',
        convert_path(npc.dats.legs) or 'null',
        convert_path(npc.dats.feet) or 'null',
        convert_path(npc.dats.main) or 'null',
        convert_path(npc.dats.sub) or 'null',
        convert_path(npc.dats.ranged) or 'null')
    return ini, 'ini', 'ini'
end

function noesis_format(npc)
    local noesis_template =
[[NOESIS_FF11_DAT_SET
setPathKey "HKEY_LOCAL_MACHINE" "SOFTWARE\WOW6432Node\PlayOnlineEU\InstallFolder" "0001"

dat "__skeleton" "%s"
dat "__animation" "%s"
dat "face" "%s"
dat "head" "%s"
dat "body" "%s"
dat "hands" "%s"
dat "legs" "%s"
dat "feet" "%s"
dat "weapon" "%s"
dat "sub" "%s"]]

    local noesis = noesis_template:format(
        npc.dats.race,
        npc.dats.race,
        npc.dats.face,
        npc.dats.head,
        npc.dats.body,
        npc.dats.hands,
        npc.dats.legs,
        npc.dats.feet,
        npc.dats.main,
        npc.dats.sub)

    return noesis, 'noesis', 'ff11datset'
end

function write_zone_ini(zone_id)
    if not npc_db[zone_id] then return end

    local zone_table = res.zones[zone_id]
    local zone_name = 'unknown'
    if zone_table ~= nil then
        zone_name = zone_table.en
    end

    local ini = L{}
    for id, npc in pairs(npc_db[zone_id]) do
        local npc_ini, _, _ = ini_format(npc)
        table.insert(ini, npc_ini)
    end

    local path = 'ini/'..zone_name..'/NPCs.ini'
    local f = files.new(path)
    f:write(table.concat(ini, '\n\n'))
end

windower.register_event("addon command", function(command, ...)
    local args = L{ ... }

    if S{'write', 'w'}[command] then
        write_zone_ini(_last_zone_id)
        config.save(npc_db, 'npc_db.xml')
    end
end)