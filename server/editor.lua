-- ─────────────────────────────────────────────────────────────────────────────
--  EDITOR — server side
-- ─────────────────────────────────────────────────────────────────────────────

local FILE_PATH   = 'data/restaurants.lua'
local FILE_HEADER = '-- AUTO-GENERATED — managed by vc_restaurants editor\n-- Do not edit by hand unless you know what you are doing.\nRestaurants = Restaurants or {}\n'

-- ─────────────────────────────────────────────────────────────────────────────
--  REGENERATE FILE  (reescreve o ficheiro completo a partir de Restaurants{})
--  Mais robusto do que append — funciona tanto para criar como para editar.
-- ─────────────────────────────────────────────────────────────────────────────

local function RegenerateFile()
    local content = FILE_HEADER
    for key, data in pairs(Restaurants) do
        local ok, block = pcall(FormatRestaurantEntry, key, data)
        if ok then
            content = content .. '\n' .. block .. '\n'
        else
            print('[VC-Restaurants] WARN: failed to serialize restaurant "' .. key .. '": ' .. tostring(block))
        end
    end
    return content
end

-- ─────────────────────────────────────────────────────────────────────────────
--  COMMAND  /criarrestaurante  (group.admin via ox_lib)
-- ─────────────────────────────────────────────────────────────────────────────

lib.addCommand('criarrestaurante', {
    help       = 'Abrir o editor de restaurantes',
    params     = {},
    restricted = 'group.admin',
}, function(source)
    TriggerClientEvent('vc_restaurants:client:startEditor', source)
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  SAVE RESTAURANT  (cria novo ou atualiza existente — baseado em data.key)
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:server:saveRestaurant', function(data)
    local src = source

    if not IsPlayerAceAllowed(src, Config.AdminAce) then
        TriggerClientEvent('ox_lib:notify', src, { description = 'Acesso negado.', type = 'error' })
        return
    end

    -- Validação básica
    if  not data
     or not data.key        or data.key == ''
     or not data.coords
     or not data.ped_model  or data.ped_model == ''
     or not data.ped_spawn
     or not data.ped_route  or #data.ped_route  < 1
     or not data.ped_route2 or #data.ped_route2 < 1
     or not data.ped_route3 or #data.ped_route3 < 1
     or not data.take
     or not data.items      or #data.items < 1
    then
        TriggerClientEvent('ox_lib:notify', src, {
            description = 'Dados inválidos — um ou mais campos obrigatórios em falta.',
            type        = 'error',
        })
        return
    end

    local isEdit = Restaurants[data.key] ~= nil

    -- Atualiza a tabela live
    Restaurants[data.key] = data

    -- Regenera o ficheiro completo
    local success = SaveResourceFile(GetCurrentResourceName(), FILE_PATH, RegenerateFile(), -1)

    if success then
        local action = isEdit and 'atualizado' or 'guardado'
        local block  = FormatRestaurantEntry(data.key, data)

        print(string.format('\n[VC-Restaurants] ✅ Restaurante %s: %s', action, data.key))
        print('──────── config block ────────')
        print(block)
        print('──────────────────────────────\n')

        -- Envia o bloco para o clipboard do admin
        TriggerClientEvent('vc_restaurants:client:copyToClipboard', src, block)

        -- Sincroniza Restaurants{} em TODOS os clientes (para que o editor mostre a entrada atualizada)
        TriggerClientEvent('vc_restaurants:client:syncRestaurant', -1, data.key, data)

        TriggerClientEvent('ox_lib:notify', src, {
            description = string.format('✅ Restaurante "%s" %s! Config copiado para o clipboard.', data.key, action),
            type        = 'success',
        })
    else
        print('[VC-Restaurants] ERROR: SaveResourceFile falhou para ' .. FILE_PATH)
        -- Reverter a tabela live em caso de erro de escrita
        if not isEdit then Restaurants[data.key] = nil end
        TriggerClientEvent('ox_lib:notify', src, {
            description = 'Servidor falhou ao escrever data/restaurants.lua — verifica permissões.',
            type        = 'error',
        })
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
--  DELETE RESTAURANT
-- ─────────────────────────────────────────────────────────────────────────────

RegisterNetEvent('vc_restaurants:server:deleteRestaurant', function(key)
    local src = source

    if not IsPlayerAceAllowed(src, Config.AdminAce) then
        TriggerClientEvent('ox_lib:notify', src, { description = 'Acesso negado.', type = 'error' })
        return
    end

    if not Restaurants[key] then
        TriggerClientEvent('ox_lib:notify', src, { description = 'Restaurante não encontrado.', type = 'error' })
        return
    end

    Restaurants[key] = nil

    local success = SaveResourceFile(GetCurrentResourceName(), FILE_PATH, RegenerateFile(), -1)

    if success then
        print('[VC-Restaurants] 🗑️ Restaurante eliminado: ' .. key)
        -- Sincroniza remoção em todos os clientes
        TriggerClientEvent('vc_restaurants:client:syncRestaurant', -1, key, nil)
        TriggerClientEvent('ox_lib:notify', src, {
            description = '🗑️ Restaurante "' .. key .. '" eliminado.',
            type        = 'success',
        })
    else
        print('[VC-Restaurants] ERROR: SaveResourceFile falhou ao eliminar ' .. key)
        TriggerClientEvent('ox_lib:notify', src, {
            description = 'Falhou ao escrever ficheiro — restaurante não eliminado.',
            type        = 'error',
        })
    end
end)
