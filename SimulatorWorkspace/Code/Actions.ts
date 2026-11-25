import { BaseAction } from "@game-simulator/framework";
import type { BaseActionOptions, CurveValue, MacroActionBlocker } from "@game-simulator/framework";
import { calculateBaseIncome, calculateForgeProbabilities, calculatePlayerUpgradePrice, calculateSlotUnlockPrice, calculateSmeltingLuckDistribution, calculateSwordUpgradePlan, calculateSwordUpgradePrice, getNextPaidMultiplier, getPlayerUpgradeCurves, type PlayerUpgradeKind } from "./Formulas";
import type { ProjectConfig } from "./Main";
import type { ForgeResultState, MiningOreState, State, SwordState } from "./State";

type UnlockSlotPayload = { slotId: number };

export class InitializeMiningOresAction extends BaseAction<Record<string, never>, State, ProjectConfig> {
  constructor(options: Omit<BaseActionOptions<Record<string, never>>, "type" | "payload"> = {}) {
    super({ ...options, type: "initializeMiningOres" });
  }

  Apply(): boolean {
    if (this.state.miningRefreshElapsedSeconds >= 0) {
      return false;
    }
    this.state.refreshMiningOres();
    this.state.oreCollectElapsedSeconds = this.config.oreCollectInterval;
    return true;
  }
}

BaseAction.register("initializeMiningOres", (value) => new InitializeMiningOresAction(value));

export class RefreshMiningOresAction extends BaseAction<Record<string, never>, State, ProjectConfig> {
  constructor(options: Omit<BaseActionOptions<Record<string, never>>, "type" | "payload"> = {}) {
    super({ ...options, type: "refreshMiningOres" });
  }

  Apply(): boolean {
    this.state.refreshMiningOres();
    return true;
  }
}

BaseAction.register("refreshMiningOres", (value) => new RefreshMiningOresAction(value));

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

type ForgeSwordPayload = { slotId?: number };

export class ForgeSwordAction extends BaseAction<ForgeSwordPayload, State, ProjectConfig> {
  constructor(
    options: Omit<BaseActionOptions<ForgeSwordPayload>, "type" | "payload"> = {},
    slotId?: number,
  ) {
    super({
      ...options,
      type: slotId !== undefined ? "replaceSword" : "forgeSword",
      payload: slotId !== undefined ? { slotId } : undefined,
    });
  }

  private getBestOre(): MiningOreState | undefined {
    return this.state.miningOres.reduce<MiningOreState | undefined>((best, ore) =>
      !best || ore.mutationId > best.mutationId || (ore.mutationId === best.mutationId && ore.id < best.id)
        ? ore : best, undefined);
  }

  private getTargetOffset(): number {
    const slotId = this.payload?.slotId;
    if (slotId === undefined) {
      return 1;
    }
    return this.state.pendingReplacements.find((request) => request.slotId === slotId)?.targetOffset
      ?? this.state.forgeTargetOffset;
  }

  GetBlocker(): MacroActionBlocker | null {
    if (this.payload?.slotId !== undefined) {
      const slot = this.state.slots.find((item) => item.id === this.payload!.slotId);
      if (!slot) {
        return { kind: "slotNotFound", reason: "槽位不存在" };
      }
      if (!slot.unlocked) {
        return { kind: "slotLocked", reason: "槽位尚未解锁" };
      }
      const targetOffset = this.getTargetOffset();
      if (!Number.isInteger(targetOffset) || targetOffset < 1 || targetOffset > 4) {
        return { kind: "invalidForgeTarget", reason: "置换目标须为 +1～+4" };
      }
    }
    if (this.state.oreCollectElapsedSeconds < this.config.oreCollectInterval) {
      return { kind: "collectCooldown", reason: "尚未到取矿时间" };
    }
    const ore = this.getBestOre();
    if (!ore) {
      return { kind: "oreNotFound", reason: "没有可获取的矿石" };
    }
    const level = this.state.playerUpgradeLevels.smelting;
    const forgingLevel = this.state.playerUpgradeLevels.forging;
    if (!Number.isInteger(level) || level < 1 || !Number.isInteger(forgingLevel) || forgingLevel < 1) {
      return { kind: "invalidLuck", reason: "熔炼和锻造等级须为正整数" };
    }
    const distribution = calculateSmeltingLuckDistribution(this.config.smeltingLuckWeightCurve, level);
    const totalWeight = distribution.reduce((total, item) => total + item.weight, 0);
    if (distribution.some((item) => !Number.isFinite(item.weight) || item.weight < 0) ||
        !Number.isFinite(totalWeight) || totalWeight <= 0) {
      return { kind: "invalidSmeltingWeights", reason: "熔炼权重须为非负有限数，且总权重大于零" };
    }
    return null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    const ore = this.getBestOre()!;
    const distribution = calculateSmeltingLuckDistribution(this.config.smeltingLuckWeightCurve, this.state.playerUpgradeLevels.smelting);
    let rollWeight = this.rng.randomFloat01() * distribution.reduce((total, item) => total + item.weight, 0);
    let materialLuck = distribution[distribution.length - 1].luck;
    for (const item of distribution) {
      rollWeight -= item.weight;
      if (rollWeight < 0) {
        materialLuck = item.luck;
        break;
      }
    }
    const forgingLevel = this.state.playerUpgradeLevels.forging;
    const targetOffset = this.getTargetOffset();
    let quality = Math.max(1, forgingLevel - 4);
    let hammerCount = 0;
    let outcome: ForgeResultState["outcome"] = "targetReached";
    while (quality < forgingLevel + targetOffset) {
      const probabilities = calculateForgeProbabilities(materialLuck, forgingLevel, quality);
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
        playerLuck: forgingLevel,
        quality,
        level: 1,
      };
      this.state.swords.push(sword);
      swordId = sword.id;
      if (this.payload?.slotId !== undefined) {
        const target = this.state.slots.find((item) => item.id === this.payload!.slotId)!;
        const equipped = this.state.swords.find((item) => item.id === target.swordId);
        if (!equipped || sword.quality > equipped.quality) {
          target.swordId = sword.id;
          slotId = target.id;
          if (equipped) {
            this.state.swords = this.state.swords.filter((item) => item.id !== equipped.id);
          }
        }
      }
    }
    this.state.currentSwordId = swordId;
    this.state.lastForgeResult = {
      oreId: ore.id, mutationId: ore.mutationId, materialLuck, playerLuck: forgingLevel, quality,
      hammerCount, outcome, swordId, slotId,
    };
    return true;
  }

}

