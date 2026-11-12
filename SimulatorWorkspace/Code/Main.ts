import configValues from "../Data/config.json";
import { Config, type CurveGroupValue, type CurveValue, type LotteryCurveValue, type NumberConfigValue, type RuntimeConfig } from "@game-simulator/framework";
import { Game } from "./Game";
import { SlotInspector } from "./Inspector";
import { State } from "./State";

export type ConfigValues = Omit<typeof configValues, "paidMultiplierCurves"> & {
  initialUnlockedSlotCount: NumberConfigValue;
  miningRefreshInterval: NumberConfigValue;
  miningSpawnCount: NumberConfigValue;
  miningMutationProbabilityCurve: LotteryCurveValue;
  oreCollectInterval: NumberConfigValue;
  miningMutationLuckCurve: CurveValue;
  swordUpgradeCurves: CurveGroupValue;
  smeltingUpgradeCurves: CurveGroupValue;
  forgingUpgradeCurves: CurveGroupValue;
  incomeUpgradeCurves: CurveGroupValue;
  swordQualityIncomeCurve: CurveValue;
  swordMutationIncomeCurve: CurveValue;
  initialDiamonds: NumberConfigValue;
  initialPaidMultiplierTier: NumberConfigValue;
  dailyDiamondReward: NumberConfigValue;
  paidMultiplierCurves: CurveGroupValue;
};
export type ProjectConfig = RuntimeConfig<ConfigValues>;

const config = new Config(configValues as ConfigValues) as ProjectConfig;
const state = new State(config.initialUnlockedSlotCount, config.initialDiamonds, config.initialPaidMultiplierTier);
const game = new Game();
const inspector = new SlotInspector();

export function createProject() {
  return { config, state, game, inspector };
}
