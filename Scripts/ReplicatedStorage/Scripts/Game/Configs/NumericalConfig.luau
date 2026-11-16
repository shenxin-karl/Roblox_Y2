return {
  initialUnlockedSlotCount = 5,
  slotUnlockCurve = {
    kind = "curve",
    input = {
      rounding = "none",
      min = 1,
      max = 36,
    },
    formula = {
      kind = "Power",
      base = 0,
      multiplier = {
        kind = "constant",
        value = 100,
      },
      power = {
        kind = "constant",
        value = 1,
      },
      rounding = "floor",
    },
  },
  miningRefreshInterval = 300,
  miningSpawnCount = 20,
  miningMutationProbabilityCurve = {
    weights = {
      5546,
      2496,
      1123,
      505,
      228,
      102,
    },
  },
  oreCollectInterval = 30,
  smeltingLuckWeightCurve = {
    kind = "curve",
    input = {
      rounding = "none",
      min = 0,
      max = 4,
    },
    formula = {
      kind = "Power",
      base = 0,
      multiplier = {
        kind = "linear",
        ranges = {
          {
            fromInput = 0,
            toInput = 0,
            fromValue = 10,
            toValue = 10,
          },
          {
            fromInput = 1,
            toInput = 1,
            fromValue = 20,
            toValue = 20,
          },
          {
            fromInput = 2,
            toInput = 2,
            fromValue = 40,
            toValue = 40,
          },
          {
            fromInput = 3,
            toInput = 3,
            fromValue = 20,
            toValue = 20,
          },
          {
            fromInput = 4,
            toInput = 4,
            fromValue = 10,
            toValue = 10,
          },
        },
      },
      power = {
        kind = "constant",
        value = 0,
      },
      rounding = "none",
    },
  },
  swordUpgradeCurves = {
    input = {
      rounding = "none",
      min = 1,
    },
    columns = {
      {
        key = "upgradeCost",
        formula = {
          kind = "Power",
          base = 0,
          multiplier = {
            kind = "constant",
            value = 25,
          },
          power = {
            kind = "constant",
            value = 1,
          },
          rounding = "floor",
        },
      },
      {
        key = "levelMultiplier",
        formula = {
          kind = "Power",
          base = 0.5,
          multiplier = {
            kind = "constant",
            value = 0.5,
          },
          power = {
            kind = "constant",
            value = 1,
          },
          rounding = "none",
        },
      },
    },
  },
  smeltingUpgradeCurves = {
    input = {
      rounding = "none",
      min = 1,
      max = 32,
    },
    columns = {
      {
        key = "upgradeCost",
        formula = {
          kind = "Power",
          base = 0,
          multiplier = {
            kind = "constant",
            value = 100,
          },
          power = {
            kind = "constant",
            value = 2,
          },
          rounding = "floor",
        },
      },
    },
  },
  forgingUpgradeCurves = {
    input = {
      rounding = "none",
      min = 1,
      max = 32,
    },
    columns = {
      {
        key = "upgradeCost",
        formula = {
          kind = "Power",
          base = 0,
          multiplier = {
            kind = "constant",
            value = 100,
          },
          power = {
            kind = "constant",
            value = 2,
          },
          rounding = "floor",
        },
      },
    },
  },
  incomeUpgradeCurves = {
    input = {
      rounding = "none",
      min = 1,
      max = 32,
    },
    columns = {
      {
        key = "upgradeCost",
        formula = {
          kind = "Power",
          base = 0,
          multiplier = {
            kind = "constant",
            value = 100,
          },
          power = {
            kind = "constant",
            value = 2,
          },
          rounding = "floor",
        },
      },
      {
        key = "effect",
        formula = {
          kind = "Power",
          base = 0.9,
          multiplier = {
            kind = "constant",
            value = 0.1,
          },
          power = {
            kind = "constant",
            value = 1,
          },
          rounding = "none",
        },
      },
    },
  },
  swordQualityIncomeCurve = {
    kind = "curve",
    input = {
      rounding = "none",
      min = 1,
      max = 36,
    },
    formula = {
      kind = "BaseExp",
      base = 0,
      multiplier = {
        kind = "constant",
        value = 1,
      },
      power = {
        kind = "constant",
        value = 1.2,
      },
      rounding = "none",
    },
  },
  swordMutationIncomeCurve = {
    kind = "curve",
    input = {
      rounding = "none",
      min = 1,
      max = 6,
    },
    formula = {
      kind = "Power",
      base = 1,
      multiplier = {
        kind = "constant",
        value = 0,
      },
      power = {
        kind = "constant",
        value = 1,
      },
      rounding = "none",
    },
  },
  initialDiamonds = 0,
  initialPaidMultiplierTier = 1,
  dailyDiamondReward = 28,
  paidMultiplierCurves = {
    input = {
      rounding = "none",
      min = 1,
      max = 11,
    },
    columns = {
      {
        key = "multiplier",
        formula = {
          kind = "BaseExp",
          base = 0,
          multiplier = {
            kind = "constant",
            value = 1,
          },
          power = {
            kind = "constant",
            value = 2,
          },
          rounding = "none",
        },
      },
      {
        key = "diamondCost",
        formula = {
          kind = "Power",
          base = 0,
          multiplier = {
            kind = "linear",
            ranges = {
              {
                fromInput = 1,
                toInput = 1,
                fromValue = 35,
                toValue = 35,
              },
              {
                fromInput = 2,
                toInput = 2,
                fromValue = 48,
                toValue = 48,
              },
              {
                fromInput = 3,
                toInput = 3,
                fromValue = 60,
                toValue = 60,
              },
              {
                fromInput = 4,
                toInput = 4,
                fromValue = 98,
                toValue = 98,
              },
              {
                fromInput = 5,
                toInput = 5,
                fromValue = 288,
                toValue = 288,
              },
              {
                fromInput = 6,
                toInput = 6,
                fromValue = 588,
                toValue = 588,
              },
              {
                fromInput = 7,
                toInput = 7,
                fromValue = 1188,
                toValue = 1188,
              },
              {
                fromInput = 8,
                toInput = 8,
                fromValue = 2688,
                toValue = 2688,
              },
              {
                fromInput = 9,
                toInput = 9,
                fromValue = 5688,
                toValue = 5688,
              },
              {
                fromInput = 10,
                toInput = 10,
                fromValue = 12888,
                toValue = 12888,
              },
              {
                fromInput = 11,
                toInput = 11,
                fromValue = 28888,
                toValue = 28888,
              },
            },
          },
          power = {
            kind = "constant",
            value = 0,
          },
          rounding = "none",
        },
      },
    },
  },
}
