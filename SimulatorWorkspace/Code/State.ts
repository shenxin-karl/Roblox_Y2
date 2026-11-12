import { State as BaseState } from "@game-simulator/framework";
import type { ProjectConfig } from "./Main";

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
};

export class State extends BaseState<StateValues> {
  slots: SlotState[];
  money: number;
  miningOres: MiningOreState[] = [];
  miningRefreshElapsedSeconds = 0;
  oreCollectElapsedSeconds = 0;
  playerLuck: number;
  swords: SwordState[] = [];
  currentSwordId: number | null = null;
  lastForgeResult: ForgeResultState | null = null;

  constructor(
    private readonly initialMoney: number,
    private readonly initialUnlockedSlotCount: number,
    private readonly initialPlayerLuck: number,
  ) {
    super();
    this.money = initialMoney;
    this.playerLuck = initialPlayerLuck;
    this.slots = Array.from({ length: 30 }, (_, index) => ({
      id: index + 1,
      unlocked: index < initialUnlockedSlotCount,
      swordId: null,
    }));
  }

  getSummary(): string {
    return `金钱：${this.money}，槽位：${this.slots.length}，矿石：${this.miningOres.length}，武器：${this.swords.length}，刷新计时：${this.miningRefreshElapsedSeconds}秒`;
  }

  getFieldDisplayNames(): Record<string, string> {
    return {
      money: "金钱",
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
      swords: "全部成品武器",
      "swords[].id": "武器 ID",
      "swords[].mutationId": "继承变异 ID",
      "swords[].luck": "原料幸运 W",
      "swords[].playerLuck": "打造时人物幸运 P",
      "swords[].quality": "武器品质 Q",
      "swords[].level": "成品武器等级",
      currentSwordId: "当前展示武器 ID",
      lastForgeResult: "最近一次打造",
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
      slots: this.slots.map((slot) => ({ ...slot })),
      miningOres: this.miningOres.map((ore) => ({ ...ore })),
      miningRefreshElapsedSeconds: this.miningRefreshElapsedSeconds,
      oreCollectElapsedSeconds: this.oreCollectElapsedSeconds,
      playerLuck: this.playerLuck,
      swords: this.swords.map((sword) => ({ ...sword })),
      currentSwordId: this.currentSwordId,
      lastForgeResult: this.lastForgeResult ? { ...this.lastForgeResult } : null,
    };
  }

  loadJSON(values: StateValues): void {
    this.money = values.money ?? this.initialMoney;
    this.slots = values.slots.map((slot) => ({
      id: slot.id,
      unlocked: slot.unlocked ?? slot.id <= this.initialUnlockedSlotCount,
      swordId: slot.swordId ?? null,
    }));
    this.miningOres = (values.miningOres ?? []).map((ore) => ({ ...ore }));
    this.miningRefreshElapsedSeconds = values.miningRefreshElapsedSeconds ?? 0;
    this.oreCollectElapsedSeconds = values.oreCollectElapsedSeconds ?? 0;
    this.playerLuck = values.playerLuck ?? this.initialPlayerLuck;
    this.swords = (values.swords ?? []).map((sword) => ({ ...sword, level: sword.level ?? 1 }));
    this.currentSwordId = values.currentSwordId ?? null;
    this.lastForgeResult = values.lastForgeResult ? { ...values.lastForgeResult } : null;
  }

  advanceOneSecond(): void {
    const config = this.config as ProjectConfig;
    this.oreCollectElapsedSeconds = Math.min(this.oreCollectElapsedSeconds + 1, config.oreCollectInterval);
    this.miningRefreshElapsedSeconds += 1;
    if (this.miningRefreshElapsedSeconds < config.miningRefreshInterval) {
      return;
    }
    this.miningOres = Array.from({ length: config.miningSpawnCount }, (_, index) => ({
      id: index + 1,
      mutationId: this.rng.sampleLotteryCurvePrize(config.miningMutationProbabilityCurve),
    }));
    this.miningRefreshElapsedSeconds = 0;
  }
}
