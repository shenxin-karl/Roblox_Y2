import { Inspector as BaseInspector, UIButton, UILabel } from "@game-simulator/framework";
import type { CurveValue, InspectorSelection } from "@game-simulator/framework";
import type { ProjectConfig } from "./Main";
import type { State } from "./State";
import type { Game } from "./Game";
import { QueueSwordReplacementAction, ReplaceSwordAction, SetForgeTargetAction, UnlockSlotAction } from "./Actions";
import { calculateSlotUnlockPrice, calculateSwordUpgradePlan } from "./Formulas";

export class SlotInspector extends BaseInspector<ProjectConfig, State> {
  BuildEditorUI({ selection }: { selection: InspectorSelection | null }): void {
    this.ClearUpdateCallback();
    this.UIRoot.ClearChildren();
    this.UIRoot.Width = 300;
    this.UIRoot.Height = 516;
    this.UIRoot.BackgroundColor = "transparent";
    this.UIRoot.BorderColor = "transparent";

    const details = new UILabel(this.UIRoot, {
      Name: "SlotDetails",
      X: 24,
      Y: 24,
      Width: 252,
      Height: 88,
      HorizontalAlign: "Left",
      VerticalAlign: "Top",
      Text: "请选择槽位",
    });
    if (selection?.type !== "slot") {
      return;
    }

    const unlock = new UIButton(this.UIRoot, {
      Name: "UnlockSlot",
      X: 24,
      Y: 144,
      Width: 252,
      Height: 40,
      Text: "解锁 (W)",
    });
    const targetButtons = [1, 2, 3, 4].map((offset, index) => {
      const button = new UIButton(this.UIRoot, {
        Name: `ForgeTarget${offset}`, X: 24 + index * 66, Y: 216, Width: 54, Height: 36,
        Text: `+${offset}`,
      });
      button.OnClick = () => {
        const slot = this.state.slots.find((item) => `${item.id}` === selection.id);
        if (!slot?.unlocked) {
          return;
        }
        const action = new SetForgeTargetAction(offset);
        if (!this.getActionBlocker(action) && this.consumeAction(action, [`一键置换打造目标切换为 +${offset}`])) {
          this.game.UpdateUI?.();
        }
        update(this.state);
      };
      return { offset, button };
    });
    const replace = new UIButton(this.UIRoot, {
      Name: "ReplaceSword",
      X: 24,
      Y: 276,
      Width: 252,
      Height: 44,
      Text: "一键置换升级 (R)",
    });
    const upgrade = new UIButton(this.UIRoot, {
      Name: "UpgradeSword",
      X: 24,
      Y: 344,
      Width: 252,
      Height: 40,
      Text: "一键升级 (W)",
    });
    const hint = new UILabel(this.UIRoot, {
      Name: "ReplaceHint",
      X: 24,
      Y: 412,
      Width: 252,
      Height: 80,
      FontSize: 12,
      TextColor: "#667085",
      HorizontalAlign: "Left",
      VerticalAlign: "Top",
    });
    const update = (state: State): void => {
      const slot = state.slots.find((item) => `${item.id}` === selection.id);
      if (!slot) {
        details.Text = "请选择槽位";
        unlock.Visible = false;
        targetButtons.forEach(({ button }) => { button.Visible = false; });
        replace.Visible = false;
        upgrade.Visible = false;
        hint.Visible = false;
        return;
      }
      unlock.Visible = true;
      targetButtons.forEach(({ offset, button }) => {
        const selected = state.forgeTargetOffset === offset;
        button.Visible = slot.unlocked;
        button.Disabled = this.getActionBlocker(new SetForgeTargetAction(offset)) !== null;
        button.ButtonColor = selected ? "#1570ef" : "#eaf4ff";
        button.TextColor = selected ? "#ffffff" : "#344054";
      });
      replace.Visible = slot.unlocked;
      upgrade.Visible = slot.unlocked;
      hint.Visible = slot.unlocked;
      const replaceBlocker = this.getActionBlocker(new QueueSwordReplacementAction(slot.id));
      replace.Disabled = replaceBlocker !== null;
      const queueIndex = state.pendingReplacementSlotIds.indexOf(slot.id);
      replace.Text = queueIndex >= 0 ? "已加入置换队列 (R)" : "一键置换升级 (R)";
      const executionBlocker = this.getActionBlocker(new ReplaceSwordAction(slot.id));
      hint.Text = queueIndex >= 0
        ? `目标 +${state.forgeTargetOffset} · 排队 #${queueIndex + 1}\n${executionBlocker?.reason ?? "待执行一次"}`
        : `目标 +${state.forgeTargetOffset} · ${executionBlocker?.reason ?? "可置换"}`;
      const blocker = this.getActionBlocker(new UnlockSlotAction(slot.id));
      unlock.Disabled = blocker !== null;
      unlock.Text = slot.unlocked ? "已解锁" : "解锁 (W)";
      const sword = state.swords.find((item) => item.id === slot.swordId);
      const upgradeBlocker = this.getActionBlocker((this.game as Game).createSlotUpgradeAction(slot.id));
      upgrade.Disabled = upgradeBlocker !== null;
      upgrade.Text = sword ? "一键升级 (W)" : "获取并升级 (W)";
      if (slot.unlocked) {
        details.Text = `槽位 ${slot.id}\n${sword ? `品质 ${sword.quality}，Lv.${sword.level}` : "空槽位"}\n金钱：${state.money.toFixed(2)}`;
        if (sword && !upgradeBlocker) {
          const plan = calculateSwordUpgradePlan(this.config.swordUpgradeCurves, sword.level, state.money);
          details.Text += `\n可升 ${plan.levels} 级 · ${plan.cost} 金币`;
        }
      } else {
        const price = calculateSlotUnlockPrice(this.config.slotUnlockCurve as CurveValue, slot.id);
        details.Text = `槽位 ${slot.id}\n解锁价格：${price}\n金钱：${state.money.toFixed(2)}`;
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
    replace.OnClick = () => {
      const slot = this.state.slots.find((item) => `${item.id}` === selection.id);
      if (!slot) {
        return;
      }
      const action = new QueueSwordReplacementAction(slot.id);
      if (!this.getActionBlocker(action) && this.consumeAction(action, [`槽位 ${slot.id} 加入一次性置换队列`])) {
        this.game.UpdateUI?.();
      }
      update(this.state);
    };
    upgrade.OnClick = () => {
      const slot = this.state.slots.find((item) => `${item.id}` === selection.id);
      if (!slot) {
        return;
      }
      (this.game as Game).upgradeSlot(slot.id);
      update(this.state);
    };
    update(this.state);
    this.RegisterUpdateUI(update);
  }
}