BaseAction.register("forgeSword", (value) => new ForgeSwordAction(value));

export class ReplaceSwordAction extends ForgeSwordAction {
  constructor(slotId: number, options: Omit<BaseActionOptions<ForgeSwordPayload>, "type" | "payload"> = {}) {
    super(options, slotId);
  }

  Apply(): boolean {
    if (!super.Apply()) {
      return false;
    }
    if (this.state.lastForgeResult?.slotId === this.payload!.slotId) {
      this.state.pendingReplacements = this.state.pendingReplacements.filter((request) => request.slotId !== this.payload!.slotId);
    }
    return true;
  }
}

BaseAction.register("replaceSword", (value) => new ReplaceSwordAction(value.payload?.slotId as number, value));

type SetForgeTargetPayload = { offset: number };

export class SetForgeTargetAction extends BaseAction<SetForgeTargetPayload, State, ProjectConfig> {
  constructor(offset: number, options: Omit<BaseActionOptions<SetForgeTargetPayload>, "type" | "payload"> = {}) {
    super({ ...options, type: "setForgeTarget", payload: { offset } });
  }

  GetBlocker(): MacroActionBlocker | null {
    const offset = this.payload?.offset;
    if (offset === undefined || !Number.isInteger(offset) || offset < 1 || offset > 4) {
      return { kind: "invalidForgeTarget", reason: "置换目标须为 +1～+4" };
    }
    if (this.state.forgeTargetOffset === offset) {
      return { kind: "forgeTargetSelected", reason: "已选中该目标" };
    }
    return null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    this.state.forgeTargetOffset = this.payload!.offset;
    return true;
  }
}

BaseAction.register("setForgeTarget", (value) => new SetForgeTargetAction(value.payload?.offset as number, value));

type QueueSwordReplacementPayload = { slotId: number; targetOffset?: number };

export class QueueSwordReplacementAction extends BaseAction<QueueSwordReplacementPayload, State, ProjectConfig> {
  constructor(slotId: number, targetOffset: number | undefined, options: Omit<BaseActionOptions<QueueSwordReplacementPayload>, "type" | "payload"> = {}) {
    super({ ...options, type: "queueSwordReplacement", payload: targetOffset === undefined ? { slotId } : { slotId, targetOffset } });
  }

  GetBlocker(): MacroActionBlocker | null {
    const slot = this.state.slots.find((item) => item.id === this.payload?.slotId);
    if (!slot) {
      return { kind: "slotNotFound", reason: "槽位不存在" };
    }
    if (!slot.unlocked) {
      return { kind: "slotLocked", reason: "槽位尚未解锁" };
    }
    if (this.state.pendingReplacements.some((request) => request.slotId === slot.id)) {
      return { kind: "replacementQueued", reason: "该槽位已加入置换队列" };
    }
    const targetOffset = this.payload?.targetOffset ?? this.state.forgeTargetOffset;
    if (!Number.isInteger(targetOffset) || targetOffset < 1 || targetOffset > 4) {
      return { kind: "invalidForgeTarget", reason: "置换目标须为 +1～+4" };
    }
    return null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    const { slotId, targetOffset = this.state.forgeTargetOffset } = this.payload!;
    this.state.pendingReplacements.push({ slotId, targetOffset });
    return true;
  }
}

