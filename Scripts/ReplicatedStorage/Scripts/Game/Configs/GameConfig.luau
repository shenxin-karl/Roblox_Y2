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
        SwordBlankItemId = 1002,
        SwordSellIncomeSeconds = 60,
        OfflineMaxSeconds = 7200,
        GiftDistance = 15,
        SwordIncomeCoefficient = 1.2,
        OfflineDoubleClaimDiamondCost = 10
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
    MiningRockData = {
        [1] = {
            Id = 1,
            Name = [[Gray]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_01_Gray]],
            ModelScale = 0.4375,
            SpawnWeight = 40,
            MutationId = [[Normal]],
            MutationName = [[Normal]],
            EffectPath = nil,
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1001,
            IconId = nil,
            mutationMultiplier = 1
        },
        [2] = {
            Id = 2,
            Name = [[Green]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_02_Green]],
            ModelScale = 0.4375,
            SpawnWeight = 25,
            MutationId = [[Toxic]],
            MutationName = [[Toxic]],
            EffectPath = [[Assets.Effects.Aura.03_Toxic]],
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1101,
            IconId = [[rbxassetid://114769267589622]],
            mutationMultiplier = 1
        },
        [3] = {
            Id = 3,
            Name = [[Blue]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_03_Blue]],
            ModelScale = 0.4375,
            SpawnWeight = 15,
            MutationId = [[Frost]],
            MutationName = [[Frost]],
            EffectPath = [[Assets.Effects.Aura.19_Frost]],
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1102,
            IconId = [[rbxassetid://106224256982724]],
            mutationMultiplier = 1
        },
        [4] = {
            Id = 4,
            Name = [[Purple]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_04_Purple]],
            ModelScale = 0.4375,
            SpawnWeight = 10,
            MutationId = [[Inferno]],
            MutationName = [[Inferno]],
            EffectPath = [[Assets.Effects.Aura.20_Inferno]],
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1103,
            IconId = [[rbxassetid://131760910444430]],
            mutationMultiplier = 1
        },
        [5] = {
            Id = 5,
            Name = [[Orange]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_05_Orange]],
            ModelScale = 0.4375,
            SpawnWeight = 6,
            MutationId = [[Storm]],
            MutationName = [[Storm]],
            EffectPath = [[Assets.Effects.Aura.21_Storm]],
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1104,
            IconId = [[rbxassetid://120733919890929]],
            mutationMultiplier = 1
        },
        [6] = {
            Id = 6,
            Name = [[Gold]],
            ModelPath = [[Assets.Decorations.MiningRockGrades.CrystalGeode_06_Gold]],
            ModelScale = 0.4375,
            SpawnWeight = 3,
            MutationId = [[Astral]],
            MutationName = [[Astral]],
            EffectPath = [[Assets.Effects.Aura.25_Astral]],
            OreCountMultiplier = 1,
            HitsMultiplier = 1,
            OreItemId = 1105,
            IconId = [[rbxassetid://73900159742590]],
            mutationMultiplier = 1
        }
    },
    WeaponData = {
        [1] = {
            Quality = 1,
            Name = [[Wooden Practice Sword]],
            ModelPath = [[Assets.WeaponList.01_WoodenPracticeSword]],
            IconId = [[rbxassetid://130937278026319]],
            BlankIconId = [[rbxassetid://96678521412485]]
        },
        [2] = {
            Quality = 2,
            Name = [[Stone Shortsword]],
            ModelPath = [[Assets.WeaponList.02_StoneShortsword]],
            IconId = [[rbxassetid://108597490544442]],
            BlankIconId = [[rbxassetid://140395733177087]]
        },
        [3] = {
            Quality = 3,
            Name = [[Novice Iron Sword]],
            ModelPath = [[Assets.WeaponList.03_NoviceIronSword]],
            IconId = [[rbxassetid://72237625079956]],
            BlankIconId = [[rbxassetid://113257907492919]]
        },
        [4] = {
            Quality = 4,
            Name = [[Patched Blunt Sword]],
            ModelPath = [[Assets.WeaponList.04_PatchedBluntSword]],
            IconId = [[rbxassetid://125830210960773]],
            BlankIconId = [[rbxassetid://78665399328160]]
        },
        [5] = {
            Quality = 5,
            Name = [[Militia Longsword]],
            ModelPath = [[Assets.WeaponList.05_MilitiaLongsword]],
            IconId = [[rbxassetid://114045323972770]],
            BlankIconId = [[rbxassetid://111037772909305]]
        },
        [6] = {
            Quality = 6,
            Name = [[Bronze Shortblade]],
            ModelPath = [[Assets.WeaponList.06_BronzeShortblade]],
            IconId = [[rbxassetid://99330775612862]],
            BlankIconId = [[rbxassetid://135031860041077]]
        },
        [7] = {
            Quality = 7,
            Name = [[Riveted Iron Sword]],
            ModelPath = [[Assets.WeaponList.07_RivetedIronSword]],
            IconId = [[rbxassetid://131868171969550]],
            BlankIconId = [[rbxassetid://74377469145128]]
        },
        [8] = {
            Quality = 8,
            Name = [[Refined Steel Sword]],
            ModelPath = [[Assets.WeaponList.08_RefinedSteelSword]],
            IconId = [[rbxassetid://116034100288426]],
            BlankIconId = [[rbxassetid://111810489529461]]
        },
        [9] = {
            Quality = 9,
            Name = [[Hunters Curved Blade]],
            ModelPath = [[Assets.WeaponList.09_HuntersCurvedBlade]],
            IconId = [[rbxassetid://135969773394825]],
            BlankIconId = [[rbxassetid://85227427177134]]
        },
        [10] = {
            Quality = 10,
            Name = [[Rangers Sword]],
            ModelPath = [[Assets.WeaponList.10_RangersSword]],
            IconId = [[rbxassetid://125283606330778]],
            BlankIconId = [[rbxassetid://83397073320874]]
        },
        [11] = {
            Quality = 11,
            Name = [[Kingdom Standard Sword]],
            ModelPath = [[Assets.WeaponList.11_KingdomStandardSword]],
            IconId = [[rbxassetid://108326404150386]],
            BlankIconId = [[rbxassetid://99584243756137]]
        },
        [12] = {
            Quality = 12,
            Name = [[Clockwork Sword]],
            ModelPath = [[Assets.WeaponList.12_ClockworkSword]],
            IconId = [[rbxassetid://103953466062807]],
            BlankIconId = [[rbxassetid://120729783397373]]
        },
        [13] = {
            Quality = 13,
            Name = [[Knights Oath Sword]],
            ModelPath = [[Assets.WeaponList.13_KnightsOathSword]],
            IconId = [[rbxassetid://96537449126562]],
            BlankIconId = [[rbxassetid://130727081373059]]
        },
        [14] = {
            Quality = 14,
            Name = [[Silvermoon Rapier]],
            ModelPath = [[Assets.WeaponList.14_SilvermoonRapier]],
            IconId = [[rbxassetid://122953578656643]],
            BlankIconId = [[rbxassetid://76750158874969]]
        },
        [15] = {
            Quality = 15,
            Name = [[Coral Tide Sword]],
            ModelPath = [[Assets.WeaponList.15_CoralTideSword]],
            IconId = [[rbxassetid://102131029134524]],
            BlankIconId = [[rbxassetid://87845917691520]]
        },
        [16] = {
            Quality = 16,
            Name = [[Forest Guardian Sword]],
            ModelPath = [[Assets.WeaponList.16_ForestGuardianSword]],
            IconId = [[rbxassetid://117235351346762]],
            BlankIconId = [[rbxassetid://85151265096684]]
        },
        [17] = {
            Quality = 17,
            Name = [[Crimson Sigil Sword]],
            ModelPath = [[Assets.WeaponList.17_CrimsonSigilSword]],
            IconId = [[rbxassetid://98478818025954]],
            BlankIconId = [[rbxassetid://111099202295909]]
        },
        [18] = {
            Quality = 18,
            Name = [[Amber Honeycomb Sword]],
            ModelPath = [[Assets.WeaponList.18_AmberHoneycombSword]],
            IconId = [[rbxassetid://77482879723436]],
            BlankIconId = [[rbxassetid://122372759076247]]
        },
        [19] = {
            Quality = 19,
            Name = [[Dune Scimitar]],
            ModelPath = [[Assets.WeaponList.19_DuneScimitar]],
            IconId = [[rbxassetid://112295423717119]],
            BlankIconId = [[rbxassetid://129035355121745]]
        },
        [20] = {
            Quality = 20,
            Name = [[Peacock Brocade Sword]],
            ModelPath = [[Assets.WeaponList.20_PeacockBrocadeSword]],
            IconId = [[rbxassetid://134249709704975]],
            BlankIconId = [[rbxassetid://135148616048462]]
        },
        [21] = {
            Quality = 21,
            Name = [[Frostblade]],
            ModelPath = [[Assets.WeaponList.21_Frostblade]],
            IconId = [[rbxassetid://101055048406495]],
            BlankIconId = [[rbxassetid://72237470100220]]
        },
        [22] = {
            Quality = 22,
            Name = [[Thunder Knight Sword]],
            ModelPath = [[Assets.WeaponList.22_ThunderKnightSword]],
            IconId = [[rbxassetid://121825748470994]],
            BlankIconId = [[rbxassetid://112662123421959]]
        },
        [23] = {
            Quality = 23,
            Name = [[Red Lion Greatsword]],
            ModelPath = [[Assets.WeaponList.23_RedLionGreatsword]],
            IconId = [[rbxassetid://106748583820642]],
            BlankIconId = [[rbxassetid://76416175717276]]
        },
        [24] = {
            Quality = 24,
            Name = [[Molten Warblade]],
            ModelPath = [[Assets.WeaponList.24_MoltenWarblade]],
            IconId = [[rbxassetid://98047870388881]],
            BlankIconId = [[rbxassetid://89749434797042]]
        },
        [25] = {
            Quality = 25,
            Name = [[Starfall Crystal Blade]],
            ModelPath = [[Assets.WeaponList.25_StarfallCrystalBlade]],
            IconId = [[rbxassetid://86151138671766]],
            BlankIconId = [[rbxassetid://103814825043818]]
        },
        [26] = {
            Quality = 26,
            Name = [[Rift Sword]],
            ModelPath = [[Assets.WeaponList.26_RiftSword]],
            IconId = [[rbxassetid://111554858232315]],
            BlankIconId = [[rbxassetid://134077063643027]]
        },
        [27] = {
            Quality = 27,
            Name = [[Iron Fortress Siegebreaker]],
            ModelPath = [[Assets.WeaponList.27_IronFortressSiegebreaker]],
            IconId = [[rbxassetid://76092898026896]],
            BlankIconId = [[rbxassetid://108112621943105]]
        },
        [28] = {
            Quality = 28,
            Name = [[White Fang Earthsplitter]],
            ModelPath = [[Assets.WeaponList.28_WhiteFangEarthsplitter]],
            IconId = [[rbxassetid://103414728704722]],
            BlankIconId = [[rbxassetid://102653827969654]]
        },
        [29] = {
            Quality = 29,
            Name = [[Obsidian Dragonslayer]],
            ModelPath = [[Assets.WeaponList.29_ObsidianDragonslayer]],
            IconId = [[rbxassetid://87879843381923]],
            BlankIconId = [[rbxassetid://87077142789956]]
        },
        [30] = {
            Quality = 30,
            Name = [[Radiant Judgment Sword]],
            ModelPath = [[Assets.WeaponList.30_RadiantJudgmentSword]],
            IconId = [[rbxassetid://103588504050882]],
            BlankIconId = [[rbxassetid://138915073633193]]
        },
        [31] = {
            Quality = 31,
            Name = [[Crucible Reforged Sword]],
            ModelPath = [[Assets.WeaponList.31_CrucibleReforgedSword]],
            IconId = [[rbxassetid://109926671801450]],
            BlankIconId = [[rbxassetid://126930822468925]]
        },
        [32] = {
            Quality = 32,
            Name = [[Emerald Beetle King Sword]],
            ModelPath = [[Assets.WeaponList.32_EmeraldBeetleKingSword]],
            IconId = [[rbxassetid://88511767540141]],
            BlankIconId = [[rbxassetid://79438475650324]]
        },
        [33] = {
            Quality = 33,
            Name = [[Abyssal King Sword]],
            ModelPath = [[Assets.WeaponList.33_AbyssalKingSword]],
            IconId = [[rbxassetid://136604115713990]],
            BlankIconId = [[rbxassetid://115911305569036]]
        },
        [34] = {
            Quality = 34,
            Name = [[Dragon Emperors Inferno]],
            ModelPath = [[Assets.WeaponList.34_DragonEmperorsInferno]],
            IconId = [[rbxassetid://120990344165085]],
            BlankIconId = [[rbxassetid://97443905377469]]
        },
        [35] = {
            Quality = 35,
            Name = [[Deepsea Anchor Greatsword]],
            ModelPath = [[Assets.WeaponList.35_DeepseaAnchorGreatsword]],
            IconId = [[rbxassetid://95601433702588]],
            BlankIconId = [[rbxassetid://127584237683102]]
        },
        [36] = {
            Quality = 36,
            Name = [[Sun And Moon Sword]],
            ModelPath = [[Assets.WeaponList.36_SunAndMoonSword]],
            IconId = [[rbxassetid://92493992558823]],
            BlankIconId = [[rbxassetid://133573002382059]]
        },
        [37] = {
            Quality = 37,
            Name = [[Crimson Jade Mountain Sword]],
            ModelPath = [[Assets.WeaponList.37_CrimsonJadeMountainSword]],
            IconId = [[rbxassetid://70846185851636]],
            BlankIconId = [[rbxassetid://93979255139003]]
        },
        [38] = {
            Quality = 38,
            Name = [[Genesis Throne Sword]],
            ModelPath = [[Assets.WeaponList.38_GenesisThroneSword]],
            IconId = [[rbxassetid://95727474697037]],
            BlankIconId = [[rbxassetid://113379469940769]]
        },
        [39] = {
            Quality = 39,
            Name = [[Titan Crusher]],
            ModelPath = [[Assets.WeaponList.39_TitanCrusher]],
            IconId = [[rbxassetid://72675675283734]],
            BlankIconId = [[rbxassetid://101491370335443]]
        },
        [40] = {
            Quality = 40,
            Name = [[Worldsend Greatsword]],
            ModelPath = [[Assets.WeaponList.40_WorldsendGreatsword]],
            IconId = [[rbxassetid://84820570103940]],
            BlankIconId = [[rbxassetid://139685104058778]]
        }
    }
}