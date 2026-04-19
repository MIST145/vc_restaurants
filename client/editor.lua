-- ─────────────────────────────────────────────────────────────────────────────
--  EDITOR — client side  (vc_restaurants v2)
-- ─────────────────────────────────────────────────────────────────────────────

local editorActive = false
local isEditMode   = false   -- true quando a editar restaurante existente

local function freshData()
    return {
        key        = nil,
        ped_model  = nil,
        coords     = nil,
        ped_spawn  = nil,
        ped_route  = {},
        ped_route2 = {},
        ped_route3 = {},
        take       = nil,
        items      = {},
    }
end

local editorData = freshData()

-- ─────────────────────────────────────────────────────────────────────────────
--  CLIPBOARD via NUI
-- ─────────────────────────────────────────────────────────────────────────────

local function CopyToClipboard(text)
    SendNuiMessage(json.encode({ type = 'vcr_copyText', text = tostring(text) }))
end

RegisterNetEvent('vc_restaurants:client:copyToClipboard', function(text)
    CopyToClipboard(text)
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  MODEL LOADER
-- ─────────────────────────────────────────────────────────────────────────────

local function LoadModel(model)
    local hash = GetHashKey(model)
    RequestModel(hash)
    local attempts = 0
    while not HasModelLoaded(hash) and attempts < 100 do
        Wait(50)
        attempts = attempts + 1
    end
    return HasModelLoaded(hash), hash
end

-- ─────────────────────────────────────────────────────────────────────────────
--  LASER HELPERS
-- ─────────────────────────────────────────────────────────────────────────────

local function RotationToDirection(rot)
    local r = {
        x = (math.pi / 180) * rot.x,
        y = (math.pi / 180) * rot.y,
        z = (math.pi / 180) * rot.z,
    }
    return {
        x = -math.sin(r.z) * math.abs(math.cos(r.x)),
        y =  math.cos(r.z) * math.abs(math.cos(r.x)),
        z =  math.sin(r.x),
    }
end

local function RayCastCamera(distance)
    local rot   = GetGameplayCamRot()
    local coord = GetGameplayCamCoord()
    local dir   = RotationToDirection(rot)
    local dest  = {
        x = coord.x + dir.x * distance,
        y = coord.y + dir.y * distance,
        z = coord.z + dir.z * distance,
    }
    local _, hit, endCoords = GetShapeTestResult(
        StartShapeTestRay(coord.x, coord.y, coord.z, dest.x, dest.y, dest.z, -1, PlayerPedId(), 0)
    )
    return hit == 1, endCoords
end

local function DrawLaserBeam(hint, color)
    local hit, coords = RayCastCamera(20.0)
    SetTextFont(4)
    SetTextScale(0.4, 0.4)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry('STRING')
    SetTextDropShadow()
    SetTextOutline()
    AddTextComponentString(hint)
    DrawText(0.43, 0.888)
    if hit then
        local pos = GetEntityCoords(PlayerPedId())
        DrawLine(pos.x, pos.y, pos.z, coords.x, coords.y, coords.z, color.r, color.g, color.b, color.a)
        DrawMarker(28, coords.x, coords.y, coords.z,
            0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
            0.1, 0.1, 0.1,
            color.r, color.g, color.b, color.a,
            false, true, 2, nil, nil, false)
    end
    return hit, coords
end

-- Laser single pick — bloqueia a thread, retorna coords ou nil
local function LaserPickSingle(label, color)
    color = color or { r = 0, g = 180, b = 255, a = 200 }
    local hint = label .. '\n~g~[E]~w~ CONFIRMAR  ~r~[ESC]~w~ CANCELAR'
    lib.showTextUI(hint, { position = 'right-center' })
    while true do
        local hit, coords = DrawLaserBeam(hint, color)
        if IsControlJustReleased(0, 38) then        -- E
            if hit then
                lib.hideTextUI()
                return coords
            else
                lib.notify({ description = 'Nenhuma superfície detetada — aponta para o chão.', type = 'error' })
            end
        elseif IsControlJustReleased(0, 200) then   -- ESC / FRONTEND_CANCEL
            lib.hideTextUI()
            return nil
        end
        Wait(0)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  PED POSITION  (jogador anda até ao sítio, ENTER captura)
-- ─────────────────────────────────────────────────────────────────────────────

local function PedPickPosition()
    lib.showTextUI(
        'Vai para a posição pretendida\n~g~[ENTER]~w~ CONFIRMAR  ~r~[ESC]~w~ CANCELAR',
        { position = 'right-center' }
    )
    while true do
        if IsControlJustPressed(0, 215) then     -- ENTER (INPUT_FRONTEND_ACCEPT)
            lib.hideTextUI()
            return GetEntityCoords(PlayerPedId()), GetEntityHeading(PlayerPedId())
        elseif IsControlJustPressed(0, 200) then -- ESC (INPUT_FRONTEND_CANCEL)
            lib.hideTextUI()
            return nil, nil
        end
        Wait(0)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  NPC PREVIEW PLACER
--  Spawna ped com alpha 150, move com raycast.
--  [SHIFT] roda esquerda, [ALT] roda direita, [ENTER] confirma, [ESC] cancela.
-- ─────────────────────────────────────────────────────────────────────────────

local function NpcPickPosition(pedModel)
    local model = (pedModel and pedModel ~= '') and pedModel or 'mp_m_shopkeep_01'
    local ok, hash = LoadModel(model)
    if not ok then
        lib.notify({ description = 'Erro ao carregar modelo: ' .. model, type = 'error' })
        return nil, nil
    end

    local origin = GetEntityCoords(PlayerPedId())
    local ent    = CreatePed(4, hash, origin.x, origin.y, origin.z, 0.0, false, false)
    SetBlockingOfNonTemporaryEvents(ent, true)
    SetPedCanRagdoll(ent, false)
    SetEntityCollision(ent, false, false)
    SetEntityAlpha(ent, 150, false)
    FreezeEntityPosition(ent, true)

    lib.showTextUI(
        '🧍 NPC Preview\n~g~[ENTER]~w~ CONFIRMAR  ~r~[ESC]~w~ CANCELAR\n[SHIFT] Rodar ←  [ALT] Rodar →',
        { position = 'right-center' }
    )

    while true do
        Wait(0)
        DisableControlAction(0, 14, true)   -- INPUT_LOOK_LR
        DisableControlAction(0, 15, true)   -- INPUT_LOOK_UD

        local hit, coords = RayCastCamera(20.0)
        if hit and coords then
            SetEntityCoords(ent, coords.x, coords.y, coords.z, false, false, false, false)
            PlaceObjectOnGroundProperly(ent)
        end

        -- SHIFT (21 = INPUT_SPRINT) → rodar esquerda
        if IsControlPressed(0, 21) then
            SetEntityHeading(ent, GetEntityHeading(ent) + 1.5)
        -- ALT (19 = INPUT_CHARACTER_WHEEL) → rodar direita
        elseif IsControlPressed(0, 19) then
            SetEntityHeading(ent, GetEntityHeading(ent) - 1.5)
        end

        if IsControlJustPressed(0, 215) then     -- ENTER
            local fc = GetEntityCoords(ent)
            local fh = GetEntityHeading(ent)
            lib.hideTextUI()
            DeleteEntity(ent)
            return fc, fh
        elseif IsControlJustPressed(0, 200) then -- ESC
            lib.hideTextUI()
            DeleteEntity(ent)
            return nil, nil
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
--  PICK ONE POINT  (abstrai laser / ped / npc)
-- ─────────────────────────────────────────────────────────────────────────────

local function PickOnePoint(method, pedModel, color, pointIndex)
    local label = 'PONTO ' .. tostring(pointIndex or '?')

    if method == 'laser' then
        local coords = LaserPickSingle(label, color or { r = 255, g = 165, b = 0, a = 200 })
        if not coords then return nil end
        return vector4(coords.x, coords.y, coords.z, GetEntityHeading(PlayerPedId()))

    elseif method == 'ped' then
        local coords, hdg = PedPickPosition()
        if not coords then return nil end
        return vector4(coords.x, coords.y, coords.z, hdg)

    elseif method == 'npc' then
        local coords, hdg = NpcPickPosition(pedModel)
        if not coords then return nil end
        return vector4(coords.x, coords.y, coords.z, hdg)
    end

    return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
--  ROUTE PREVIEW  (ped genérico percorre os waypoints e apaga no final)
-- ─────────────────────────────────────────────────────────────────────────────

local function PreviewRoute(route, pedModel)
    if not route or #route < 1 then
        lib.notify({ description = 'Rota vazia — sem nada para pré-visualizar.', type = 'error' })
        return
    end

    local model = (pedModel and pedModel ~= '') and pedModel or 'mp_m_shopkeep_01'
    local ok, hash = LoadModel(model)
    if not ok then
        lib.notify({ description = 'Erro ao carregar modelo para preview.', type = 'error' })
        return
    end

    local first = route[1]
    local ent   = CreatePed(4, hash, first.x, first.y, first.z, first.w, false, false)
    SetBlockingOfNonTemporaryEvents(ent, true)
    SetPedCanRagdoll(ent, false)
    SetEntityInvincible(ent, true)
    SetPedFleeAttributes(ent, 0, false)

    lib.notify({ description = '▶️ A pré-visualizar rota...', type = 'inform' })

    for _, wp in ipairs(route) do
        if not DoesEntityExist(ent) then break end
        TaskGoStraightToCoord(ent, wp.x, wp.y, wp.z, 1.0, -1, wp.w, 0.5)
        local timeout = 0
        repeat
            Wait(100)
            timeout = timeout + 100
            if DoesEntityExist(ent) then
                TaskGoStraightToCoord(ent, wp.x, wp.y, wp.z, 1.0, -1, wp.w, 0.5)
            end
        until not DoesEntityExist(ent)
             or #(GetEntityCoords(ent) - vec3(wp.x, wp.y, wp.z)) < 1.5
             or timeout > 15000
        if DoesEntityExist(ent) then SetEntityHeading(ent, wp.w) end
        Wait(200)
    end

    Wait(1200)
    if DoesEntityExist(ent) then DeleteEntity(ent) end
    lib.notify({ description = '✅ Preview concluído.', type = 'success' })
end

-- ─────────────────────────────────────────────────────────────────────────────
--  LOAD EXISTING RESTAURANT INTO editorData  (deep copy)
-- ─────────────────────────────────────────────────────────────────────────────

local function LoadRestaurantIntoEditor(key)
    local r = Restaurants[key]
    if not r then return false end

    local function copyRoute(src)
        local t = {}
        for _, wp in ipairs(src or {}) do
            t[#t + 1] = vector4(wp.x, wp.y, wp.z, wp.w)
        end
        return t
    end

    editorData = {
        key        = key,
        ped_model  = r.ped_model,
        coords     = r.coords,
        ped_spawn  = r.ped_spawn,
        ped_route  = copyRoute(r.ped_route),
        ped_route2 = copyRoute(r.ped_route2),
        ped_route3 = copyRoute(r.ped_route3),
        take       = r.take,
        items      = {},
    }
    for _, it in ipairs(r.items or {}) do
        editorData.items[#editorData.items + 1] = { name = it.name, label = it.label, price = it.price }
    end
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
--  FORWARD DECLARATIONS
-- ─────────────────────────────────────────────────────────────────────────────

local OpenEditorStartMenu
local OpenEditorMenu
local OpenRestaurantListMenu
local OpenSpawnMenu
local OpenRouteMenu
local OpenItemsMenu

-- ─────────────────────────────────────────────────────────────────────────────
--  DISPLAY HELPERS
-- ─────────────────────────────────────────────────────────────────────────────

local function fmtV3(v)
    if not v then return '⬜ Não definido' end
    return string.format('%.2f, %.2f, %.2f', v.x, v.y, v.z)
end

local function fmtV4(v)
    if not v then return '⬜ Não definido' end
    return string.format('%.2f, %.2f, %.2f  (%.1f°)', v.x, v.y, v.z, v.w)
end

local function fmtRoute(t)
    if not t or #t == 0 then return '⬜ Não definido' end
    return string.format('✅ %d pontos', #t)
end

local function fmtItems(t)
    if not t or #t == 0 then return '⬜ Nenhum item' end
    return string.format('✅ %d item(s)', #t)
end

local function isDataComplete()
    return editorData.key       and editorData.key ~= ''
       and editorData.ped_model and editorData.ped_model ~= ''
       and editorData.coords
       and editorData.ped_spawn
       and #editorData.ped_route  >= 1
       and #editorData.ped_route2 >= 1
       and #editorData.ped_route3 >= 1
       and editorData.take
       and #editorData.items >= 1
end

-- ─────────────────────────────────────────────────────────────────────────────
--  EDITOR START MENU  (Novo vs Editar)
-- ─────────────────────────────────────────────────────────────────────────────

OpenEditorStartMenu = function()
    local count = 0
    for _ in pairs(Restaurants) do count = count + 1 end

    lib.registerContext({
        id    = 'vcr_start_menu',
        title = '🍽️ VC-Restaurants Editor',
        options = {
            {
                title       = '🆕 Novo Restaurante',
                description = 'Criar um restaurante do zero',
                icon        = 'plus',
                onSelect    = function()
                    editorData = freshData()
                    isEditMode = false
                    OpenEditorMenu()
                end,
            },
            {
                title       = '✏️ Editar Existente',
                description = count > 0
                    and string.format('%d restaurante(s) disponíveis', count)
                    or  'Nenhum restaurante criado ainda',
                icon        = 'pen-to-square',
                disabled    = count == 0,
                onSelect    = function()
                    OpenRestaurantListMenu()
                end,
            },
        },
    })
    lib.showContext('vcr_start_menu')
end

-- ─────────────────────────────────────────────────────────────────────────────
--  RESTAURANT LIST MENU  (listar / editar / eliminar)
-- ─────────────────────────────────────────────────────────────────────────────

OpenRestaurantListMenu = function()
    local options = {
        {
            title    = '← Voltar',
            icon     = 'arrow-left',
            onSelect = function() OpenEditorStartMenu() end,
        },
    }

    local keys = {}
    for k in pairs(Restaurants) do keys[#keys + 1] = k end
    table.sort(keys)

    for _, key in ipairs(keys) do
        local r = Restaurants[key]
        local k = key
        options[#options + 1] = {
            title       = key,
            description = string.format(
                '%s  ·  %d item(s)  ·  %d+%d+%d pts rota',
                r.ped_model or '?',
                #(r.items or {}),
                #(r.ped_route or {}), #(r.ped_route2 or {}), #(r.ped_route3 or {})
            ),
            icon     = 'utensils',
            metadata = {
                { label = 'Coords',    value = fmtV3(r.coords)    },
                { label = 'Ped Model', value = r.ped_model or '?' },
                { label = 'Items',     value = #(r.items or {})   },
            },
            onSelect = function()
                lib.registerContext({
                    id    = 'vcr_list_action_' .. k,
                    title = '📋 ' .. k,
                    options = {
                        {
                            title    = '← Voltar à lista',
                            icon     = 'arrow-left',
                            onSelect = function() OpenRestaurantListMenu() end,
                        },
                        {
                            title       = '✏️ Editar',
                            description = 'Carregar dados para o editor',
                            icon        = 'pen-to-square',
                            onSelect    = function()
                                if LoadRestaurantIntoEditor(k) then
                                    isEditMode = true
                                    OpenEditorMenu()
                                else
                                    lib.notify({ description = 'Erro ao carregar restaurante.', type = 'error' })
                                    OpenRestaurantListMenu()
                                end
                            end,
                        },
                        {
                            title       = '🗑️ Eliminar',
                            description = 'Remove do ficheiro permanentemente',
                            icon        = 'trash',
                            iconColor   = '#e74c3c',
                            onSelect    = function()
                                local confirm = lib.alertDialog({
                                    header   = 'Eliminar Restaurante',
                                    content  = string.format(
                                        'Tens a certeza que queres eliminar **%s**?\n\nEsta ação é irreversível.', k),
                                    centered = true,
                                    cancel   = true,
                                    labels   = { confirm = 'Eliminar', cancel = 'Cancelar' },
                                })
                                if confirm == 'confirm' then
                                    TriggerServerEvent('vc_restaurants:server:deleteRestaurant', k)
                                    -- Remoção local imediata (servidor confirma via syncRestaurant)
                                    Restaurants[k] = nil
                                    OpenEditorStartMenu()
                                else
                                    OpenRestaurantListMenu()
                                end
                            end,
                        },
                    },
                })
                lib.showContext('vcr_list_action_' .. k)
            end,
        }
    end

    lib.registerContext({
        id      = 'vcr_restaurant_list',
        title   = '📋 Restaurantes Existentes',
        options = options,
    })
    lib.showContext('vcr_restaurant_list')
end

-- ─────────────────────────────────────────────────────────────────────────────
--  SPAWN MENU  (laser / ped / npc)
-- ─────────────────────────────────────────────────────────────────────────────

OpenSpawnMenu = function()
    lib.registerContext({
        id    = 'vcr_spawn_menu',
        title = '🚶 Spawn do NPC',
        options = {
            {
                title    = '← Voltar',
                icon     = 'arrow-left',
                onSelect = function() OpenEditorMenu() end,
            },
            {
                title       = 'Laser',
                description = 'Aponta para o chão e prime [E]',
                icon        = 'crosshairs',
                onSelect    = function()
                    CreateThread(function()
                        local coords = LaserPickSingle('SPAWN NPC', { r = 0, g = 200, b = 255, a = 200 })
                        if coords then
                            editorData.ped_spawn = vector4(coords.x, coords.y, coords.z, GetEntityHeading(PlayerPedId()))
                            lib.notify({ description = '✅ Spawn definido via laser.', type = 'success' })
                        end
                        OpenEditorMenu()
                    end)
                end,
            },
            {
                title       = 'Ped (posição do jogador)',
                description = 'Vai ao sítio pretendido e prime [ENTER]',
                icon        = 'person-walking',
                onSelect    = function()
                    CreateThread(function()
                        local coords, hdg = PedPickPosition()
                        if coords then
                            editorData.ped_spawn = vector4(coords.x, coords.y, coords.z, hdg)
                            lib.notify({ description = '✅ Spawn definido pela posição do jogador.', type = 'success' })
                        end
                        OpenEditorMenu()
                    end)
                end,
            },
            {
                title       = 'NPC Preview',
                description = 'Move um ped para a posição — ENTER confirma',
                icon        = 'user-gear',
                onSelect    = function()
                    CreateThread(function()
                        local coords, hdg = NpcPickPosition(editorData.ped_model)
                        if coords then
                            editorData.ped_spawn = vector4(coords.x, coords.y, coords.z, hdg)
                            lib.notify({ description = '✅ Spawn definido via NPC preview.', type = 'success' })
                        end
                        OpenEditorMenu()
                    end)
                end,
            },
        },
    })
    lib.showContext('vcr_spawn_menu')
end

-- ─────────────────────────────────────────────────────────────────────────────
--  ROUTE MENU  (multi-ponto · laser / ped / npc · preview · limpar)
-- ─────────────────────────────────────────────────────────────────────────────

OpenRouteMenu = function(routeKey, routeLabel)
    local route = editorData[routeKey]
    local color = { r = 255, g = 165, b = 0, a = 200 }

    local function RunAddLoop(method)
        CreateThread(function()
            while true do
                local pt = PickOnePoint(method, editorData.ped_model, color, #route + 1)
                if pt then
                    route[#route + 1] = pt
                    lib.notify({
                        description = string.format('Ponto %d adicionado ✅', #route),
                        type        = 'success',
                    })
                end

                local more = lib.alertDialog({
                    header   = routeLabel .. string.format(' (%d pontos)', #route),
                    content  = 'Adicionar mais um ponto?',
                    centered = true,
                    cancel   = true,
                    labels   = { confirm = 'Adicionar mais', cancel = 'Terminar' },
                })
                if more ~= 'confirm' then break end
            end
            OpenEditorMenu()
        end)
    end

    local options = {
        {
            title    = '← Voltar',
            icon     = 'arrow-left',
            onSelect = function() OpenEditorMenu() end,
        },
        {
            title       = 'Adicionar via Laser',
            description = 'Aponta para o chão e prime [E]',
            icon        = 'crosshairs',
            onSelect    = function() RunAddLoop('laser') end,
        },
        {
            title       = 'Adicionar via Ped (jogador)',
            description = 'Vai ao sítio e prime [ENTER]',
            icon        = 'person-walking',
            onSelect    = function() RunAddLoop('ped') end,
        },
        {
            title       = 'Adicionar via NPC Preview',
            description = 'Move ped para posição — ENTER confirma',
            icon        = 'user-gear',
            onSelect    = function() RunAddLoop('npc') end,
        },
    }

    if #route > 0 then
        options[#options + 1] = {
            title       = '▶️ Pré-visualizar Rota',
            description = string.format('%d pontos gravados', #route),
            icon        = 'play',
            onSelect    = function()
                CreateThread(function()
                    PreviewRoute(route, editorData.ped_model)
                    OpenRouteMenu(routeKey, routeLabel)
                end)
            end,
        }
        options[#options + 1] = {
            title       = '🗑️ Limpar Rota',
            description = 'Apaga todos os pontos desta rota',
            icon        = 'trash',
            iconColor   = '#e74c3c',
            onSelect    = function()
                local confirm = lib.alertDialog({
                    header   = 'Limpar ' .. routeLabel,
                    content  = string.format('Apagar os **%d pontos** desta rota?', #route),
                    centered = true,
                    cancel   = true,
                })
                if confirm == 'confirm' then
                    for i = #route, 1, -1 do route[i] = nil end
                    lib.notify({ description = routeLabel .. ' limpa ✅', type = 'inform' })
                end
                OpenEditorMenu()
            end,
        }
    end

    lib.registerContext({
        id      = 'vcr_route_' .. routeKey,
        title   = '🛤️ ' .. routeLabel,
        options = options,
    })
    lib.showContext('vcr_route_' .. routeKey)
end

-- ─────────────────────────────────────────────────────────────────────────────
--  ITEMS MENU
-- ─────────────────────────────────────────────────────────────────────────────

OpenItemsMenu = function()
    local options = {
        {
            title    = '← Voltar',
            icon     = 'arrow-left',
            onSelect = function() OpenEditorMenu() end,
        },
        {
            title       = '➕ Adicionar Item',
            description = 'Novo item para o menu do restaurante',
            icon        = 'plus',
            onSelect    = function()
                local input = lib.inputDialog('Novo Item', {
                    { type = 'input',  label = 'Nome (ox_inventory)',  required = true, placeholder = 'ex: burger'    },
                    { type = 'input',  label = 'Label visível',        required = true, placeholder = 'ex: Hamburger' },
                    { type = 'number', label = 'Preço ($)',            required = true, default = 10                  },
                })
                if input and input[1] and input[2] and input[3] then
                    editorData.items[#editorData.items + 1] = {
                        name  = input[1],
                        label = input[2],
                        price = tonumber(input[3]) or 0,
                    }
                    lib.notify({ description = '✅ Item "' .. input[2] .. '" adicionado.', type = 'success' })
                end
                OpenItemsMenu()
            end,
        },
    }

    for i, item in ipairs(editorData.items) do
        local idx    = i
        local iLabel = item.label
        local iName  = item.name
        local iPrice = item.price
        options[#options + 1] = {
            title       = iLabel,
            description = string.format('"%s"  ·  $%d', iName, iPrice),
            icon        = 'utensils',
            onSelect    = function()
                local action = lib.alertDialog({
                    header   = 'Item: ' .. iLabel,
                    content  = string.format('Nome: **%s**\nPreço: **$%d**\n\nEliminar este item?', iName, iPrice),
                    centered = true,
                    cancel   = true,
                    labels   = { confirm = 'Eliminar', cancel = 'Cancelar' },
                })
                if action == 'confirm' then
                    table.remove(editorData.items, idx)
                    lib.notify({ description = 'Item removido.', type = 'inform' })
                end
                OpenItemsMenu()
            end,
        }
    end

    lib.registerContext({
        id      = 'vcr_items_menu',
        title   = '🍔 Items do Menu',
        options = options,
    })
    lib.showContext('vcr_items_menu')
end

-- ─────────────────────────────────────────────────────────────────────────────
--  MAIN EDITOR CONTEXT MENU  (persistente — reflete o estado atual)
-- ─────────────────────────────────────────────────────────────────────────────

OpenEditorMenu = function()
    local complete = isDataComplete()
    local title    = isEditMode
        and ('✏️ Editar: ' .. (editorData.key or '?'))
        or  '🍽️ Novo Restaurante'

    lib.registerContext({
        id    = 'vcr_editor_main',
        title = title,
        options = {

            -- ── Chave (só editável em modo novo) ───────────────────────────
            {
                title       = '🔑 Chave do Restaurante',
                description = isEditMode
                    and (editorData.key .. '  (não alterável em modo edição)')
                    or  (editorData.key or '⬜ Não definido'),
                icon        = 'key',
                disabled    = isEditMode,
                onSelect    = function()
                    local input = lib.inputDialog('Chave do Restaurante', {
                        {
                            type        = 'input',
                            label       = 'Chave única (sem espaços)',
                            required    = true,
                            placeholder = 'ex: burger_shot_downtown',
                            default     = editorData.key,
                        },
                    })
                    if input and input[1] and input[1] ~= '' then
                        editorData.key = input[1]:gsub('%s+', '_'):lower()
                    end
                    OpenEditorMenu()
                end,
            },

            -- ── Modelo NPC ─────────────────────────────────────────────────
            {
                title       = '🧍 Modelo do NPC',
                description = editorData.ped_model or '⬜ Não definido',
                icon        = 'id-badge',
                onSelect    = function()
                    local input = lib.inputDialog('Modelo do NPC', {
                        {
                            type     = 'input',
                            label    = 'Nome do modelo',
                            required = true,
                            default  = editorData.ped_model or 'mp_m_shopkeep_01',
                        },
                    })
                    if input and input[1] and input[1] ~= '' then
                        editorData.ped_model = input[1]
                    end
                    OpenEditorMenu()
                end,
            },

            -- ── Coordenadas — laser ────────────────────────────────────────
            {
                title       = '📍 Coordenadas (referência)',
                description = fmtV3(editorData.coords),
                icon        = 'location-dot',
                onSelect    = function()
                    CreateThread(function()
                        local coords = LaserPickSingle('RESTAURANT COORDS', { r = 0, g = 180, b = 255, a = 200 })
                        if coords then
                            editorData.coords = vec3(coords.x, coords.y, coords.z)
                            lib.notify({ description = '✅ Coordenadas definidas.', type = 'success' })
                        end
                        OpenEditorMenu()
                    end)
                end,
            },

            -- ── Spawn NPC — submenu ────────────────────────────────────────
            {
                title       = '🚶 Spawn do NPC',
                description = fmtV4(editorData.ped_spawn),
                icon        = 'person-circle-plus',
                onSelect    = function() OpenSpawnMenu() end,
            },

            -- ── Routes ─────────────────────────────────────────────────────
            {
                title       = '🛤️ Route 1 — chegada à estação',
                description = fmtRoute(editorData.ped_route),
                icon        = 'route',
                onSelect    = function() OpenRouteMenu('ped_route', 'Route 1 — Chegada') end,
            },
            {
                title       = '🛤️ Route 2 — cozinha',
                description = fmtRoute(editorData.ped_route2),
                icon        = 'route',
                onSelect    = function() OpenRouteMenu('ped_route2', 'Route 2 — Cozinha') end,
            },
            {
                title       = '🛤️ Route 3 — entrega ao balcão',
                description = fmtRoute(editorData.ped_route3),
                icon        = 'route',
                onSelect    = function() OpenRouteMenu('ped_route3', 'Route 3 — Entrega') end,
            },

            -- ── Take — laser ───────────────────────────────────────────────
            {
                title       = '🎯 Take (posição do tabuleiro)',
                description = fmtV4(editorData.take),
                icon        = 'bullseye',
                onSelect    = function()
                    CreateThread(function()
                        local coords = LaserPickSingle('TRAY TAKE POSITION', { r = 255, g = 120, b = 0, a = 200 })
                        if coords then
                            editorData.take = vector4(coords.x, coords.y, coords.z, GetEntityHeading(PlayerPedId()))
                            lib.notify({ description = '✅ Take definido.', type = 'success' })
                        end
                        OpenEditorMenu()
                    end)
                end,
            },

            -- ── Items ──────────────────────────────────────────────────────
            {
                title       = '🍔 Items do Menu',
                description = fmtItems(editorData.items),
                icon        = 'utensils',
                onSelect    = function() OpenItemsMenu() end,
            },

            -- ── Guardar / Atualizar ────────────────────────────────────────
            {
                title = complete
                    and (isEditMode and '💾 Atualizar Restaurante' or '💾 Guardar Restaurante')
                    or  '💾 Guardar (campos em falta)',
                description = complete
                    and 'Todos os campos preenchidos — pronto a guardar.'
                    or  'Preenche todos os campos antes de guardar.',
                icon      = 'floppy-disk',
                iconColor = complete and '#27ae60' or '#7f8c8d',
                disabled  = not complete,
                onSelect  = function()
                    if not complete then return end
                    local action  = isEditMode and 'atualizar' or 'guardar'
                    local confirm = lib.alertDialog({
                        header   = isEditMode and 'Atualizar Restaurante' or 'Guardar Restaurante',
                        content  = string.format(
                            'Tens a certeza que queres **%s** o restaurante **%s**?\n\nEsta ação escreverá em `data/restaurants.lua`.',
                            action, editorData.key
                        ),
                        centered = true,
                        cancel   = true,
                        labels   = { confirm = isEditMode and 'Atualizar' or 'Guardar', cancel = 'Cancelar' },
                    })
                    if confirm == 'confirm' then
                        lib.notify({ description = '💾 A enviar dados ao servidor...', type = 'inform' })
                        TriggerServerEvent('vc_restaurants:server:saveRestaurant', editorData)
                        editorData   = freshData()
                        isEditMode   = false
                        editorActive = false
                    else
                        OpenEditorMenu()
                    end
                end,
            },

        },
    })
    lib.showContext('vcr_editor_main')
end

-- ─────────────────────────────────────────────────────────────────────────────
--  ENTRY POINT
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:client:startEditor', function()
    if editorActive then
        -- Reabre o menu atual se o jogador fechou com ESC
        if isEditMode or editorData.key then
            OpenEditorMenu()
        else
            OpenEditorStartMenu()
        end
        return
    end
    editorActive = true
    editorData   = freshData()
    isEditMode   = false
    OpenEditorStartMenu()
end)
