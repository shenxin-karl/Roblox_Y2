import { Inspector as BaseInspector, UIButton, UILabel } from "@game-simulator/framework";
import type { CurveValue, InspectorSelection } from "@game-simulator/framework";
import type { ProjectConfig } from "./Main";
import type { State } from "./State";
import { UnlockSlotAction } from "./Actions";
import { calculateSlotUnlockPrice } from "./Formulas";

export class SlotInspector extends BaseInspector<ProjectConfig, State> {
  BuildEditorUI({ selection }: { selection: InspectorSelection | null }): void {
    this.ClearUpdateCallback();
    this.UIRoot.ClearChildren();
    this.UIRoot.Width = 260;
    this.UIRoot.Height = 164;

    const details = new UILabel(this.UIRoot, {
      Name: "SlotDetails",
      X: 12,
      Y: 12,
      Width: 236,
      Height: 80,
      HorizontalAlign: "Left",
      VerticalAlign: "Top",
      Text: "请选择槽位",
    });
    if (selection?.type !== "slot") {
      return;
    }

    const unlock = new UIButton(this.UIRoot, {
      Name: "UnlockSlot",
      X: 12,
      Y: 112,
      Width: 236,
      Height: 36,
      Text: "解锁",
    });
    const update = (state: State): void => {
      const slot = state.slots.find((item) => `${item.id}` === selection.id);
      if (!slot) {
        details.Text = "请选择槽位";
        unlock.Visible = false;
        return;
      }
      unlock.Visible = true;
      const blocker = this.getActionBlocker(new UnlockSlotAction(slot.id));
      unlock.Disabled = blocker !== null;
      unlock.Text = slot.unlocked ? "已解锁" : "解锁";
      if (slot.unlocked) {
        details.Text = `槽位 ${slot.id}\n已解锁\n金钱：${state.money}`;
      } else {
        const price = calculateSlotUnlockPrice(this.config.slotUnlockCurve as CurveValue, slot.id);
        details.Text = `槽位 ${slot.id}\n解锁价格：${price}\n金钱：${state.money}`;
      }
    };
    unlock.OnClick = () => {
      const slot = this.state.slots.find((item) => `${item.id}` === selection.id);
      if (!slot) {
        return;
      }
      const action = new UnlockSlotAction(slot.id);
      if (!this.getActionBlocker(action) && this.consumeAction(action, [`解锁槽位 ${slot.id}`])) {
        this.game.UpdateUI?.();
      }
      update(this.state);
    };
    update(this.state);
    this.RegisterUpdateUI(update);
  }
}
