local ESX = exports['es_extended']:getSharedObject()

local spawned    = {}   -- [restaurantKey] = true (ped já solicitado ao servidor)
local zones      = {}   -- [restaurantKey] = lib.zones object (para destroy em runtime)
local orderReady = {}   -- [restaurantKey] = bool (sinaliza que o tabuleiro foi recolhido)

-- ─────────────────────────────────────────────────────────────────────────────
--  ZONE FACTORY — cria sphere zone para um restaurante
--  Usado tanto no arranque como quando um novo restaurante é adicionado via editor
-- ─────────────────────────────────────────────────────────────────────────────

local function createZone(key, resto)
    -- Destruir zona existente (caso seja uma atualização)
    if zones[key] then
        zones[key]:remove()
        zones[key] = nil
    end

    zones[key] = lib.zones.sphere({
        coords  = resto.coords,
        radius  = 80.0,
        onEnter = function()
            if spawned[key] then return end
            spawned[key] = true
            lib.requestModel(GetHashKey(resto.ped_model))
            TriggerServerEvent('vc_restaurants:server:spawnPed', key)
        end,
    })
end

-- ─────────────────────────────────────────────────────────────────────────────
--  ZONE-BASED PROXIMITY  — substitui polling GetInteriorFromEntity
--  Criado no arranque para todos os restaurantes presentes no ficheiro
-- ─────────────────────────────────────────────────────────────────────────────

CreateThread(function()
    Wait(500)   -- Aguarda ox_lib estar pronto
    for k, v in pairs(Restaurants) do
        createZone(k, v)
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  SYNC RESTAURANTS TABLE
--  Disparado pelo servidor após save/delete no editor.
--  Atualiza Restaurants{} em runtime E cria/destrói zonas conforme necessário.
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:client:syncRestaurant', function(key, data)
    if data then
        -- Novo restaurante ou atualização
        Restaurants[key] = data
        spawned[key]     = nil   -- reset para permitir novo spawn se necessário
        createZone(key, data)
    else
        -- Eliminado
        Restaurants[key] = nil
        spawned[key]     = nil
        if zones[key] then
            zones[key]:remove()
            zones[key] = nil
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  LOAD ANIMATION + OX_TARGET  (broadcast a todos os clientes)
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:client:loadAnimation', function(animDict, animName, pedNetId, restaurantKey)
    lib.requestAnimDict(animDict)
    Wait(300)

    local ped = NetworkGetEntityFromNetworkId(pedNetId)
    if not DoesEntityExist(ped) then return end

    TaskPlayAnim(ped, animDict, animName, 1.0, -1.0, -1, 1, 1, false, false, false)
    PlayPedAmbientSpeechNative(ped, 'SHOP_GREET', 'SPEECH_PARAMS_STANDARD')
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    -- ox_target espera entity handle, não network ID
    exports.ox_target:addEntity(ped, {
        {
            icon     = 'fa-solid fa-utensils',
            label    = Config.Locales.Order,
            distance = 2.0,
            onSelect = function(data)
                LocalPlayer.state.ped = data.entity
                OpenRestaurantMenu(restaurantKey)
            end,
            canInteract = function(entity)
                return IsEntityPlayingAnim(entity, animDict, animName, 3)
            end,
        }
    })

    -- Watchdog: mantém a animação idle viva
    CreateThread(function()
        while DoesEntityExist(ped) do
            Wait(2000)
            if not IsEntityPlayingAnim(ped, animDict, animName, 3) and IsPedStill(ped) then
                TaskPlayAnim(ped, animDict, animName, 3.0, -8.0, -1, 1, 0, false, false, false)
            end
        end
        -- Ped deixou de existir — limpar target (entity handle)
        exports.ox_target:removeEntity(ped)
    end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  ORDER PREPARATION  (corre no cliente do comprador)
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:client:prepareOrder', function(restaurantKey, itemName, pedNetId, buyerSource)
    local resto = Restaurants[restaurantKey]
    if not resto then return end

    local ped = NetworkGetEntityFromNetworkId(pedNetId)
    if not DoesEntityExist(ped) then return end

    orderReady[restaurantKey] = false

    lib.showTextUI('⏳ ' .. Config.Locales.Preparing, { position = 'bottom-center' })

    PlayPedAmbientSpeechNative(ped, 'SHOP_SELL', 'SPEECH_PARAMS_STANDARD')
    FreezeEntityPosition(ped, false)

    -- Rota cozinha
    for _, wp in ipairs(resto.ped_route2) do
        TaskGoStraightToCoord(ped, wp.x, wp.y, wp.z, 1.0, -1, wp.w, 0.5)
        repeat
            Wait(100)
            TaskGoStraightToCoord(ped, wp.x, wp.y, wp.z, 1.0, -1, wp.w, 0.5)
        until #(GetEntityCoords(ped) - vec3(wp.x, wp.y, wp.z)) < 1.5
        SetEntityHeading(ped, wp.w)
    end

    Wait(800)
    lib.requestAnimDict('missheistfbisetup1')
    TaskPlayAnim(ped, 'missheistfbisetup1', 'hassle_intro_loop_f', 1.0, -1.0, -1, 1, 1, false, false, false)
    Wait(5000)
    ClearPedTasks(ped)

    -- Anexar tabuleiro ao ped
    local prop = CreateObject(GetHashKey('prop_food_tray_03'), GetEntityCoords(ped), false, false, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 60309),
        0.25, 0.05, 0.23, -55.0, 290.0, 0.0, true, true, false, true, 1, true)

    lib.requestAnimDict('anim@heists@box_carry@')
    TaskPlayAnim(ped, 'anim@heists@box_carry@', 'idle', 3.0, -8.0, -1, 63, 0, false, false, false)
    Wait(800)

    -- Rota entrega
    for i, wp in ipairs(resto.ped_route3) do
        TaskGoStraightToCoord(ped, wp.x, wp.y, wp.z, 1.0, -1, wp.w, 0.5)
        repeat
            Wait(100)
            TaskGoStraightToCoord(ped, wp.x, wp.y, wp.z, 1.0, -1, wp.w, 0.5)
        until #(GetEntityCoords(ped) - vec3(wp.x, wp.y, wp.z)) < 1.5
        if i == #resto.ped_route3 then
            SetEntityCoords(ped, wp.x, wp.y - 0.5, wp.z - 0.9)
        end
        SetEntityHeading(ped, wp.w)
    end

    ClearPedTasks(ped)

    -- Soltar tabuleiro no balcão
    DetachEntity(prop, false, false)
    SetEntityCoords(prop, resto.take.x, resto.take.y, resto.take.z)
    PlaceObjectOnGroundProperly(prop)
    FreezeEntityPosition(prop, true)

    lib.hideTextUI()
    PlayPedAmbientSpeechNative(ped, 'SHOP_GOODBYE', 'SPEECH_PARAMS_STANDARD')
    lib.notify({ description = Config.Locales.OrderReady, type = 'success' })
    lib.showTextUI('🍽️ ' .. Config.Locales.OrderReady, { position = 'bottom-center' })

    -- Target no tabuleiro para recolha (entity handle do prop)
    exports.ox_target:addLocalEntity(prop, {
        {
            icon     = 'fa-solid fa-utensils',
            label    = Config.Locales.Tray,
            distance = 1.5,
            onSelect = function()
                TriggerServerEvent('vc_restaurants:server:trayPickup', restaurantKey, itemName, buyerSource)
            end,
        }
    })

    -- Bloquear até o tabuleiro ser recolhido
    repeat Wait(500) until orderReady[restaurantKey]

    lib.hideTextUI()

    -- Devolver ped à estação idle
    ClearPedTasks(ped)
    lib.requestAnimDict('mp_fbi_heist')
    TaskPlayAnim(ped, 'mp_fbi_heist', 'loop', 1.0, -1.0, -1, 1, 1, false, false, false)
    FreezeEntityPosition(ped, true)
    DeleteEntity(prop)
    orderReady[restaurantKey] = nil

    -- Sinalizar ao servidor que o pedido terminou → processa o próximo na fila
    TriggerServerEvent('vc_restaurants:server:orderComplete', restaurantKey)
end)

