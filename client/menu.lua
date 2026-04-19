-- ox_lib context menu — replaces legacy ESX.UI.Menu

function OpenRestaurantMenu(restaurantKey)
    local resto = Restaurants[restaurantKey]
    if not resto then return end

    local options = {}

    if #resto.items > 0 then
        for _, item in ipairs(resto.items) do
            local itemSnap = item  -- local copy to avoid closure capture issues
            options[#options + 1] = {
                title       = itemSnap.label,
                description = '$' .. itemSnap.price,
                icon        = 'utensils',
                onSelect    = function()
                    ConfirmOrder(restaurantKey, itemSnap)
                end
            }
        end
    else
        options[#options + 1] = {
            title    = 'No items available',
            disabled = true
        }
    end

    lib.registerContext({
        id      = 'vc_restaurant_menu',
        title   = '🍽️ Restaurant Menu',
        options = options
    })
    lib.showContext('vc_restaurant_menu')
end

function ConfirmOrder(restaurantKey, item)
    local confirmed = lib.alertDialog({
        header   = 'Confirm Order',
        content  = string.format('**%s** — $%d\n\nConfirm this order?', item.label, item.price),
        centered = true,
        cancel   = true
    })
    if confirmed == 'confirm' then
        lib.notify({ description = Config.Locales.Preparing, type = 'inform' })
        TriggerServerEvent('vc_restaurants:server:buyItem',
            restaurantKey,
            item.name,
            item.price,
            NetworkGetNetworkIdFromEntity(LocalPlayer.state.ped))
    end
end
