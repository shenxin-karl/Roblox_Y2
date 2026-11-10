import { sampleCurve } from "@game-simulator/framework";
import type { CurveValue } from "@game-simulator/framework";

/** 直接以目标槽位 ID 采样完整解锁曲线，返回展示和扣款共用的解锁价格。 */
export function calculateSlotUnlockPrice(curve: CurveValue, slotId: number): number {
  return sampleCurve(curve, slotId);
}
