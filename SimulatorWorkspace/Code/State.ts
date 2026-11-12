import { State as BaseState } from "@game-simulator/framework";
import type { ProjectConfig } from "./Main";
import { calculateBaseIncome, type PlayerUpgradeKind } from "./Formulas";

export type SlotState = { id: number; unlocked: boolean; swordId: number | null };
export type MiningOreState = { id: number; mutationId: number };
export type SwordState = { id: number; mutationId: number; luck: number; playerLuck: number; quality: number; level: number };
export type ForgeResultState = {
  oreId: number;
  mutationId: number;
  materialLuck: number;
  playerLuck: number;
  quality: number;
  hammerCount: number;
  outcome: "targetReached" | "broken" | "destroyed";
  swordId: number | null;
  slotId: number | null;
};

export type StateValues = {
  money: number;
  slots: SlotState[];
  miningOres: MiningOreState[];
  miningRefreshElapsedSeconds: number;
  oreCollectElapsedSeconds: number;
  playerLuck: number;
  swords: SwordState[];
  currentSwordId: number | null;
  lastForgeResult: ForgeResultState | null;
  pendingReplacementSlotIds: number[];
  playerUpgradeLevels: Record<PlayerUpgradeKind, number>;
  forgeTargetOffset: number;
  diamonds: number;
  paidMultiplierTier: number;
  lastDiamondRewardDay: number;
  autoBuyPaidMultiplier: boolean;
};

export class State extends BaseState<StateValues> {
  slots: SlotState[];
  money = 0;
  miningOres: MiningOreState[] = [];
  miningRefreshElapsedSeconds = -1;
  oreCollectElapsedSeconds = 0;
  playerLuck = 1;
  swords: SwordState[] = [];
  currentSwordId: number | null = null;
  lastForgeResult: ForgeResultState | null = null;
  pendingReplacementSlotIds: number[] = [];
  playerUpgradeLevels: Record<PlayerUpgradeKind, number> = { smelting: 1, forging: 1, income: 1 };
  forgeTargetOffset = 1;
  diamonds: number;
  paidMultiplierTier: number;
  lastDiamondRewardDay = 0;
  autoBuyPaidMultiplier = false;

  constructor(
    private readonly initialUnlockedSlotCount: number,
    private readonly initialDiamonds: number,
    private readonly initialPaidMultiplierTier: number,
  ) {
    super();
    this.diamonds = initialDiamonds;
    this.paidMultiplierTier = initialPaidMultiplierTier;
    this.slots = Array.from({ length: 30 }, (_, index) => ({
      id: index + 1,
      unlocked: index < initialUnlockedSlotCount,
      swordId: null,
    }));
  }

  getSummary(): string {
    return `金钱：${this.money.toFixed(2)}，钻石：${this.diamonds}，付费倍率档位：${this.paidMultiplierTier}，槽位：${this.slots.length}，矿石：${this.miningOres.length}，武器：${this.swords.length}，刷新计时：${this.miningRefreshElapsedSeconds}秒，待置换：${this.pendingReplacementSlotIds.length}，置换目标：+${this.forgeTargetOffset}，玩家升级：${this.playerUpgradeLevels.smelting}/${this.playerUpgradeLevels.forging}/${this.playerUpgradeLevels.income}`;
  }

  getFieldDisplayNames(): Record<string, string> {
    return {
      money: "金钱",
      diamonds: "当前钻石",
      paidMultiplierTier: "已购付费倍率档位",
      lastDiamondRewardDay: "最近赠送钻石的模拟日",
      autoBuyPaidMultiplier: "自动购买付费倍率",
      slots: "槽位",
      "slots[].id": "槽位 ID",
      "slots[].unlocked": "已解锁",
      "slots[].swordId": "已放置武器 ID",
      miningOres: "当前矿石",
      "miningOres[].id": "矿石 ID",
      "miningOres[].mutationId": "变异 ID",
      miningRefreshElapsedSeconds: "矿石刷新已过秒数",
      oreCollectElapsedSeconds: "打造取矿冷却已过秒数",
      playerLuck: "人物幸运 P",
      forgeTargetOffset: "一键置换目标品质偏移",
      playerUpgradeLevels: "玩家升级等级",
      "playerUpgradeLevels.smelting": "熔炼幸运等级",
      "playerUpgradeLevels.forging": "武器锻造等级",
      "playerUpgradeLevels.income": "收益倍率等级",
      swords: "全部成品武器",
      "swords[].id": "武器 ID",
      "swords[].mutationId": "继承变异 ID",
      "swords[].luck": "原料幸运 W",
      "swords[].playerLuck": "打造时人物幸运 P",
      "swords[].quality": "武器品质 Q",
      "swords[].level": "成品武器等级",
      currentSwordId: "当前展示武器 ID",
      lastForgeResult: "最近一次打造",
      pendingReplacementSlotIds: "待置换槽位队列",
      "lastForgeResult.oreId": "消耗矿石 ID",
      "lastForgeResult.mutationId": "继承变异 ID",
      "lastForgeResult.materialLuck": "原料幸运 W",
      "lastForgeResult.playerLuck": "人物幸运 P",
      "lastForgeResult.quality": "结束品质 Q",
      "lastForgeResult.hammerCount": "敲击次数",
      "lastForgeResult.outcome": "出炉结果",
      "lastForgeResult.swordId": "成品武器 ID",
      "lastForgeResult.slotId": "放置槽位 ID",
    };
  }

