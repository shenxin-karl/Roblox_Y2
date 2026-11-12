import { Game as BaseGame, UIButton, UILabel, UIPanel } from "@game-simulator/framework";
import type { BaseAction } from "@game-simulator/framework";
import { ForgeSwordAction, PlaceSwordAction, UpgradeSwordAction } from "./Actions";
import { calculateSwordLevelMultiplier, calculateSwordUpgradePrice } from "./Formulas";
import type { ProjectConfig } from "./Main";
import type { State, SwordState } from "./State";

export class Game extends BaseGame<ProjectConfig, State> {
  readonly UIRoot = new UIPanel();
  private readonly slotLabels: { id: UILabel; button: UIButton }[] = [];
  private readonly currentSwordLabel: UILabel;
  private readonly statusLabel: UILabel;
  private readonly forgeButton: UIButton;
  private readonly placeButton: UIButton;
  private readonly upgradeButton: UIButton;
  private selectedSlotId: number | null = null;

  constructor() {
    super();
    this.UIRoot.Name = "GameRoot";
    this.UIRoot.Width = 660;
    this.UIRoot.Height = 688;
    this.UIRoot.BackgroundColor = "transparent";
    this.UIRoot.BorderColor = "transparent";

    this.currentSwordLabel = new UILabel(this.UIRoot, {
      Name: "CurrentSword", X: 12, Y: 8, Width: 636, Height: 40,
      FontSize: 13, HorizontalAlign: "Left", VerticalAlign: "Top",
    });
    this.statusLabel = new UILabel(this.UIRoot, {
      Name: "PlayStatus", X: 12, Y: 52, Width: 636, Height: 32,
      FontSize: 12, HorizontalAlign: "Left", VerticalAlign: "Top",
    });
    this.forgeButton = new UIButton(this.UIRoot, {
      Name: "ForgeSword", X: 12, Y: 96, Width: 144, Height: 36, Text: "打造",
    });
    this.forgeButton.OnClick = () => this.forgeSword();
    this.placeButton = new UIButton(this.UIRoot, {
      Name: "PlaceSword", X: 168, Y: 96, Width: 228, Height: 36, Text: "放入选中槽位",
    });
    this.placeButton.OnClick = () => this.placeCurrentSword();
    this.upgradeButton = new UIButton(this.UIRoot, {
      Name: "UpgradeSword", X: 408, Y: 96, Width: 240, Height: 36, Text: "升级槽位武器",
    });
    this.upgradeButton.OnClick = () => this.upgradeSelectedSword();

    this.state.slots.forEach((slot, index) => {
      const button = new UIButton(this.UIRoot, {
        Name: `Slot${slot.id}`,
        X: 12 + (index % 6) * 108,
        Y: 148 + Math.floor(index / 6) * 108,
        Width: 96,
        Height: 96,
        Text: "未解锁",
        FontSize: 12,
        ButtonColor: "#eaf4ff",
        BorderColor: "#c9def5",
        TextColor: "#8a94a6",
      });
      button.OnClick = ({ editor }) => {
        this.selectedSlotId = this.state.slots[index].id;
        editor.selectInspectable({
          type: "slot",
          id: `${this.state.slots[index].id}`,
          source: "game",
        });
        this.UpdateUI();
      };
      const id = new UILabel(button, {
        Name: "Id",
        X: 6,
        Y: 4,
        Width: 84,
        Height: 16,
        FontSize: 10,
        HorizontalAlign: "Left",
        VerticalAlign: "Top",
        TextColor: "#667085",
      });
      this.slotLabels.push({ id, button });
    });
  }

  BuildEditorUI(): void {
    this.UpdateUI();
  }

  private execute(action: BaseAction, message: string): void {
    if (!this.getActionBlocker(action)) {
      this.consumeAction(action, [message]);
    }
    this.UpdateUI();
  }

  forgeSword(): void {
    this.execute(new ForgeSwordAction(), "手动取最佳变异矿石并打造至 +1，不自动放置");
  }

  placeCurrentSword(): void {
    this.execute(new PlaceSwordAction(this.state.currentSwordId ?? 0, this.selectedSlotId ?? 0), "将当前武器放入选中槽位，替换时丢弃旧剑");
  }

