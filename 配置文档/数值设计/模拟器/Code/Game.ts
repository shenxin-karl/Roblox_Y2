import { Game as BaseGame, UIButton, UILabel, UIPanel } from "@game-simulator/framework";
import type { ProjectConfig } from "./Main";
import type { State } from "./State";

export class Game extends BaseGame<ProjectConfig, State> {
  readonly UIRoot = new UIPanel();
  private readonly slotLabels: { id: UILabel; button: UIButton }[] = [];

  constructor() {
    super();
    this.UIRoot.Name = "GameRoot";
    this.UIRoot.Width = 660;
    this.UIRoot.Height = 552;
    this.UIRoot.BackgroundColor = "transparent";
    this.UIRoot.BorderColor = "transparent";

    this.state.slots.forEach((slot, index) => {
      const button = new UIButton(this.UIRoot, {
        Name: `Slot${slot.id}`,
        X: 12 + (index % 6) * 108,
        Y: 12 + Math.floor(index / 6) * 108,
        Width: 96,
        Height: 96,
        Text: "未解锁",
        FontSize: 12,
        ButtonColor: "#eaf4ff",
        BorderColor: "#c9def5",
        TextColor: "#8a94a6",
      });
      button.OnClick = ({ editor }) => {
        editor.selectInspectable({
          type: "slot",
          id: `${this.state.slots[index].id}`,
          source: "game",
        });
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

  UpdateUI(): void {
    this.slotLabels.forEach((labels, index) => {
      const slot = this.state.slots[index];
      labels.id.Text = `${slot.id}`;
      labels.button.Text = slot.unlocked ? "已解锁" : "未解锁";
    });
  }
}
