local me_tools = {
    {
        name = "export_item",
        description = "Export items from the ME system to a specific direction",
        parameters = {
            items = "array of {name: string, count: number, nbt?: string, fingerprint?: string, tags?: string}",
            direction = "up|down|north|south|east|west|top|bottom|left|right|front|back"
        },
        example = '{"items": [{"name": "minecraft:iron_ingot", "count": 64}], "direction": "up"}'
    },
    {
        name = "import_item",
        description = "Import items into the ME system from a specific direction",
        parameters = {
            items = "array of {name: string, count: number, nbt?: string, fingerprint?: string, tags?: string}",
            direction = "up|down|north|south|east|west|top|bottom|left|right|front|back"
        },
        example = '{"items": [{"name": "minecraft:cobblestone", "count": 99999}], "direction": "north"}'
    },
    {
        name = "is_crafting",
        description = "Check if an item is currently being crafted",
        parameters = {
            item = "{name: string, nbt?: string, fingerprint?: string, tags?: string}",
            crafting_cpu = "optional CPU name"
        },
        example = '{"item": {"name": "minecraft:piston"}}'
    },
    {
        name = "craft_items",
        description = "Craft specified items, checks affordability and returns missing ingredients if needed",
        parameters = {
            items = "array of {name: string, count: number, nbt?: string, fingerprint?: string, tags?: string, crafting_cpu?: string}"
        },
        example = '{"items": [{"name": "minecraft:piston", "count": 64, "crafting_cpu": "main"}]}'
    },
    {
        name = "get_pattern_ingredients",
        description = "Get the ingredients required to craft a pattern item",
        parameters = {
            item = "{name: string, nbt?: string, fingerprint?: string, tags?: string}"
        },
        example = '{"item": {"name": "minecraft:cake"}}'
    },
    {
        name = "is_craft_affordable",
        description = "Check if an item is affordable to craft with current resources",
        parameters = {
            item = "{name: string, nbt?: string, fingerprint?: string, tags?: string}",
            amount = "optional number, default 1",
        },
        example = '{"item": {"name": "minecraft:diamond_pickaxe"}, "amount": 10}'
    }
}

return me_tools