  upgradeSelectedSword(): void {
    this.execute(new UpgradeSwordAction(this.selectedSlotId ?? 0), "花费金币将选中槽位内的武器升一级");
  }

  private describeSword(sword: SwordState): string {
    const input = this.config.swordUpgradeCurves.input;
    const levelInRange = Number.isInteger(sword.level) && sword.level >= (input.min ?? 1) &&
      sword.level <= (input.max ?? Infinity);
    const multiplier = levelInRange ? calculateSwordLevelMultiplier(this.config.swordUpgradeCurves, sword.level) : "—";
    const offset = sword.quality - sword.playerLuck;
    return `武器 #${sword.id}，品质 ${sword.quality}（${offset >= 0 ? "+" : ""}${offset}），Lv.${sword.level}，变异 ${sword.mutationId}，等级倍率 ${multiplier}`;
  }

  UpdateUI(): void {
    const currentSword = this.state.swords.find((sword) => sword.id === this.state.currentSwordId);
    const currentSlot = this.state.slots.find((slot) => slot.swordId === currentSword?.id);
    this.currentSwordLabel.Text = currentSword
      ? `当前${this.describeSword(currentSword)}\n${currentSlot ? `已放入槽位 ${currentSlot.id}` : "尚未放置：请选择槽位，再点击放入或替换"}`
      : (this.state.lastForgeResult?.outcome === "destroyed" ? "本次打造武器消失，无成品" : "当前武器：暂无，请点击打造");
    const selectedSlot = this.state.slots.find((slot) => slot.id === this.selectedSlotId);
    const selectedSword = this.state.swords.find((sword) => sword.id === selectedSlot?.swordId);
    const cooldown = Math.max(0, this.config.oreCollectInterval - this.state.oreCollectElapsedSeconds);
    const selectedText = selectedSlot
      ? `选中槽位 ${selectedSlot.id}：${selectedSlot.unlocked ? (selectedSword ? `武器 #${selectedSword.id}，品质 ${selectedSword.quality}，Lv.${selectedSword.level}` : "空槽位") : "未解锁"}`
      : "请选择一个槽位，放置、替换或升级武器";
    this.statusLabel.Text = `金钱：${this.state.money}　矿石：${this.state.miningOres.length}　取矿冷却：${cooldown}秒\n${selectedText}`;
    const forgeBlocker = this.getActionBlocker(new ForgeSwordAction());
    this.forgeButton.Disabled = forgeBlocker !== null;
    this.forgeButton.Text = forgeBlocker ? (cooldown > 0 ? `打造（冷却 ${cooldown}s）` : forgeBlocker.reason) : "打造";
    const placeBlocker = this.getActionBlocker(new PlaceSwordAction(currentSword?.id ?? 0, selectedSlot?.id ?? 0));
    this.placeButton.Disabled = placeBlocker !== null;
    this.placeButton.Text = selectedSlot?.swordId != null
      ? `替换槽位 ${selectedSlot.id}（丢弃旧剑）` : "放入选中槽位";
    const upgradeBlocker = this.getActionBlocker(new UpgradeSwordAction(selectedSlot?.id ?? 0));
    this.upgradeButton.Disabled = upgradeBlocker !== null;
    if (selectedSword && upgradeBlocker?.kind !== "invalidSwordLevel" && upgradeBlocker?.kind !== "swordMaxLevel") {
      const price = calculateSwordUpgradePrice(this.config.swordUpgradeCurves, selectedSword.level);
      this.upgradeButton.Text = `升一级（${price}金币${upgradeBlocker?.kind === "moneyNotEnough" ? "，余额不足" : ""}）`;
    } else {
      this.upgradeButton.Text = upgradeBlocker?.reason ?? "升级槽位武器";
    }
    this.slotLabels.forEach((labels, index) => {
      const slot = this.state.slots[index];
      const sword = this.state.swords.find((item) => item.id === slot.swordId);
      labels.id.Text = `${slot.id}`;
      labels.button.Text = slot.unlocked ? (sword ? `品质 ${sword.quality}\nLv.${sword.level}` : "已解锁") : "未解锁";
      labels.button.BorderColor = slot.id === this.selectedSlotId ? "#f79009" : "#c9def5";
    });
  }
}
