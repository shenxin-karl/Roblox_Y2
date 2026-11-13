import { Game as BaseGame, UIButton, UILabel, UIPanel } from "@game-simulator/framework";
import type { DailyScheduleContext } from "@game-simulator/framework";
import { BuyPaidMultiplierAction, ClaimDailyDiamondsAction, ClaimOfflineIncomeAction, InitializeMiningOresAction, QueueSwordReplacementAction, RefreshMiningOresAction, ReplaceSwordAction, SetAutoBuyPaidMultiplierAction, UnlockSlotAction, UpgradePlayerAction, UpgradeSwordMaxAction } from "./Actions";
import { calculatePaidMultiplier, calculatePlayerUpgradeEffect, calculatePlayerUpgradePrice, getNextPaidMultiplier, getPlayerUpgradeCurves, type PlayerUpgradeKind } from "./Formulas";
import type { ProjectConfig } from "./Main";
import type { State } from "./State";

export class Game extends BaseGame<ProjectConfig, State> {
  readonly UIRoot = new UIPanel();
  private readonly slotLabels: { id: UILabel; button: UIButton }[] = [];
  private readonly oreSummaryLabel: UILabel;
  private readonly paidSummaryLabel: UILabel;
  private readonly paidTiersLabel: UILabel;
  private readonly buyPaidMultiplierButton: UIButton;
  private readonly autoBuyPaidMultiplierButton: UIButton;
  private readonly dailyDiamondsLabel: UILabel;
  private readonly playerUpgradeButtons: { kind: PlayerUpgradeKind; title: string; button: UIButton }[] = [];
  private selectedSlotId: number | null = null;

  constructor() {
    super();
    this.UIRoot.Name = "GameRoot";
    this.UIRoot.Width = 972;
    this.UIRoot.Height = 520;
    this.UIRoot.BackgroundColor = "transparent";
    this.UIRoot.BorderColor = "transparent";

    this.oreSummaryLabel = new UILabel(this.UIRoot, {
      Name: "OreSummary", X: 12, Y: 8, Width: 948, Height: 24,
      FontSize: 12, HorizontalAlign: "Left", VerticalAlign: "Top",
    });

    const upgrades = [
      { kind: "smelting", title: "熔炼幸运" },
      { kind: "forging", title: "武器锻造" },
      { kind: "income", title: "收益倍率" },
    ] as const;
    upgrades.forEach(({ kind, title }, index) => {
      const button = new UIButton(this.UIRoot, {
        Name: `PlayerUpgrade_${kind}`, X: 12 + index * 320, Y: 40, Width: 308, Height: 64, FontSize: 12,
      });
      button.OnClick = () => {
        const action = new UpgradePlayerAction(kind);
        if (!this.getActionBlocker(action)) {
          this.consumeAction(action, [`玩家升级：${title}`]);
        }
        this.UpdateUI();
      };
      this.playerUpgradeButtons.push({ kind, title, button });
    });

    this.state.slots.forEach((slot, index) => {
      const button = new UIButton(this.UIRoot, {
        Name: `Slot${slot.id}`,
        X: 12 + (index % 10) * 96,
        Y: 112 + Math.floor(index / 10) * 96,
        Width: 84,
        Height: 84,
        Text: "未解锁",
        FontSize: 12,
        ButtonColor: "#e1ecfb",
        BorderColor: "#a6c1e5",
        TextColor: "#36577f",
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
        Width: 72,
        Height: 16,
        FontSize: 10,
        HorizontalAlign: "Left",
        VerticalAlign: "Top",
        TextColor: "#526782",
      });
      this.slotLabels.push({ id, button });
    });

    this.paidSummaryLabel = new UILabel(this.UIRoot, {
      Name: "PaidMultiplierSummary", X: 12, Y: 404, Width: 444, Height: 32,
      HorizontalAlign: "Left",
    });
    this.paidTiersLabel = new UILabel(this.UIRoot, {
      Name: "PurchasedPaidTiers", X: 12, Y: 444, Width: 948, Height: 32,
      FontSize: 12, HorizontalAlign: "Left", VerticalAlign: "Top",
    });
    this.buyPaidMultiplierButton = new UIButton(this.UIRoot, {
      Name: "BuyPaidMultiplier", X: 468, Y: 404, Width: 276, Height: 32, FontSize: 12,
    });
    this.buyPaidMultiplierButton.OnClick = () => {
      const action = new BuyPaidMultiplierAction();
      if (!this.getActionBlocker(action)) {
        this.consumeAction(action, ["钻石购买下一档付费倍率"]);
      }
      this.UpdateUI();
    };
    this.autoBuyPaidMultiplierButton = new UIButton(this.UIRoot, {
      Name: "AutoBuyPaidMultiplier", X: 756, Y: 404, Width: 204, Height: 32, FontSize: 12,
    });
    this.autoBuyPaidMultiplierButton.OnClick = () => {
      this.consumeAction(new SetAutoBuyPaidMultiplierAction(!this.state.autoBuyPaidMultiplier));
      this.tryAutoBuyPaidMultiplier();
      this.UpdateUI();
    };
    this.dailyDiamondsLabel = new UILabel(this.UIRoot, {
      Name: "DailyDiamonds", X: 12, Y: 484, Width: 948, Height: 24,
      FontSize: 12, HorizontalAlign: "Left", VerticalAlign: "Top", TextColor: "#526782",
    });
  }

