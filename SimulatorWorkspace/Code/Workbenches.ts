import { WorkbenchSet, sampleCurveGroupColumn, type CurveValue } from "@game-simulator/framework";
import { calculatePlayerUpgradePrice, calculateSlotUnlockPrice } from "./Formulas";
import type { ProjectConfig } from "./Main";

export class ProjectWorkbenches extends WorkbenchSet {
  static WorkbenchNames = {
    workbenchPlayerUpgrade: "玩家升级",
  };

  workbenchPlayerUpgrade() {
    const config = this.config as ProjectConfig;
    const upgrades = [
      { id: "income", label: "收益倍率", configKey: "incomeUpgradeCurves" },
      { id: "forging", label: "武器锻造", configKey: "forgingUpgradeCurves" },
      { id: "smelting", label: "熔炼幸运", configKey: "smeltingUpgradeCurves" },
    ] as const;
    const upgradeInputs = upgrades.map(({ configKey }) => config[configKey].input);
    const slotInput = (config.slotUnlockCurve as CurveValue).input;

    return {
      variable: "level",
      rowLabel: "当前等级 / 槽位编号",
      minRow: Math.min(slotInput.min ?? 1, ...upgradeInputs.map(({ min }) => min ?? 1)),
      maxRow: Math.max(slotInput.max ?? 36, ...upgradeInputs.map(({ min = 1, max }) => max ?? Math.max(min, 32))),
      step: 1,
      editors: [...upgrades, { id: "slotUnlock", label: "槽位解锁", configKey: "slotUnlockCurve" }],
      columns: [
        ...upgrades.map(({ id, label, configKey }) => ({
          id: `${id}Cost`,
          label: `${label}升级费（金币）`,
          configTarget: { configKey, columnKey: "upgradeCost" },
          sample: (level: number) => {
            const curves = (this.config as ProjectConfig)[configKey];
            const { min = 1, max = Infinity } = curves.input;
            if (level < min || level > max) {
              return "";
            }
            return level < max ? calculatePlayerUpgradePrice(curves, level) : "满级";
          },
        })),
        {
          id: "incomeMultiplier",
          label: "玩家收益倍率",
          format: "multiplier" as const,
          configTarget: { configKey: "incomeUpgradeCurves", columnKey: "effect" },
          sample: (level: number) => {
            const curves = (this.config as ProjectConfig).incomeUpgradeCurves;
            const { min = 1, max = Infinity } = curves.input;
            return level >= min && level <= max ? sampleCurveGroupColumn(curves, "effect", level) : "";
          },
        },
        {
          id: "slotUnlockCost",
          label: "槽位解锁费（金币）",
          configTarget: { configKey: "slotUnlockCurve" },
          sample: (slotId: number) => {
            const config = this.config as ProjectConfig;
            const curve = config.slotUnlockCurve as CurveValue;
            const { min = 1, max = 36 } = curve.input;
            if (slotId < min || slotId > max) {
              return "";
            }
            return slotId - 1 < config.initialUnlockedSlotCount ? "初始解锁" : calculateSlotUnlockPrice(curve, slotId);
          },
        },
      ],
    };
  }
}
