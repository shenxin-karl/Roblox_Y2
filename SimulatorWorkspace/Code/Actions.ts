import { BaseAction, sampleCurve } from "@game-simulator/framework";
import type { BaseActionOptions, CurveValue, MacroActionBlocker } from "@game-simulator/framework";
import { calculateForgeProbabilities, calculateSlotUnlockPrice, calculateSwordUpgradePrice } from "./Formulas";
import type { ProjectConfig } from "./Main";
import type { ForgeResultState, MiningOreState, SlotState, State, SwordState } from "./State";

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

export class ForgeSwordAction extends BaseAction<Record<string, never>, State, ProjectConfig> {
  constructor(
    options: Omit<BaseActionOptions<Record<string, never>>, "type" | "payload"> = {},
    private readonly legacyAutoPlace = false,
  ) {
    super({ ...options, type: legacyAutoPlace ? "autoForgeSword" : "forgeSword" });
  }

  private getBestOre(): MiningOreState | undefined {
    return this.state.miningOres.reduce<MiningOreState | undefined>((best, ore) =>
      !best || ore.mutationId > best.mutationId || (ore.mutationId === best.mutationId && ore.id < best.id)
        ? ore : best, undefined);
  }

  GetBlocker(): MacroActionBlocker | null {
    if (this.state.oreCollectElapsedSeconds < this.config.oreCollectInterval) {
      return { kind: "collectCooldown", reason: "尚未到取矿时间" };
    }
    const ore = this.getBestOre();
    if (!ore) {
      return { kind: "oreNotFound", reason: "没有可获取的矿石" };
    }
    const input = this.config.miningMutationLuckCurve.input;
    if (!Number.isInteger(ore.mutationId) || ore.mutationId < (input.min ?? -Infinity) ||
        ore.mutationId > (input.max ?? Infinity)) {
      return { kind: "invalidMutation", reason: "矿石变异不在原料幸运曲线范围内" };
    }
    const luck = sampleCurve(this.config.miningMutationLuckCurve, ore.mutationId);
    if (!Number.isInteger(luck) || luck < 1 || !Number.isInteger(this.state.playerLuck) || this.state.playerLuck < 1) {
      return { kind: "invalidLuck", reason: "原料和人物幸运须为正整数" };
    }
    return null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    const ore = this.getBestOre()!;
    const materialLuck = sampleCurve(this.config.miningMutationLuckCurve, ore.mutationId);
    const playerLuck = this.state.playerLuck;
    let quality = playerLuck - 4;
    let hammerCount = 0;
    let outcome: ForgeResultState["outcome"] = "targetReached";
    while (quality < playerLuck + 1) {
      const probabilities = calculateForgeProbabilities(materialLuck, playerLuck, quality);
      const roll = this.rng.randomFloat01() * 100;
      hammerCount += 1;
      if (roll < probabilities.success) {
        quality += 1;
      } else if (roll < probabilities.success + probabilities.unchanged) {
        continue;
      } else if (roll < probabilities.success + probabilities.unchanged + probabilities.broken) {
        outcome = "broken";
        break;
      } else {
        outcome = "destroyed";
        break;
      }
    }

    this.state.miningOres.splice(this.state.miningOres.indexOf(ore), 1);
    this.state.oreCollectElapsedSeconds = 0;
    let swordId: number | null = null;
    let slotId: number | null = null;
    if (outcome !== "destroyed") {
      const sword: SwordState = {
        id: this.state.swords.reduce((max, item) => Math.max(max, item.id), 0) + 1,
        mutationId: ore.mutationId,
        luck: materialLuck,
        playerLuck,
        quality,
        level: 1,
      };
      this.state.swords.push(sword);
      swordId = sword.id;
      if (this.legacyAutoPlace) {
        slotId = this.placeLegacySword(sword);
      }
    }
    this.state.currentSwordId = swordId;
    this.state.lastForgeResult = {
      oreId: ore.id, mutationId: ore.mutationId, materialLuck, playerLuck, quality,
      hammerCount, outcome, swordId, slotId,
    };
    return true;
  }