  BuildEditorUI(): void {
    if (this.state.miningRefreshElapsedSeconds < 0) {
      this.consumeAction(new InitializeMiningOresAction(), ["开局立即刷新矿石"], "system");
    }
    this.grantDailyDiamonds(this.getScheduleContext()?.day ?? 1);
    this.tryAutoBuyPaidMultiplier();
    this.UpdateUI();
  }

  onSessionStart(context: DailyScheduleContext): void {
    this.consumeAction(new RefreshMiningOresAction(), ["上线立即刷新一批矿石"], "system");
    const offlineIncome = new ClaimOfflineIncomeAction(context.offlineSeconds);
    if (!this.getActionBlocker(offlineIncome)) {
      this.consumeAction(offlineIncome, ["上线自动结算离线金币收益"], "system");
    }
    this.grantDailyDiamonds(context.day);
    this.tryAutoBuyPaidMultiplier();
  }

  private grantDailyDiamonds(day: number): void {
    const action = new ClaimDailyDiamondsAction(day);
    if (!this.getActionBlocker(action)) {
      this.consumeAction(action, [`第 ${day} 个模拟日赠送钻石`], "system");
    }
  }

  private tryAutoBuyPaidMultiplier(): void {
    while (this.state.autoBuyPaidMultiplier) {
      const action = new BuyPaidMultiplierAction();
      if (this.getActionBlocker(action) || !this.consumeAction(action, ["自动购买下一档付费倍率"], "system")) {
        break;
      }
    }
  }

  handleShortcutKey(key: string): void {
    if ((key !== "R" && key !== "W") || this.selectedSlotId === null) {
      return;
    }
    if (key === "W") {
      this.upgradeSlot(this.selectedSlotId);
      return;
    }
    const action = new QueueSwordReplacementAction(this.selectedSlotId);
    if (!this.getActionBlocker(action)) {
      this.consumeAction(action, [`槽位 ${this.selectedSlotId} 加入一次性置换队列`]);
    }
    this.UpdateUI();
  }

  createSlotUpgradeAction(slotId: number): UnlockSlotAction | ReplaceSwordAction | UpgradeSwordMaxAction {
    const slot = this.state.slots.find((item) => item.id === slotId);
    if (!slot?.unlocked) {
      return new UnlockSlotAction(slotId);
    }
    return slot.swordId === null ? new ReplaceSwordAction(slotId) : new UpgradeSwordMaxAction(slotId);
  }

  upgradeSlot(slotId: number): void {
    const action = this.createSlotUpgradeAction(slotId);
    if (!this.getActionBlocker(action) && this.consumeAction(action, [`槽位 ${slotId} 执行一键解锁、获取或升级`])) {
      if (action instanceof ReplaceSwordAction) {
        const upgrade = new UpgradeSwordMaxAction(slotId);
        if (!this.getActionBlocker(upgrade)) {
          this.consumeAction(upgrade, [`一键升级槽位 ${slotId} 内的新武器`]);
        }
      }
    }
    this.UpdateUI();
  }

  advanceOneSecond(): void {
    this.tryAutoBuyPaidMultiplier();
    const slotId = this.state.pendingReplacementSlotIds[0];
    if (slotId === undefined) {
      return;
    }
    const action = new ReplaceSwordAction(slotId);
    if (!this.getActionBlocker(action)) {
      this.consumeAction(action, [`执行队首槽位 ${slotId} 的一次置换请求，完成后出队`]);
    }
  }