RegisterNetEvent('vc_restaurants:client:markOrderReady', function(restaurantKey)
    orderReady[restaurantKey] = true
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  PLAYER CARRY TRAY
-- ─────────────────────────────────────────────────────────────────────────────

local carry = { active = false, prop = 0, item = nil }

RegisterNetEvent('vc_restaurants:client:carryTray', function(itemName)
    local playerPed = PlayerPedId()
    carry.item      = itemName
    carry.prop      = 0

    ESX.TriggerServerCallback('vc_restaurants:cb:spawnProp', function(netId)
        carry.prop = NetworkGetEntityFromNetworkId(netId)
    end, 'prop_food_tray_03', GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 0.0, 1.0))

    while carry.prop == 0 do Wait(10) end

    lib.notify({ description = Config.Locales.TrayTwo, type = 'success' })

    AttachEntityToEntity(carry.prop, playerPed, GetPedBoneIndex(playerPed, 60309),
        0.25, 0.05, 0.23, -55.0, 290.0, 0.0, true, true, false, true, 1, true)

    lib.requestAnimDict('anim@heists@box_carry@')
    TaskPlayAnim(playerPed, 'anim@heists@box_carry@', 'idle', 3.0, -8.0, -1, 63, 0, false, false, false)

    carry.active = true
end)

-- Mantém animação de carry + E para colocar
CreateThread(function()
    while true do
        if carry.active then
            Wait(0)
            local ped = PlayerPedId()
            if not IsEntityPlayingAnim(ped, 'anim@heists@box_carry@', 'idle', 3) then
                TaskPlayAnim(ped, 'anim@heists@box_carry@', 'idle', 3.0, -8.0, -1, 63, 0, false, false, false)
            end
            if IsControlJustPressed(0, 38) then  -- E
                PlaceTray()
            end
        else
            Wait(500)
        end
    end
end)

function PlaceTray()
    if not carry.active then return end
    carry.active = false
    DetachEntity(carry.prop, false, false)
    ClearPedTasks(PlayerPedId())
    exports['object_gizmo']:useGizmo(carry.prop)
    TriggerServerEvent('vc_restaurants:server:giveItem', carry.item)
    Wait(60000)
    if DoesEntityExist(carry.prop) then DeleteEntity(carry.prop) end
    carry.prop = 0
    carry.item = nil
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if carry.prop ~= 0 and DoesEntityExist(carry.prop) then
        DeleteEntity(carry.prop)
    end
end)
