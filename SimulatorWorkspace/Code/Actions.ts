import { BaseAction } from "@game-simulator/framework";
import type { BaseActionOptions, CurveValue, MacroActionBlocker } from "@game-simulator/framework";
import { calculateSlotUnlockPrice } from "./Formulas";
import type { ProjectConfig } from "./Main";
import type { State } from "./State";

type UnlockSlotPayload = { slotId: number };

export class UnlockSlotAction extends BaseAction<UnlockSlotPayload, State, ProjectConfig> {
  constructor(slotId: number, options: Omit<BaseActionOptions<UnlockSlotPayload>, "type" | "payload"> = {}) {
    super({ ...options, type: "unlockSlot", payload: { slotId } });
  }

  GetBlocker(): MacroActionBlocker | null {
    const slot = this.state.slots.find((item) => item.id === this.payload?.slotId);
    if (!slot) {
      return { kind: "slotNotFound", reason: "槽位不存在" };
    }
    if (slot.unlocked) {
      return { kind: "slotUnlocked", reason: "已解锁" };
    }
    const price = calculateSlotUnlockPrice(this.config.slotUnlockCurve as CurveValue, slot.id);
    if (this.state.money < price) {
      return { kind: "moneyNotEnough", reason: "金钱不足" };
    }
    return null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    const slot = this.state.slots.find((item) => item.id === this.payload?.slotId)!;
    this.state.money -= calculateSlotUnlockPrice(this.config.slotUnlockCurve as CurveValue, slot.id);
    slot.unlocked = true;
    return true;
  }
}

BaseAction.register("unlockSlot", (value) => new UnlockSlotAction(value.payload?.slotId as number, value));
