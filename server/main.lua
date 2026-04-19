local ESX = exports['es_extended']:getSharedObject()

-- [restaurantKey] = 'pending' | { netId, entity }
-- 'pending' is set synchronously before CreateThread so that concurrent
-- spawnPed events from multiple clients entering the zone at the same time
-- are all rejected by the guard check before any async work begins.
local spawnedPeds = {}

-- ─────────────────────────────────────────────────────────────────────────────
--  ORDER QUEUE
--  [restaurantKey] = { { src, itemName, pedNetId }, ... }
--  preparing[key]  = src do pedido ativo (false quando livre)
-- ─────────────────────────────────────────────────────────────────────────────

local orderQueue = {}
local preparing  = {}

local function processNextOrder(restaurantKey)
    if preparing[restaurantKey] then return end

    local queue = orderQueue[restaurantKey]
    if not queue or #queue == 0 then return end

    local order = table.remove(queue, 1)
    preparing[restaurantKey] = order.src

    TriggerClientEvent('ox_lib:notify', order.src, {
        description = Config.Locales.Preparing,
        type        = 'inform',
    })

    TriggerClientEvent('vc_restaurants:client:prepareOrder',
        order.src, restaurantKey, order.itemName, order.pedNetId, order.src)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  PED SPAWN
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:server:spawnPed', function(restaurantKey)
    -- Guard covers both 'pending' (in-progress) and a spawn-data table (done).
    -- Written synchronously so concurrent events in the same tick are rejected.
    if spawnedPeds[restaurantKey] then return end

    local resto = Restaurants[restaurantKey]
    if not resto then return end

    -- Lock immediately — before any yield — to prevent race condition
    spawnedPeds[restaurantKey] = 'pending'

    CreateThread(function()
        local pedNetId = 0
        local attempts = 0
        local maxTries = 5

        repeat
            attempts = attempts + 1
            pedNetId = 0
            ESX.OneSync.SpawnPed(resto.ped_model, resto.ped_spawn.xyz, resto.ped_spawn.w, function(obj)
                pedNetId = obj
            end)
            while pedNetId == 0 do Wait(10) end
            if not DoesEntityExist(NetworkGetEntityFromNetworkId(pedNetId)) then
                Wait(300)
                pedNetId = 0
            end
        until pedNetId ~= 0 or attempts >= maxTries

        if pedNetId == 0 then
            print('[VC-Restaurants] ERROR: Could not spawn ped for ' .. restaurantKey .. ' after ' .. maxTries .. ' attempts.')
            spawnedPeds[restaurantKey] = nil  -- release lock so a retry is possible
            return
        end

        local pedEntity = NetworkGetEntityFromNetworkId(pedNetId)
        spawnedPeds[restaurantKey] = { netId = pedNetId, entity = pedEntity }

        -- Arrival route (server-side so all clients see movement)
        for _, wp in ipairs(resto.ped_route) do
            TaskGoStraightToCoord(pedEntity, wp.x, wp.y, wp.z, 1.0, -1, wp.w, 0.5)
            repeat
                Wait(100)
                TaskGoStraightToCoord(pedEntity, wp.x, wp.y, wp.z, 1.0, -1, wp.w, 0.5)
            until #(GetEntityCoords(pedEntity) - vec3(wp.x, wp.y, wp.z)) < 1.5
            SetEntityHeading(pedEntity, wp.w)
        end

        FreezeEntityPosition(pedEntity, true)
        TriggerClientEvent('vc_restaurants:client:loadAnimation', -1, 'mp_fbi_heist', 'loop', pedNetId, restaurantKey)
    end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  PURCHASE — enqueue order, do not trigger prepareOrder directly
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:server:buyItem', function(restaurantKey, itemName, price, pedNetId)
    local src     = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local resto = Restaurants[restaurantKey]
    if not resto then return end

    -- Server-side item + price validation (anti-cheat)
    local validItem = false
    for _, it in ipairs(resto.items) do
        if it.name == itemName and it.price == price then
            validItem = true
            break
        end
    end
    if not validItem then
        print(string.format('[VC-Restaurants] WARN: player %s sent invalid item "%s" for restaurant "%s"', src, itemName, restaurantKey))
        return
    end

    local money = xPlayer.getInventoryItem('money').count
    if money < price then
        TriggerClientEvent('ox_lib:notify', src, {
            description = Config.Locales.NoMoney .. (price - money),
            type        = 'error',
        })
        return
    end

    xPlayer.removeInventoryItem('money', price)

    orderQueue[restaurantKey] = orderQueue[restaurantKey] or {}
    local queueLen = #orderQueue[restaurantKey]

    if queueLen > 0 or preparing[restaurantKey] then
        local pos = queueLen + (preparing[restaurantKey] and 1 or 0) + 1
        TriggerClientEvent('ox_lib:notify', src, {
            description = string.format('O teu pedido está em fila — posição %d', pos),
            type        = 'inform',
        })
    end

    orderQueue[restaurantKey][#orderQueue[restaurantKey] + 1] = {
        src      = src,
        itemName = itemName,
        pedNetId = pedNetId,
    }

    processNextOrder(restaurantKey)
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  ORDER COMPLETE — client signals server when prepareOrder finishes
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:server:orderComplete', function(restaurantKey)
    local src = source
    if preparing[restaurantKey] ~= src then return end
    preparing[restaurantKey] = false
    processNextOrder(restaurantKey)
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  TRAY PICKUP
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:server:trayPickup', function(restaurantKey, itemName, buyerSource)
    local src = source
    if src ~= buyerSource then return end
    TriggerClientEvent('vc_restaurants:client:markOrderReady', src, restaurantKey)
    TriggerClientEvent('vc_restaurants:client:carryTray', src, itemName)
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  GIVE ITEM
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:server:giveItem', function(itemName)
    local src = source
    exports.ox_inventory:AddItem(src, itemName, 1)
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  SPAWN PROP CALLBACK
-- ─────────────────────────────────────────────────────────────────────────────

ESX.RegisterServerCallback('vc_restaurants:cb:spawnProp', function(src, cb, model, coords)
    local propNetId = 0
    local attempts  = 0
    local maxTries  = 5

    repeat
        attempts = attempts + 1
        propNetId = 0
        ESX.OneSync.SpawnObject(model, coords, GetEntityHeading(GetPlayerPed(src)), function(obj)
            propNetId = obj
        end)
        while propNetId == 0 do Wait(10) end
        if not DoesEntityExist(NetworkGetEntityFromNetworkId(propNetId)) then
            Wait(300)
            propNetId = 0
        end
    until propNetId ~= 0 or attempts >= maxTries

    cb(propNetId)
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  PLAYER DISCONNECT — release mutex and clean queue
-- ─────────────────────────────────────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local src = source

    for key, activeSrc in pairs(preparing) do
        if activeSrc == src then
            print(string.format('[VC-Restaurants] Player %s disconnected mid-order (%s) — releasing mutex.', src, key))
            preparing[key] = false
            processNextOrder(key)
        end
    end

    for _, queue in pairs(orderQueue) do
        for i = #queue, 1, -1 do
            if queue[i].src == src then
                table.remove(queue, i)
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  CLEANUP on resource stop
-- ─────────────────────────────────────────────────────────────────────────────

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, data in pairs(spawnedPeds) do
        -- Skip 'pending' entries (string, not table)
        if type(data) == 'table' and DoesEntityExist(data.entity) then
            DeleteEntity(data.entity)
        end
    end
end)