  toJSON(): StateValues {
    return {
      money: this.money,
      diamonds: this.diamonds,
      paidMultiplierTier: this.paidMultiplierTier,
      lastDiamondRewardDay: this.lastDiamondRewardDay,
      autoBuyPaidMultiplier: this.autoBuyPaidMultiplier,
      slots: this.slots.map((slot) => ({ ...slot })),
      miningOres: this.miningOres.map((ore) => ({ ...ore })),
      miningRefreshElapsedSeconds: this.miningRefreshElapsedSeconds,
      oreCollectElapsedSeconds: this.oreCollectElapsedSeconds,
      playerLuck: this.playerLuck,
      swords: this.swords.map((sword) => ({ ...sword })),
      currentSwordId: this.currentSwordId,
      lastForgeResult: this.lastForgeResult ? { ...this.lastForgeResult } : null,
      pendingReplacementSlotIds: [...this.pendingReplacementSlotIds],
      playerUpgradeLevels: { ...this.playerUpgradeLevels },
      forgeTargetOffset: this.forgeTargetOffset,
    };
  }

  loadJSON(values: StateValues): void {
    this.money = values.money ?? 0;
    this.diamonds = values.diamonds ?? this.initialDiamonds;
    this.paidMultiplierTier = values.paidMultiplierTier ?? this.initialPaidMultiplierTier;
    this.lastDiamondRewardDay = values.lastDiamondRewardDay ?? 0;
    this.autoBuyPaidMultiplier = values.autoBuyPaidMultiplier ?? false;
    this.slots = values.slots.map((slot) => ({
      id: slot.id,
      unlocked: slot.unlocked ?? slot.id <= this.initialUnlockedSlotCount,
      swordId: slot.swordId ?? null,
    }));
    this.miningOres = (values.miningOres ?? []).map((ore) => ({ ...ore }));
    this.miningRefreshElapsedSeconds = values.miningRefreshElapsedSeconds ?? 0;
    this.oreCollectElapsedSeconds = values.oreCollectElapsedSeconds ?? 0;
    this.playerLuck = values.playerLuck ?? 1;
    this.swords = (values.swords ?? []).map((sword) => ({ ...sword, level: sword.level ?? 1 }));
    this.currentSwordId = values.currentSwordId ?? null;
    this.lastForgeResult = values.lastForgeResult ? { ...values.lastForgeResult } : null;
    this.pendingReplacementSlotIds = [...(values.pendingReplacementSlotIds ?? [])];
    this.playerUpgradeLevels = {
      smelting: values.playerUpgradeLevels?.smelting ?? 1,
      forging: values.playerUpgradeLevels?.forging ?? 1,
      income: values.playerUpgradeLevels?.income ?? 1,
    };
    this.forgeTargetOffset = values.forgeTargetOffset ?? 1;
  }

  advanceOneSecond(): void {
    const config = this.config as ProjectConfig;
    this.money += calculateBaseIncome(config, this.slots, this.swords, this.playerUpgradeLevels.income, this.paidMultiplierTier);
    this.oreCollectElapsedSeconds = Math.min(this.oreCollectElapsedSeconds + 1, config.oreCollectInterval);
    this.miningRefreshElapsedSeconds += 1;
    if (this.miningRefreshElapsedSeconds < config.miningRefreshInterval) {
      return;
    }
    this.refreshMiningOres();
  }

  refreshMiningOres(): void {
    const config = this.config as ProjectConfig;
    this.miningOres = Array.from({ length: config.miningSpawnCount }, (_, index) => ({
      id: index + 1,
      mutationId: this.rng.sampleLotteryCurvePrize(config.miningMutationProbabilityCurve),
    }));
    this.miningRefreshElapsedSeconds = 0;
  }
}
