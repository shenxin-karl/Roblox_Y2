import configValues from "../Data/config.json";
import { Config, type NumberConfigValue, type RuntimeConfig } from "@game-simulator/framework";
import { Game } from "./Game";
import { SlotInspector } from "./Inspector";
import { State } from "./State";

export type ConfigValues = typeof configValues & {
  initialMoney: NumberConfigValue;
  initialUnlockedSlotCount: NumberConfigValue;
};
export type ProjectConfig = RuntimeConfig<ConfigValues>;

const config = new Config(configValues) as ProjectConfig;
const state = new State(config.initialMoney, config.initialUnlockedSlotCount);
const game = new Game();
const inspector = new SlotInspector();

export function createProject() {
  return { config, state, game, inspector };
}
