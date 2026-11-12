return {
    CommonConfig = {
        BaseInitialSlots = 5,
        BaseSlotsPerFloor = 10,
        BaseMaxFloors = 4,
        SwordInitialIncome = 10,
        SwordIncomePerLevel = 5,
        SwordUpgradePricePerLevel = 25,
        MiningRefreshInterval = 300,
        MiningSpawnCount = 8,
        MiningRockHits = 3,
        MiningSpawnProbability = 0.8,
        MiningOrePerHit = 1,
        MiningOreItemId = 1001,
        FurnaceOreCost = 5,
        FurnaceSwordItemId = 1002
    },
    BaseSlotData = {
        [1] = {
            SlotId = 1,
            UnlockPrice = 1
        },
        [2] = {
            SlotId = 2,
            UnlockPrice = 1
        },
        [3] = {
            SlotId = 3,
            UnlockPrice = 1
        },
        [4] = {
            SlotId = 4,
            UnlockPrice = 1
        },
        [5] = {
            SlotId = 5,
            UnlockPrice = 1
        },
        [6] = {
            SlotId = 6,
            UnlockPrice = 1
        },
        [7] = {
            SlotId = 7,
            UnlockPrice = 1
        },
        [8] = {
            SlotId = 8,
            UnlockPrice = 1
        },
        [9] = {
            SlotId = 9,
            UnlockPrice = 1
        },
        [10] = {
            SlotId = 10,
            UnlockPrice = 1
        },
        [11] = {
            SlotId = 11,
            UnlockPrice = 1
        },
        [12] = {
            SlotId = 12,
            UnlockPrice = 1
        },
        [13] = {
            SlotId = 13,
            UnlockPrice = 1
        },
        [14] = {
            SlotId = 14,
            UnlockPrice = 1
        },
        [15] = {
            SlotId = 15,
            UnlockPrice = 1
        },
        [16] = {
            SlotId = 16,
            UnlockPrice = 1
        },
        [17] = {
            SlotId = 17,
            UnlockPrice = 1
        },
        [18] = {
            SlotId = 18,
            UnlockPrice = 1
        },
        [19] = {
            SlotId = 19,
            UnlockPrice = 1
        },
        [20] = {
            SlotId = 20,
            UnlockPrice = 1
        },
        [21] = {
            SlotId = 21,
            UnlockPrice = 1
        },
        [22] = {
            SlotId = 22,
            UnlockPrice = 1
        },
        [23] = {
            SlotId = 23,
            UnlockPrice = 1
        },
        [24] = {
            SlotId = 24,
            UnlockPrice = 1
        },
        [25] = {
            SlotId = 25,
            UnlockPrice = 1
        },
        [26] = {
            SlotId = 26,
            UnlockPrice = 1
        },
        [27] = {
            SlotId = 27,
            UnlockPrice = 1
        },
        [28] = {
            SlotId = 28,
            UnlockPrice = 1
        },
        [29] = {
            SlotId = 29,
            UnlockPrice = 1
        },
        [30] = {
            SlotId = 30,
            UnlockPrice = 1
        },
        [31] = {
            SlotId = 31,
            UnlockPrice = 1
        },
        [32] = {
            SlotId = 32,
            UnlockPrice = 1
        },
        [33] = {
            SlotId = 33,
            UnlockPrice = 1
        },
        [34] = {
            SlotId = 34,
            UnlockPrice = 1
        },
        [35] = {
            SlotId = 35,
            UnlockPrice = 1
        },
        [36] = {
            SlotId = 36,
            UnlockPrice = 1
        },
        [37] = {
            SlotId = 37,
            UnlockPrice = 1
        },
        [38] = {
            SlotId = 38,
            UnlockPrice = 1
        },
        [39] = {
            SlotId = 39,
            UnlockPrice = 1
        },
        [40] = {
            SlotId = 40,
            UnlockPrice = 1
        }
    },
    MiningMutationData = {
        Normal = {
            Id = [[Normal]],
            Name = [[Normal]],
            Probability = 0.8,
            EffectPath = nil,
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1001,
            Luck = 1
        },
        Toxic = {
            Id = [[Toxic]],
            Name = [[Toxic]],
            Probability = 0.1,
            EffectPath = [[Assets.Effects.Aura.03_Toxic]],
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1101,
            Luck = 2
        },
        Frost = {
            Id = [[Frost]],
            Name = [[Frost]],
            Probability = 0.05,
            EffectPath = [[Assets.Effects.Aura.19_Frost]],
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1102,
            Luck = 3
        },
        Inferno = {
            Id = [[Inferno]],
            Name = [[Inferno]],
            Probability = 0.03,
            EffectPath = [[Assets.Effects.Aura.20_Inferno]],
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1103,
            Luck = 4
        },
        Storm = {
            Id = [[Storm]],
            Name = [[Storm]],
            Probability = 0.015,
            EffectPath = [[Assets.Effects.Aura.21_Storm]],
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1104,
            Luck = 5
        },
        Astral = {
            Id = [[Astral]],
            Name = [[Astral]],
            Probability = 0.005,
            EffectPath = [[Assets.Effects.Aura.25_Astral]],
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1105,
            Luck = 6
        }
    },
    MiningRockData = {
        [1] = {
            Id = 1,
            Name = [[Gray]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_01_Gray]],
            ModelScale = 0.4375,
            SpawnWeight = 40
        },
        [2] = {
            Id = 2,
            Name = [[Green]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_02_Green]],
            ModelScale = 0.4375,
            SpawnWeight = 25
        },
        [3] = {
            Id = 3,
            Name = [[Blue]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_03_Blue]],
            ModelScale = 0.4375,
            SpawnWeight = 15
        },
        [4] = {
            Id = 4,
            Name = [[Purple]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_04_Purple]],
            ModelScale = 0.4375,
            SpawnWeight = 10
        },
        [5] = {
            Id = 5,
            Name = [[Orange]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_05_Orange]],
            ModelScale = 0.4375,
            SpawnWeight = 6
        },
        [6] = {
            Id = 6,
            Name = [[Gold]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_06_Gold]],
            ModelScale = 0.4375,
            SpawnWeight = 3
        },
        [7] = {
            Id = 7,
            Name = [[Red]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_07_Red]],
            ModelScale = 0.4375,
            SpawnWeight = 1
        }
    }
}