BaseAction.register("queueSwordReplacement", (value) =>
  new QueueSwordReplacementAction(value.payload?.slotId as number, value.payload?.targetOffset as number | undefined, value));

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
  constructor(
    slotId: number,
    options: Omit<BaseActionOptions<UpgradeSwordPayload>, "type" | "payload"> = {},
    private readonly upgradeMax = false,
  ) {
    super({ ...options, type: upgradeMax ? "upgradeSwordMax" : "upgradeSword", payload: { slotId } });
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
    const plan = this.upgradeMax
      ? calculateSwordUpgradePlan(this.config.swordUpgradeCurves, sword.level, this.state.money)
      : { levels: 1, cost: calculateSwordUpgradePrice(this.config.swordUpgradeCurves, sword.level) };
    this.state.money -= plan.cost;
    sword.level += plan.levels;
    return true;
  }
}

BaseAction.register("upgradeSword", (value) => new UpgradeSwordAction(value.payload?.slotId as number, value));

export class UpgradeSwordMaxAction extends UpgradeSwordAction {
  constructor(slotId: number, options: Omit<BaseActionOptions<UpgradeSwordPayload>, "type" | "payload"> = {}) {
    super(slotId, options, true);
  }
}

BaseAction.register("upgradeSwordMax", (value) => new UpgradeSwordMaxAction(value.payload?.slotId as number, value));

type UpgradePlayerPayload = { kind: PlayerUpgradeKind };

export class UpgradePlayerAction extends BaseAction<UpgradePlayerPayload, State, ProjectConfig> {
  constructor(kind: PlayerUpgradeKind, options: Omit<BaseActionOptions<UpgradePlayerPayload>, "type" | "payload"> = {}) {
    super({ ...options, type: "upgradePlayer", payload: { kind } });
  }

  GetBlocker(): MacroActionBlocker | null {
    const kind = this.payload?.kind;
    if (kind !== "smelting" && kind !== "forging" && kind !== "income") {
      return { kind: "upgradeNotFound", reason: "升级项不存在" };
    }
    const level = this.state.playerUpgradeLevels[kind];
    const curves = getPlayerUpgradeCurves(this.config, kind);
    if (!Number.isInteger(level) || level < (curves.input.min ?? 1) || level > (curves.input.max ?? Infinity)) {
      return { kind: "invalidUpgradeLevel", reason: "玩家升级等级不在曲线范围内" };
    }
    if (level + 1 > (curves.input.max ?? Infinity)) {
      return { kind: "playerUpgradeMaxLevel", reason: "已满级" };
    }
    const order = ["income", "forging", "smelting"] as const;
    const levels = this.state.playerUpgradeLevels;
    const eligible = order.filter((item) => levels[item] < (getPlayerUpgradeCurves(this.config, item).input.max ?? Infinity));
    const roundLevel = Math.min(...eligible.map((item) => levels[item]));
    const next = eligible.find((item) => levels[item] === roundLevel)!;
    if (kind !== next) {
      const titles = { income: "收益倍率", forging: "武器锻造", smelting: "熔炼幸运" };
      return { kind: "playerUpgradeOrder", reason: `请先将${titles[next]}升至 ${roundLevel + 1} 级` };
    }
    if (this.state.money < calculatePlayerUpgradePrice(curves, level)) {
      return { kind: "moneyNotEnough", reason: "金钱不足" };
    }
    return null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    const kind = this.payload!.kind;
    const level = this.state.playerUpgradeLevels[kind];
    const curves = getPlayerUpgradeCurves(this.config, kind);
    this.state.money -= calculatePlayerUpgradePrice(curves, level);
    this.state.playerUpgradeLevels[kind] += 1;
    return true;
  }
}

BaseAction.register("upgradePlayer", (value) => new UpgradePlayerAction(value.payload?.kind as PlayerUpgradeKind, value));

type OfflineIncomePayload = { offlineSeconds: number };

export class ClaimOfflineIncomeAction extends BaseAction<OfflineIncomePayload, State, ProjectConfig> {
  constructor(offlineSeconds: number, options: Omit<BaseActionOptions<OfflineIncomePayload>, "type" | "payload"> = {}) {
    super({ ...options, type: "claimOfflineIncome", payload: { offlineSeconds } });
  }

  GetBlocker(): MacroActionBlocker | null {
    const seconds = this.payload?.offlineSeconds;
    return seconds === undefined || !Number.isInteger(seconds) || seconds <= 0
      ? { kind: "invalidOfflineDuration", reason: "没有有效离线时长" } : null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    this.state.money += calculateBaseIncome(
      this.config, this.state.slots, this.state.swords, this.state.playerUpgradeLevels.income, this.state.paidMultiplierTier,
    ) * this.payload!.offlineSeconds;
    return true;
  }
}

