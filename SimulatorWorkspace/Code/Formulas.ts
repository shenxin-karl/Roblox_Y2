import { sampleCurve, sampleCurveGroupColumn } from "@game-simulator/framework";
import type { CurveGroupValue, CurveValue } from "@game-simulator/framework";

/** 直接以目标槽位 ID 采样完整解锁曲线，返回展示和扣款共用的解锁价格。 */
export function calculateSlotUnlockPrice(curve: CurveValue, slotId: number): number {
  return sampleCurve(curve, slotId);
}

/** 按成品武器当前等级采样升一级费用；目标等级边界由升级 Action 在采样前检查。 */
export function calculateSwordUpgradePrice(curves: CurveGroupValue, level: number): number {
  return sampleCurveGroupColumn(curves, "upgradeCost", level);
}

/** 按成品武器等级采样其等级倍率，不改变锻造品质。 */
export function calculateSwordLevelMultiplier(curves: CurveGroupValue, level: number): number {
  return sampleCurveGroupColumn(curves, "levelMultiplier", level);
}

export type ForgeProbabilities = { success: number; unchanged: number; broken: number; destroy: number };

/**
 * 按锻造设计计算单锤概率（百分数）。P 为人物幸运，W 为原料幸运；
 * 本轮只打造到 P+1，允许敲击的当前品质为 P-4～P，好坏料只修正冲 +1 的成功和破损率。
 */
export function calculateForgeProbabilities(weaponLuck: number, playerLuck: number, quality: number): ForgeProbabilities {
  const offset = quality - playerLuck;
  if (!Number.isInteger(weaponLuck) || weaponLuck < 1 || !Number.isInteger(playerLuck) || playerLuck < 1 ||
      !Number.isInteger(offset) || offset < -4 || offset > 0) {
    throw new RangeError("原料和人物幸运须为正整数，当前品质须在 P-4～P 范围内");
  }
  const baseSuccess = [94, 93, 91, 88, 70][offset + 4];
  const unchanged = 5;
  const destroy = offset === 0 ? 3 : 0;
  let success = baseSuccess;
  if (offset === 0) {
    const difference = Math.max(-10, Math.min(10, weaponLuck - playerLuck));
    success = difference > 0
      ? Math.min(baseSuccess * (1 + 0.2 * difference), 100 - unchanged - destroy)
      : baseSuccess * (1 + 0.05 * difference);
  }
  return { success, unchanged, broken: 100 - unchanged - destroy - success, destroy };
}
