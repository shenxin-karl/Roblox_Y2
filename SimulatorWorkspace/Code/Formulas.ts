import { sampleCurve, sampleCurveGroupColumn } from "@game-simulator/framework";
import type { CurveGroupValue, CurveValue } from "@game-simulator/framework";
import type { ProjectConfig } from "./Main";
import type { SlotState, SwordState } from "./State";

export type PlayerUpgradeKind = "smelting" | "forging" | "income";

/** 按升级项读取费用曲线组；收益倍率升级额外包含效果列，不修改配置。 */
export function getPlayerUpgradeCurves(config: ProjectConfig, kind: PlayerUpgradeKind): CurveGroupValue {
  const keys = { smelting: "smeltingUpgradeCurves", forging: "forgingUpgradeCurves", income: "incomeUpgradeCurves" } as const;
  return config[keys[kind]];
}

/** 以当前玩家升级等级采样升一级费用，调用方先检查目标等级边界。 */
export function calculatePlayerUpgradePrice(curves: CurveGroupValue, level: number): number {
  return sampleCurveGroupColumn(curves, "upgradeCost", level);
}

/** 幸运升级固定每级增加 1，初始加值为 0；只有收益倍率效果从配置采样。 */
export function calculatePlayerUpgradeEffect(config: ProjectConfig, kind: PlayerUpgradeKind, level: number): number {
  return kind === "income" ? sampleCurveGroupColumn(config.incomeUpgradeCurves, "effect", level) : level - 1;
}

/** 按已购档位采样最终付费金币倍率，不连乘历史档位。 */
export function calculatePaidMultiplier(config: ProjectConfig, tier: number): number {
  return sampleCurveGroupColumn(config.paidMultiplierCurves, "multiplier", tier);
}

/** 返回下一档的最终倍率与本档钻石价格；达到上限后不再采样下一档。 */
export function getNextPaidMultiplier(config: ProjectConfig, tier: number): { tier: number; multiplier: number; price: number } | null {
  if (tier + 1 > config.paidMultiplierCurves.input.max!) {
    return null;
  }
  return {
    tier: tier + 1,
    multiplier: calculatePaidMultiplier(config, tier + 1),
    price: sampleCurveGroupColumn(config.paidMultiplierCurves, "diamondCost", tier + 1),
  };
}

/** 汇总已解锁槽位内武器的在线秒收益，付费倍率只作用于金币，未入槽武器不产出。 */
export function calculateBaseIncome(config: ProjectConfig, slots: readonly SlotState[], swords: readonly SwordState[], incomeLevel: number, paidMultiplierTier: number): number {
  const playerMultiplier = calculatePlayerUpgradeEffect(config, "income", incomeLevel);
  let income = 0;
  for (const slot of slots) {
    if (!slot.unlocked || slot.swordId === null) {
      continue;
    }
    const sword = swords.find((item) => item.id === slot.swordId);
    if (!sword) {
      continue;
    }
    income += sampleCurve(config.swordQualityIncomeCurve, sword.quality)
      * calculateSwordLevelMultiplier(config.swordUpgradeCurves, sword.level)
      * sampleCurve(config.swordMutationIncomeCurve, sword.mutationId)
      * playerMultiplier;
  }
  return income * calculatePaidMultiplier(config, paidMultiplierTier);
}

/** 直接以目标槽位 ID 采样完整解锁曲线，返回展示和扣款共用的解锁价格。 */
export function calculateSlotUnlockPrice(curve: CurveValue, slotId: number): number {
  return sampleCurve(curve, slotId);
}

/** 按成品武器当前等级采样升一级费用；目标等级边界由升级 Action 在采样前检查。 */
export function calculateSwordUpgradePrice(curves: CurveGroupValue, level: number): number {
  return sampleCurveGroupColumn(curves, "upgradeCost", level);
}

/** 按当前等级和金币逐档累计可购买的升级次数与总费用；不超过配置等级上限，不修改状态。 */
export function calculateSwordUpgradePlan(curves: CurveGroupValue, level: number, money: number): { levels: number; cost: number } {
  let levels = 0;
  let cost = 0;
  while (level + levels + 1 <= (curves.input.max ?? Infinity)) {
    const price = calculateSwordUpgradePrice(curves, level + levels);
    if (cost + price > money) {
      break;
    }
    cost += price;
    levels += 1;
  }
  return { levels, cost };
}

/** 按成品武器等级采样其等级倍率，不改变锻造品质。 */
export function calculateSwordLevelMultiplier(curves: CurveGroupValue, level: number): number {
  return sampleCurveGroupColumn(curves, "levelMultiplier", level);
}

export type ForgeProbabilities = { success: number; unchanged: number; broken: number; destroy: number };

/**
 * 按锻造设计计算单锤概率（百分数）。P 为人物幸运，W 为原料幸运；
 * 允许敲击的当前品质为 P-4～P+3；达到 P+4 后停止，好坏料修正冲 +1～+4 的成功和破损率。
 */
export function calculateForgeProbabilities(weaponLuck: number, playerLuck: number, quality: number): ForgeProbabilities {
  const offset = quality - playerLuck;
  if (!Number.isInteger(weaponLuck) || weaponLuck < 1 || !Number.isInteger(playerLuck) || playerLuck < 1 ||
      !Number.isInteger(offset) || offset < -4 || offset > 3) {
    throw new RangeError("原料和人物幸运须为正整数，当前品质须在 P-4～P+3 范围内");
  }
  const baseSuccess = [94, 93, 91, 88, 70, 50, 30, 10][offset + 4];
  const unchanged = [5, 5, 5, 5, 5, 15, 25, 40][offset + 4];
  const destroy = [0, 0, 0, 0, 3, 5, 10, 15][offset + 4];
  let success = baseSuccess;
  if (offset >= 0) {
    const difference = Math.max(-10, Math.min(10, weaponLuck - playerLuck));
    success = difference > 0
      ? Math.min(baseSuccess * (1 + 0.2 * difference), 100 - unchanged - destroy)
      : baseSuccess * (1 + 0.05 * difference);
  }
  return { success, unchanged, broken: 100 - unchanged - destroy - success, destroy };
}
