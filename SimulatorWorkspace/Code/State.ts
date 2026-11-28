import { State as BaseState } from "@game-simulator/framework";
import type { ProjectConfig } from "./Main";
import { calculateBaseIncome, type PlayerUpgradeKind } from "./Formulas";

export type SlotState = { id: number; unlocked: boolean; swordId: number | null };
export type MiningOreState = { id: number; mutationId: number };
type ReplacementRequest = { slotId: number; targetOffset: number };
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
  swords: SwordState[];
  currentSwordId: number | null;
  lastForgeResult: ForgeResultState | null;
  pendingReplacements: ReplacementRequest[];
  playerUpgradeLevels: Record<PlayerUpgradeKind, number>;
  forgeTargetOffset: number;
  diamonds: number;
  paidMultiplierTier: number;
  lastDiamondRewardDay: number;
  autoBuyPaidMultiplier: boolean;
  autoUnlockSlots: boolean;
};

export class State extends BaseState<StateValues> {
  slots: SlotState[];
  money = 0;
  miningOres: MiningOreState[] = [];
  miningRefreshElapsedSeconds = -1;
  oreCollectElapsedSeconds = 0;
  swords: SwordState[] = [];
  currentSwordId: number | null = null;
  lastForgeResult: ForgeResultState | null = null;
  pendingReplacements: ReplacementRequest[] = [];
  playerUpgradeLevels: Record<PlayerUpgradeKind, number> = { smelting: 1, forging: 1, income: 1 };
  forgeTargetOffset = 1;
  diamonds: number;
  paidMultiplierTier: number;
  lastDiamondRewardDay = 1; // 第一天发放新手钻石，第二天起发放每日钻石。
  autoBuyPaidMultiplier = false;
  autoUnlockSlots = false;

  constructor(
    initialUnlockedSlotCount: number,
    initialDiamonds: number,
    initialPaidMultiplierTier: number,
  ) {
    super();
    this.diamonds = initialDiamonds;
    this.paidMultiplierTier = initialPaidMultiplierTier;
    this.slots = Array.from({ length: 36 }, (_, index) => ({
      id: index + 1,
      unlocked: index < initialUnlockedSlotCount,
      swordId: null,
    }));
  }

  getSummary(): string {
    return `金钱：${this.money.toFixed(2)}，钻石：${this.diamonds}，付费倍率档位：${this.paidMultiplierTier}，槽位：${this.slots.length}，矿石：${this.miningOres.length}，武器：${this.swords.length}，刷新计时：${this.miningRefreshElapsedSeconds}秒，待置换：${this.pendingReplacements.length}，新请求目标：+${this.forgeTargetOffset}，玩家升级：${this.playerUpgradeLevels.smelting}/${this.playerUpgradeLevels.forging}/${this.playerUpgradeLevels.income}`;
  }

  getFieldDisplayNames(): Record<string, string> {
    return {
      money: "金钱",
      diamonds: "当前钻石",
      paidMultiplierTier: "已购付费倍率档位",
      lastDiamondRewardDay: "最近赠送钻石的模拟日",
      autoBuyPaidMultiplier: "自动购买付费倍率",
      autoUnlockSlots: "自动解锁槽位",
      slots: "槽位",
      "slots[].id": "槽位 ID",
      "slots[].unlocked": "已解锁",
      "slots[].swordId": "已放置武器 ID",
      miningOres: "当前矿石",
      "miningOres[].id": "矿石 ID",
      "miningOres[].mutationId": "变异 ID",
      miningRefreshElapsedSeconds: "矿石刷新已过秒数",
      oreCollectElapsedSeconds: "打造取矿冷却已过秒数",
      forgeTargetOffset: "一键置换目标品质偏移",
      playerUpgradeLevels: "玩家升级等级",
      "playerUpgradeLevels.smelting": "熔炼幸运等级",
      "playerUpgradeLevels.forging": "武器锻造等级",
      "playerUpgradeLevels.income": "收益倍率等级",
      swords: "全部成品武器",
      "swords[].id": "武器 ID",
      "swords[].mutationId": "继承变异 ID",
      "swords[].luck": "原料幸运 W",
      "swords[].playerLuck": "打造时的 P（现取锻造等级）",
      "swords[].quality": "武器品质 Q",
      "swords[].level": "成品武器等级",
      currentSwordId: "当前展示武器 ID",
      lastForgeResult: "最近一次打造",
      pendingReplacements: "待置换队列",
      "pendingReplacements[].slotId": "槽位",
      "pendingReplacements[].targetOffset": "置换目标偏移",
      "lastForgeResult.oreId": "消耗矿石 ID",
      "lastForgeResult.mutationId": "继承变异 ID",
      "lastForgeResult.materialLuck": "原料幸运 W",
      "lastForgeResult.playerLuck": "打造时的 P（现取锻造等级）",
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
      autoUnlockSlots: this.autoUnlockSlots,
      slots: this.slots.map((slot) => ({ ...slot })),
      miningOres: this.miningOres.map((ore) => ({ ...ore })),
      miningRefreshElapsedSeconds: this.miningRefreshElapsedSeconds,
      oreCollectElapsedSeconds: this.oreCollectElapsedSeconds,
      swords: this.swords.map((sword) => ({ ...sword })),
      currentSwordId: this.currentSwordId,
      lastForgeResult: this.lastForgeResult ? { ...this.lastForgeResult } : null,
      pendingReplacements: this.pendingReplacements.map((request) => ({ ...request })),
      playerUpgradeLevels: { ...this.playerUpgradeLevels },
      forgeTargetOffset: this.forgeTargetOffset,
    };
  }

  loadJSON(values: StateValues | (Omit<StateValues, "pendingReplacements"> & { pendingReplacementSlotIds: number[] })): void {
    this.money = values.money;
    this.diamonds = values.diamonds;
    this.paidMultiplierTier = values.paidMultiplierTier;
    this.lastDiamondRewardDay = values.lastDiamondRewardDay;
    this.autoBuyPaidMultiplier = values.autoBuyPaidMultiplier;
    this.autoUnlockSlots = values.autoUnlockSlots;
    this.slots = values.slots.map((slot) => ({ ...slot }));
    this.miningOres = values.miningOres.map((ore) => ({ ...ore }));
    this.miningRefreshElapsedSeconds = values.miningRefreshElapsedSeconds;
    this.oreCollectElapsedSeconds = values.oreCollectElapsedSeconds;
    this.swords = values.swords.map((sword) => ({ ...sword }));
    this.currentSwordId = values.currentSwordId;
    this.lastForgeResult = values.lastForgeResult ? { ...values.lastForgeResult } : null;
    this.pendingReplacements = "pendingReplacements" in values
      ? values.pendingReplacements.map((request) => ({ ...request }))
      : values.pendingReplacementSlotIds.map((slotId) => ({ slotId, targetOffset: values.forgeTargetOffset }));
    this.playerUpgradeLevels = { ...values.playerUpgradeLevels };
    this.forgeTargetOffset = values.forgeTargetOffset;
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
    const formula = config.mutationCurves.columns.find(column => column.key === "probability")?.formula;
    if (formula?.kind !== "LotteryProbability") {
      throw new Error("变异概率列需要使用抽奖概率公式");
    }
    this.miningOres = Array.from({ length: config.miningSpawnCount }, (_, index) => ({
      id: index + 1,
      mutationId: this.rng.sampleLotteryCurvePrize(formula.distribution),
    }));
    this.miningRefreshElapsedSeconds = 0;
  }
}
