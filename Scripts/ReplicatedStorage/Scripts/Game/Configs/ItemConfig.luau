return {
    Data = {
        [1001] = {
            Id = 1001,
            Type = [[Ore]],
            MaxStack = 999,
            UseHandler = nil,
            HeldHandler = [[Ore]],
            NumberArray = nil,
            KVTable = nil
        },
        [1002] = {
            Id = 1002,
            Type = [[RawSword]],
            MaxStack = 1,
            UseHandler = nil,
            HeldHandler = [[Sword]],
            NumberArray = nil,
            KVTable = nil
        },
        [1003] = {
            Id = 1003,
            Type = [[ForgedSword]],
            MaxStack = 1,
            UseHandler = nil,
            HeldHandler = [[Sword]],
            NumberArray = nil,
            KVTable = nil
        }
    },
    Display = {
        [1001] = {
            Id = 1001,
            Name = [[Iron Ore]],
            Desc = [[Smelt ore into a raw sword at the public furnace.]],
            Quality = 1,
            IconId = [[rbxassetid://0]],
            DisplayModelId = nil
        },
        [1002] = {
            Id = 1002,
            Name = [[Raw Iron Sword]],
            Desc = [[Forge this raw sword at a forge station before placing it in your base.]],
            Quality = 1,
            IconId = [[rbxasset://Textures/Sword128.png]],
            DisplayModelId = [[Sword]]
        },
        [1003] = {
            Id = 1003,
            Name = [[Forged Iron Sword]],
            Desc = [[A finished sword. Place it in an unlocked base slot to earn coins.]],
            Quality = 1,
            IconId = [[rbxasset://Textures/Sword128.png]],
            DisplayModelId = [[Sword]]
        }
    },
    ExtraDataSchema = {
        Animal = {
            level = 1,
            mutationExp = 1,
            size = 1,
            sizeMutationPityCount = 0
        },
        ForgedSword = {
            Level = 1,
            StoredMoney = 0
        }
    }
}