  UpdateUI(): void {
    const tier = this.state.paidMultiplierTier;
    const curves = this.config.paidMultiplierCurves;
    const multiplier = calculatePaidMultiplier(this.config, tier);
    this.paidSummaryLabel.Text = `付费金币倍率 ×${multiplier} ｜ 钻石 ${this.state.diamonds} ｜ 已购第 ${tier} 档`;
    const purchasedTiers = Array.from({ length: tier - curves.input.min! + 1 }, (_, index) =>
      `×${calculatePaidMultiplier(this.config, curves.input.min! + index)}`);
    this.paidTiersLabel.Text = `已购档位：${purchasedTiers.join(" → ")}（新手默认 ×${calculatePaidMultiplier(this.config, this.config.initialPaidMultiplierTier)}）`;
    const next = getNextPaidMultiplier(this.config, tier);
    const buyBlocker = this.getActionBlocker(new BuyPaidMultiplierAction());
    this.buyPaidMultiplierButton.Disabled = buyBlocker !== null;
    this.buyPaidMultiplierButton.ButtonColor = buyBlocker ? "#f9e2ad" : "#f6ce7c";
    this.buyPaidMultiplierButton.TextColor = "#6d4817";
    this.buyPaidMultiplierButton.BorderColor = "#d9b979";
    this.buyPaidMultiplierButton.Text = next
      ? `购买下一档 ×${next.multiplier}：${next.price} 钻${buyBlocker ? `（${buyBlocker.reason}）` : ""}`
      : "付费倍率已满档";
    this.autoBuyPaidMultiplierButton.Text = `自动购买付费倍率：${this.state.autoBuyPaidMultiplier ? "开启" : "关闭"}`;
    this.autoBuyPaidMultiplierButton.ButtonColor = this.state.autoBuyPaidMultiplier ? "#bbdfd4" : "#ddd4f2";
    this.autoBuyPaidMultiplierButton.TextColor = this.state.autoBuyPaidMultiplier ? "#24564d" : "#4e416e";
    this.autoBuyPaidMultiplierButton.BorderColor = this.state.autoBuyPaidMultiplier ? "#8bbfaf" : "#bba8da";
    this.dailyDiamondsLabel.Text = `每日赠送 ${this.config.dailyDiamondReward} 钻｜最近已发：第 ${this.state.lastDiamondRewardDay} 个模拟日｜钻石不受倍率加成`;
    const mutationNames = ["无变异", "变异1", "变异2", "变异3", "变异4", "变异5"];
    const oreCounts = new Map<number, number>();
    for (const ore of this.state.miningOres) {
      oreCounts.set(ore.mutationId, (oreCounts.get(ore.mutationId) ?? 0) + 1);
    }
    const oreSummary = [...oreCounts].sort(([a], [b]) => a - b)
      .map(([id, count]) => `${mutationNames[id - 1] ?? `变异${id - 1}`} x ${count}`).join(" · ");
    this.oreSummaryLabel.Text = oreSummary ? `矿石 ${this.state.miningOres.length}｜${oreSummary}` : "矿石：暂无";
    this.playerUpgradeButtons.forEach(({ kind, title, button }) => {
      const level = this.state.playerUpgradeLevels[kind];
      const blocker = this.getActionBlocker(new UpgradePlayerAction(kind));
      const palette = {
        smelting: { background: "#afcdf5", muted: "#cadffa", text: "#234b7a", border: "#94b6e3" },
        forging: { background: "#cbb5ee", muted: "#dfd1f7", text: "#533578", border: "#b49ad6" },
        income: { background: "#a6d8ca", muted: "#c5e7dd", text: "#24564d", border: "#8bbfaf" },
      }[kind];
      button.Disabled = blocker !== null;
      button.ButtonColor = blocker ? palette.muted : palette.background;
      button.TextColor = palette.text;
      button.BorderColor = palette.border;
      if (blocker && blocker.kind !== "moneyNotEnough") {
        button.Text = `${title} Lv.${level}\n${blocker.reason}`;
        return;
      }
      const curves = getPlayerUpgradeCurves(this.config, kind);
      const effect = calculatePlayerUpgradeEffect(this.config, kind, level);
      const nextEffect = calculatePlayerUpgradeEffect(this.config, kind, level + 1);
      const preview = kind === "income"
        ? `×${effect.toFixed(2)} → ×${nextEffect.toFixed(2)}`
        : kind === "forging"
          ? `人物幸运 ${this.state.playerLuck} → ${this.state.playerLuck + nextEffect - effect}`
          : `原料幸运 +${effect} → +${nextEffect}`;
      button.Text = `${title} Lv.${level}\n${preview}\n${calculatePlayerUpgradePrice(curves, level)}金币${blocker ? "（不足）" : ""}`;
    });
    this.slotLabels.forEach((labels, index) => {
      const slot = this.state.slots[index];
      const sword = this.state.swords.find((item) => item.id === slot.swordId);
      labels.id.Text = `${slot.id}`;
      labels.button.Text = slot.unlocked ? (sword ? `品质 ${sword.quality}\nLv.${sword.level}` : "已解锁") : "未解锁";
      labels.button.ButtonColor = slot.unlocked ? (sword ? "#cbdffb" : "#e1ecfb") : "#e9eef5";
      labels.button.TextColor = slot.unlocked ? (sword ? "#234b7a" : "#486588") : "#5b6b82";
      labels.button.BorderColor = slot.id === this.selectedSlotId ? "#f79009" : slot.unlocked ? "#a6c1e5" : "#c6d1e1";
    });
  }
}
