-- Shared utilities for vc_restaurants
-- Available on both client and server via shared_scripts

local function fv4(v)
    return string.format('vector4(%.4f, %.4f, %.4f, %.4f)', v.x, v.y, v.z, v.w)
end

local function fv3(v)
    return string.format('vec3(%.4f, %.4f, %.4f)', v.x, v.y, v.z)
end

-- Generates the full Lua assignment block for a restaurant entry.
-- Used by the editor to write to data/restaurants.lua and to print/copy to clipboard.
function FormatRestaurantEntry(key, data)
    local lines = {}
    local push  = function(s) lines[#lines + 1] = s end

    push(string.format("Restaurants['%s'] = {", key))
    push(string.format("    coords    = %s,",   fv3(data.coords)))
    push(string.format("    ped_model = '%s',", data.ped_model))
    push(string.format("    ped_spawn = %s,",   fv4(data.ped_spawn)))

    local function routeLine(field, tbl)
        local parts = {}
        for _, wp in ipairs(tbl) do
            parts[#parts + 1] = fv4(wp)
        end
        push(string.format("    %-10s = {%s},", field, table.concat(parts, ', ')))
    end

    routeLine('ped_route',  data.ped_route)
    routeLine('ped_route2', data.ped_route2)
    routeLine('ped_route3', data.ped_route3)

    push(string.format("    take      = %s,", fv4(data.take)))

    local itemParts = {}
    for _, it in ipairs(data.items) do
        itemParts[#itemParts + 1] = string.format(
            "{ name = '%s', label = '%s', price = %d }", it.name, it.label, it.price)
    end
    push("    items = { " .. table.concat(itemParts, ', ') .. " }")
    push("}")

    return table.concat(lines, '\n')
end
