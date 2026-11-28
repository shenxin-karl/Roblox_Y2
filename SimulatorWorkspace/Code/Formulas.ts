import { sampleCurve, sampleCurveGroupColumn } from "@game-simulator/framework";
import type { CurveGroupValue, CurveValue } from "@game-simulator/framework";
import type { ProjectConfig } from "./Main";
import type { SlotState, State, SwordState } from "./State";

export type PlayerUpgradeKind = "smelting" | "forging" | "income";

/** 五档使用0～4索引采样权重，对应幸运偏移-2～+2；低于最低幸运的产出统一为1。 */
export function calculateSmeltingLuckDistribution(curve: CurveValue, level: number): { luck: number; weight: number }[] {
  return [-2, -1, 0, 1, 2].map((offset) => ({
    luck: Math.max(1, level + offset),
    weight: sampleCurve(curve, offset + 2),
  }));
}

/** 按升级项读取费用曲线组；收益倍率升级额外包含效果列，不修改配置。 */
export function getPlayerUpgradeCurves(config: ProjectConfig, kind: PlayerUpgradeKind): CurveGroupValue {
  const keys = { smelting: "smeltingUpgradeCurves", forging: "forgingUpgradeCurves", income: "incomeUpgradeCurves" } as const;
  return config[keys[kind]];
}

/** 以当前玩家升级等级采样升一级费用，调用方先检查目标等级边界。 */
export function calculatePlayerUpgradePrice(curves: CurveGroupValue, level: number): number {
  return sampleCurveGroupColumn(curves, "upgradeCost", level);
}

/** 用当前收益等级查配置，返回玩家金币收益倍率。 */
function calculateIncomeUpgradeMultiplier(config: ProjectConfig, level: number): number {
  return sampleCurveGroupColumn(config.incomeUpgradeCurves, "effect", level);
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

/** 按武器品质采样基础秒收益，作为武器升级计价基数。 */
export function calculateSwordQualityIncome(config: ProjectConfig, quality: number): number {
  return sampleCurve(config.swordQualityIncomeCurve, quality);
}

/** 用武器品质和变异 ID 计算基础秒收益，供置换比较及实际收益结算使用。 */
export function calculateSwordBaseIncome(config: ProjectConfig, quality: number, mutationId: number): number {
  return calculateSwordQualityIncome(config, quality)
    * sampleCurveGroupColumn(config.mutationCurves, "incomeMultiplier", mutationId);
}

/** 按武器品质、变异和当前全局倍率计算乘等级倍率前的秒收益，供升级回本计算使用。 */
export function calculateSwordIncomeBeforeLevel(config: ProjectConfig, sword: SwordState, state: Pick<State, "playerUpgradeLevels" | "paidMultiplierTier">): number {
  return calculateSwordBaseIncome(config, sword.quality, sword.mutationId)
    * calculateIncomeUpgradeMultiplier(config, state.playerUpgradeLevels.income)
    * calculatePaidMultiplier(config, state.paidMultiplierTier);
}

/** 汇总已解锁槽位内武器的在线秒收益，付费倍率只作用于金币，未入槽武器不产出。 */
export function calculateBaseIncome(config: ProjectConfig, slots: readonly SlotState[], swords: readonly SwordState[], incomeLevel: number, paidMultiplierTier: number): number {
  const playerMultiplier = calculateIncomeUpgradeMultiplier(config, incomeLevel);
  let income = 0;
  for (const slot of slots) {
    if (!slot.unlocked || slot.swordId === null) {
      continue;
    }
    const sword = swords.find((item) => item.id === slot.swordId);
    if (!sword) {
      continue;
    }
    income += calculateSwordBaseIncome(config, sword.quality, sword.mutationId)
      * calculateSwordLevelMultiplier(config.swordUpgradeCurves, sword.level)
      * playerMultiplier;
  }
  return income * calculatePaidMultiplier(config, paidMultiplierTier);
}

/** 直接以目标槽位 ID 采样完整解锁曲线，返回展示和扣款共用的解锁价格。 */
export function calculateSlotUnlockPrice(curve: CurveValue, slotId: number): number {
  return sampleCurve(curve, slotId);
}

/** 品质基础秒收益乘当前等级的消耗倍率后向下取整，每级至少 1 金币。 */
export function calculateSwordUpgradePrice(curves: CurveGroupValue, level: number, qualityIncome: number): number {
  return Math.max(1, Math.floor(qualityIncome * sampleCurveGroupColumn(curves, "upgradeCost", level)));
}

/** 按品质基础秒收益和余额逐档规划升级，遵守配置上限和本次目标等级。 */
export function calculateSwordUpgradePlan(curves: CurveGroupValue, level: number, money: number, qualityIncome: number, targetLevel = Infinity): { levels: number; cost: number } {
  const maxLevel = Math.min(curves.input.max ?? Infinity, targetLevel);
  let levels = 0;
  let cost = 0;
  while (level + levels + 1 <= maxLevel) {
    const price = calculateSwordUpgradePrice(curves, level + levels, qualityIncome);
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
 * 按锻造设计计算单锤概率（百分数）。P 为当前锻造等级，W 为原料幸运；
 * 允许敲击的当前品质为 P-4～P+3；达到 P+4 后停止，好坏料修正冲 +1～+4 的成功和破损率。
 */
export function calculateForgeProbabilities(weaponLuck: number, forgingLevel: number, quality: number): ForgeProbabilities {
  const offset = quality - forgingLevel;
  if (!Number.isInteger(weaponLuck) || weaponLuck < 1 || !Number.isInteger(forgingLevel) || forgingLevel < 1 ||
      !Number.isInteger(offset) || offset < -4 || offset > 3) {
    throw new RangeError("原料幸运和锻造等级须为正整数，当前品质须在 P-4～P+3 范围内");
  }
  const baseSuccess = [94, 93, 91, 88, 70, 50, 30, 10][offset + 4];
  const unchanged = [5, 5, 5, 5, 5, 15, 25, 40][offset + 4];
  const destroy = [0, 0, 0, 0, 3, 5, 10, 15][offset + 4];
  let success = baseSuccess;
  if (offset >= 0) {
    const difference = Math.max(-10, Math.min(10, weaponLuck - forgingLevel));
    success = difference > 0
      ? Math.min(baseSuccess * (1 + 0.2 * difference), 100 - unchanged - destroy)
      : baseSuccess * (1 + 0.05 * difference);
  }
  return { success, unchanged, broken: 100 - unchanged - destroy - success, destroy };
}