  // 仅用于已有 autoForgeSword 时间线回放，新手动打造不自动放置。
  private placeLegacySword(sword: SwordState): number | null {
    let target: SlotState | undefined;
    let lowestQuality = Infinity;
    for (const slot of this.state.slots) {
      if (!slot.unlocked) {
        continue;
      }
      if (slot.swordId === null) {
        target = slot;
        break;
      }
      const equipped = this.state.swords.find((item) => item.id === slot.swordId)!;
      if (equipped.quality < lowestQuality) {
        target = slot;
        lowestQuality = equipped.quality;
      }
    }
    if (!target || (target.swordId !== null && sword.quality <= lowestQuality)) {
      return null;
    }
    const replacedSwordId = target.swordId;
    target.swordId = sword.id;
    if (replacedSwordId !== null) {
      this.state.swords = this.state.swords.filter((item) => item.id !== replacedSwordId);
    }
    return target.id;
  }
}

BaseAction.register("forgeSword", (value) => new ForgeSwordAction(value));
BaseAction.register("autoForgeSword", (value) => new ForgeSwordAction(value, true));

type PlaceSwordPayload = { swordId: number; slotId: number };

export class PlaceSwordAction extends BaseAction<PlaceSwordPayload, State, ProjectConfig> {
  constructor(swordId: number, slotId: number, options: Omit<BaseActionOptions<PlaceSwordPayload>, "type" | "payload"> = {}) {
    super({ ...options, type: "placeSword", payload: { swordId, slotId } });
  }

  GetBlocker(): MacroActionBlocker | null {
    if (!this.state.swords.some((sword) => sword.id === this.payload?.swordId)) {
      return { kind: "swordNotFound", reason: "没有当前武器，请先打造" };
    }
    if (this.state.slots.some((slot) => slot.swordId === this.payload?.swordId)) {
      return { kind: "swordAlreadyPlaced", reason: "该武器已放入槽位" };
    }
    const slot = this.state.slots.find((item) => item.id === this.payload?.slotId);
    if (!slot) {
      return { kind: "slotNotFound", reason: "请先选择槽位" };
    }
    if (!slot.unlocked) {
      return { kind: "slotLocked", reason: "槽位尚未解锁" };
    }
    return null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    const { swordId, slotId } = this.payload!;
    const slot = this.state.slots.find((item) => item.id === slotId)!;
    const replacedSwordId = slot.swordId;
    slot.swordId = swordId;
    if (replacedSwordId !== null) {
      this.state.swords = this.state.swords.filter((sword) => sword.id !== replacedSwordId);
    }
    this.state.currentSwordId = swordId;
    if (this.state.lastForgeResult?.swordId === swordId) {
      this.state.lastForgeResult.slotId = slotId;
    }
    return true;
  }
}

BaseAction.register("placeSword", (value) =>
  new PlaceSwordAction(value.payload?.swordId as number, value.payload?.slotId as number, value));

type UpgradeSwordPayload = { slotId: number };

export class UpgradeSwordAction extends BaseAction<UpgradeSwordPayload, State, ProjectConfig> {
  constructor(slotId: number, options: Omit<BaseActionOptions<UpgradeSwordPayload>, "type" | "payload"> = {}) {
    super({ ...options, type: "upgradeSword", payload: { slotId } });
  }

  GetBlocker(): MacroActionBlocker | null {
    const slot = this.state.slots.find((item) => item.id === this.payload?.slotId);
    if (!slot) {
      return { kind: "slotNotFound", reason: "请先选择槽位" };
    }
    if (!slot.unlocked) {
      return { kind: "slotLocked", reason: "槽位尚未解锁" };
    }
    const sword = this.state.swords.find((item) => item.id === slot.swordId);
    if (!sword) {
      return { kind: "swordNotPlaced", reason: "只能升级槽位内的武器" };
    }
    const input = this.config.swordUpgradeCurves.input;
    if (!Number.isInteger(sword.level) || sword.level < (input.min ?? 1)) {
      return { kind: "invalidSwordLevel", reason: "武器等级不在升级曲线范围内" };
    }
    if (sword.level + 1 > (input.max ?? Infinity)) {
      return { kind: "swordMaxLevel", reason: "武器已满级" };
    }
    const price = calculateSwordUpgradePrice(this.config.swordUpgradeCurves, sword.level);
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
    const sword = this.state.swords.find((item) => item.id === slot.swordId)!;
    this.state.money -= calculateSwordUpgradePrice(this.config.swordUpgradeCurves, sword.level);
    sword.level += 1;
    return true;
  }
}

BaseAction.register("upgradeSword", (value) => new UpgradeSwordAction(value.payload?.slotId as number, value));