BaseAction.register("claimOfflineIncome", (value) =>
  new ClaimOfflineIncomeAction(value.payload?.offlineSeconds as number, value));

type DailyDiamondsPayload = { day: number };

export class ClaimDailyDiamondsAction extends BaseAction<DailyDiamondsPayload, State, ProjectConfig> {
  constructor(day: number, options: Omit<BaseActionOptions<DailyDiamondsPayload>, "type" | "payload"> = {}) {
    super({ ...options, type: "claimDailyDiamonds", payload: { day } });
  }

  GetBlocker(): MacroActionBlocker | null {
    const day = this.payload?.day;
    if (day === undefined || !Number.isInteger(day) || day < 1) {
      return { kind: "invalidRewardDay", reason: "钻石奖励日须为正整数" };
    }
    return day <= this.state.lastDiamondRewardDay
      ? { kind: "dailyDiamondsClaimed", reason: "当日钻石已赠送" } : null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    this.state.diamonds += this.config.dailyDiamondReward;
    this.state.lastDiamondRewardDay = this.payload!.day;
    return true;
  }
}

BaseAction.register("claimDailyDiamonds", (value) => new ClaimDailyDiamondsAction(value.payload?.day as number, value));

export class BuyPaidMultiplierAction extends BaseAction<Record<string, never>, State, ProjectConfig> {
  constructor(options: Omit<BaseActionOptions<Record<string, never>>, "type" | "payload"> = {}) {
    super({ ...options, type: "buyPaidMultiplier" });
  }

  GetBlocker(): MacroActionBlocker | null {
    const tier = this.state.paidMultiplierTier;
    const input = this.config.paidMultiplierCurves.input;
    if (!Number.isInteger(tier) || tier < input.min! || tier > input.max!) {
      return { kind: "invalidPaidMultiplierTier", reason: "付费倍率档位超出配置范围" };
    }
    const next = getNextPaidMultiplier(this.config, tier);
    if (!next) {
      return { kind: "paidMultiplierMaxTier", reason: "付费倍率已满档" };
    }
    return this.state.diamonds < next.price
      ? { kind: "diamondsNotEnough", reason: "钻石不足" } : null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    const next = getNextPaidMultiplier(this.config, this.state.paidMultiplierTier)!;
    this.state.diamonds -= next.price;
    this.state.paidMultiplierTier = next.tier;
    return true;
  }
}

BaseAction.register("buyPaidMultiplier", (value) => new BuyPaidMultiplierAction(value));

type AutoBuyPaidMultiplierPayload = { enabled: boolean };

export class SetAutoBuyPaidMultiplierAction extends BaseAction<AutoBuyPaidMultiplierPayload, State, ProjectConfig> {
  constructor(enabled: boolean, options: Omit<BaseActionOptions<AutoBuyPaidMultiplierPayload>, "type" | "payload"> = {}) {
    super({ ...options, type: "setAutoBuyPaidMultiplier", payload: { enabled } });
  }

  GetBlocker(): MacroActionBlocker | null {
    return typeof this.payload?.enabled !== "boolean" || this.payload.enabled === this.state.autoBuyPaidMultiplier
      ? { kind: "autoBuyUnchanged", reason: "自动购买状态未改变" } : null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    this.state.autoBuyPaidMultiplier = this.payload!.enabled;
    return true;
  }
}

BaseAction.register("setAutoBuyPaidMultiplier", (value) =>
  new SetAutoBuyPaidMultiplierAction(value.payload?.enabled as boolean, value));

type AutoUnlockSlotsPayload = { enabled: boolean };

export class SetAutoUnlockSlotsAction extends BaseAction<AutoUnlockSlotsPayload, State, ProjectConfig> {
  constructor(enabled: boolean, options: Omit<BaseActionOptions<AutoUnlockSlotsPayload>, "type" | "payload"> = {}) {
    super({ ...options, type: "setAutoUnlockSlots", payload: { enabled } });
  }

  GetBlocker(): MacroActionBlocker | null {
    return typeof this.payload?.enabled !== "boolean" || this.payload.enabled === this.state.autoUnlockSlots
      ? { kind: "autoUnlockUnchanged", reason: "自动解锁状态未改变" } : null;
  }

  Apply(): boolean {
    if (this.GetBlocker()) {
      return false;
    }
    this.state.autoUnlockSlots = this.payload!.enabled;
    return true;
  }
}

BaseAction.register("setAutoUnlockSlots", (value) =>
  new SetAutoUnlockSlotsAction(value.payload?.enabled as boolean, value));
