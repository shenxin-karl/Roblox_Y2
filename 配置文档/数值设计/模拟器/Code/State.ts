import { State as BaseState } from "@game-simulator/framework";

export type SlotState = { id: number; unlocked: boolean };

export type StateValues = { money: number; slots: SlotState[] };

export class State extends BaseState<StateValues> {
  slots: SlotState[];
  money: number;

  constructor(private readonly initialMoney: number, private readonly initialUnlockedSlotCount: number) {
    super();
    this.money = initialMoney;
    this.slots = Array.from({ length: 30 }, (_, index) => ({
      id: index + 1,
      unlocked: index < initialUnlockedSlotCount,
    }));
  }

  getSummary(): string {
    return `金钱：${this.money}，槽位：${this.slots.length}`;
  }

  getFieldDisplayNames(): Record<string, string> {
    return { money: "金钱", slots: "槽位", "slots[].id": "槽位 ID", "slots[].unlocked": "已解锁" };
  }

  toJSON(): StateValues {
    return { money: this.money, slots: this.slots.map((slot) => ({ ...slot })) };
  }

  loadJSON(values: StateValues): void {
    this.money = values.money ?? this.initialMoney;
    this.slots = values.slots.map((slot) => ({
      id: slot.id,
      unlocked: slot.unlocked ?? slot.id <= this.initialUnlockedSlotCount,
    }));
  }
}
