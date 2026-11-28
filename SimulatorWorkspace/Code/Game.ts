import { Game as BaseGame, UIButton, UILabel, UIPanel } from "@game-simulator/framework";
import type { DailyScheduleContext } from "@game-simulator/framework";
import { BuyPaidMultiplierAction, ClaimDailyDiamondsAction, ClaimOfflineIncomeAction, InitializeMiningOresAction, QueueSwordReplacementAction, RefreshMiningOresAction, ReplaceSwordAction, SetAutoBuyPaidMultiplierAction, SetAutoUnlockSlotsAction, UnlockSlotAction, UpgradePlayerAction, UpgradeSwordMaxAction, isSwordReplacementRecommended } from "./Actions";
import { calculateBaseIncome, calculatePaidMultiplier, calculatePlayerUpgradePrice, getNextPaidMultiplier, getPlayerUpgradeCurves, type PlayerUpgradeKind } from "./Formulas";
import type { ProjectConfig } from "./Main";
import type { State } from "./State";

const slotIncomeFormat = new Intl.NumberFormat("zh-CN", {
  notation: "compact",
  maximumSignificantDigits: 4,
  useGrouping: true,
});

export class Game extends BaseGame<ProjectConfig, State> {
  readonly UIRoot = new UIPanel();
  private readonly slotLabels: { id: UILabel; mutation: UILabel; button: UIButton; stats: UILabel; income: UILabel; queue: UILabel }[] = [];
  private readonly oreSummaryLabel: UILabel;
  private readonly paidSummaryLabel: UILabel;
  private readonly buyPaidMultiplierButton: UIButton;
  private readonly autoBuyPaidMultiplierButton: UIButton;
  private readonly replaceRecommendedButton: UIButton;
  private readonly autoUnlockSlotsButton: UIButton;
  private readonly playerUpgradeButtons: { kind: PlayerUpgradeKind; title: string; button: UIButton }[] = [];
  private selectedSlotId: number | null = null;

  constructor() {
    super();
    this.UIRoot.Name = "GameRoot";
    this.UIRoot.Width = 972;
    this.UIRoot.Height = 528;
    this.UIRoot.BackgroundColor = "transparent";
    this.UIRoot.BorderColor = "transparent";

    this.oreSummaryLabel = new UILabel(this.UIRoot, {
      Name: "OreSummary", X: 12, Y: 34, Width: 948, Height: 18,
      FontSize: 12, HorizontalAlign: "Left",
    });
    this.oreSummaryLabel.RichText = true;

    const upgrades = [
      { kind: "income", title: "收益倍率" },
      { kind: "forging", title: "武器锻造" },
      { kind: "smelting", title: "熔炼幸运" },
    ] as const;
    upgrades.forEach(({ kind, title }, index) => {
      const button = new UIButton(this.UIRoot, {
        Name: `PlayerUpgrade_${kind}`, X: 12 + index * 212, Y: 60, Width: 204, Height: 30, FontSize: 11, TextWrap: false,
      });
      button.OnClick = ({ editor }) => {
        const action = new UpgradePlayerAction(kind);
        if (!this.getActionBlocker(action) && this.consumeAction(action, [`玩家升级：${title}`])) {
          const { income, forging, smelting } = this.state.playerUpgradeLevels;
          if (income === forging && income === smelting) {
            editor.addRewindPoint(`玩家升级 L${income}`);
          }
        }
        this.UpdateUI();
      };
      this.playerUpgradeButtons.push({ kind, title, button });
    });

    this.state.slots.forEach((slot, index) => {
      const button = new UIButton(this.UIRoot, {
        Name: `Slot${slot.id}`,
        X: 12 + (index % 9) * 108,
        Y: 108 + Math.floor(index / 9) * 96,
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
        Width: 28,
        Height: 16,
        FontSize: 10,
        HorizontalAlign: "Left",
        VerticalAlign: "Top",
        TextColor: "#526782",
      });
      const mutation = new UILabel(button, {
        Name: "Mutation", X: 36, Y: 4, Width: 42, Height: 16,
        FontSize: 10, HorizontalAlign: "Right", VerticalAlign: "Top",
      });
      const income = new UILabel(button, {
        Name: "Income", X: 4, Y: 22, Width: 76, Height: 26, FontSize: 15,
        TextWrap: false, TextColor: "#174635",
      });
      income.RichText = true;
      const stats = new UILabel(button, {
        Name: "Stats", X: 4, Y: 54, Width: 76, Height: 17, FontSize: 10,
        TextWrap: false, TextColor: "#52645c",
      });
      const queue = new UILabel(button, {
        Name: "Queue", X: 4, Y: 72, Width: 76, Height: 10, FontSize: 9,
        Text: "", TextColor: "#795611",
      });
      this.slotLabels.push({ id, mutation, button, stats, income, queue });
    });

    this.paidSummaryLabel = new UILabel(this.UIRoot, {
      Name: "PaidMultiplierSummary", X: 12, Y: 8, Width: 948, Height: 24,
      FontSize: 12, HorizontalAlign: "Left",
    });
    this.buyPaidMultiplierButton = new UIButton(this.UIRoot, {
      Name: "BuyPaidMultiplier", X: 648, Y: 60, Width: 240, Height: 30, FontSize: 11, TextWrap: false,
    });
    this.buyPaidMultiplierButton.OnClick = () => {
      const action = new BuyPaidMultiplierAction();
      if (!this.getActionBlocker(action)) {
        this.consumeAction(action, ["钻石购买下一档付费倍率"]);
      }
      this.UpdateUI();
    };
    this.autoBuyPaidMultiplierButton = new UIButton(this.UIRoot, {
      Name: "AutoBuyPaidMultiplier", X: 896, Y: 60, Width: 64, Height: 30, FontSize: 10, TextWrap: false,
    });
    this.autoBuyPaidMultiplierButton.OnClick = () => {
      this.consumeAction(new SetAutoBuyPaidMultiplierAction(!this.state.autoBuyPaidMultiplier));
      this.tryAutoBuyPaidMultiplier();
      this.UpdateUI();
    };
    this.replaceRecommendedButton = new UIButton(this.UIRoot, {
      Name: "ReplaceRecommended", X: 12, Y: 488, Width: 132, Height: 30,
      FontSize: 12, Text: "一键置换", ButtonColor: "#fff0b3",
      TextColor: "#795611", BorderColor: "#d9b64c",
    });
    this.replaceRecommendedButton.OnClick = () => {
      for (const slotId of this.getRecommendedReplacementSlotIds()) {
        const action = new QueueSwordReplacementAction(slotId, this.state.forgeTargetOffset);
        if (!this.getActionBlocker(action)) {
          this.consumeAction(action, [`推荐槽位 ${slotId} 加入置换升级队列`]);
        }
      }
      this.executeNextReplacement();
      this.UpdateUI();
    };
    this.autoUnlockSlotsButton = new UIButton(this.UIRoot, {
      Name: "AutoUnlockSlots", X: 156, Y: 488, Width: 156, Height: 30,
      FontSize: 12, TextWrap: false,
    });
    this.autoUnlockSlotsButton.OnClick = () => {
      this.consumeAction(new SetAutoUnlockSlotsAction(!this.state.autoUnlockSlots));
      this.tryAutoUnlockSlots();
      this.UpdateUI();
    };
  }

  BuildEditorUI(): void {
    if (this.state.miningRefreshElapsedSeconds < 0) {
      this.consumeAction(new InitializeMiningOresAction(), ["开局立即刷新矿石"], "system");
    }
    this.grantDailyDiamonds(this.getScheduleContext()?.day ?? 1);
    this.tryAutoBuyPaidMultiplier();
    this.tryAutoUnlockSlots();
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
    this.tryAutoUnlockSlots();
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

  private tryAutoUnlockSlots(): void {
    while (this.state.autoUnlockSlots) {
      const slot = this.state.slots.find((item) => !item.unlocked);
      if (!slot) {
        break;
      }
      const action = new UnlockSlotAction(slot.id);
      if (this.getActionBlocker(action) || !this.consumeAction(action, [`自动解锁槽位 ${slot.id}`], "system")) {
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
    this.queueSwordReplacement(this.selectedSlotId);
  }

  queueSwordReplacement(slotId: number): void {
    if (!this.isSlotReplacementRecommended(slotId)) {
      return;
    }
    const action = new QueueSwordReplacementAction(slotId, this.state.forgeTargetOffset);
    if (!this.getActionBlocker(action)) {
      this.consumeAction(action, [`槽位 ${slotId} 加入置换升级队列`]);
    }
    this.executeNextReplacement();
    this.UpdateUI();
  }

  isSlotReplacementRecommended(slotId: number): boolean {
    const slot = this.state.slots.find((item) => item.id === slotId);
    return slot !== undefined && isSwordReplacementRecommended(this.config, this.state, slot);
  }

  private getRecommendedReplacementSlotIds(): number[] {
    return this.state.slots.filter((slot) => this.isSlotReplacementRecommended(slot.id)).map((slot) => slot.id);
  }

  createSlotUpgradeAction(slotId: number): UnlockSlotAction | QueueSwordReplacementAction | UpgradeSwordMaxAction {
    const slot = this.state.slots.find((item) => item.id === slotId);
    if (!slot?.unlocked) {
      return new UnlockSlotAction(slotId);
    }
    return slot.swordId === null ? new QueueSwordReplacementAction(slotId, this.state.forgeTargetOffset) : new UpgradeSwordMaxAction(slotId);
  }

  upgradeSlot(slotId: number): void {
    const action = this.createSlotUpgradeAction(slotId);
    if (!this.getActionBlocker(action)) {
      this.consumeAction(action, [`槽位 ${slotId} 执行一键解锁、排队获取或升级`]);
      if (action instanceof QueueSwordReplacementAction) {
        this.executeNextReplacement();
      }
    }
    this.UpdateUI();
  }

  advanceOneSecond(): void {
    this.tryAutoBuyPaidMultiplier();
    this.tryAutoUnlockSlots();
    this.executeNextReplacement();
  }

  private executeNextReplacement(): void {
    const request = this.state.pendingReplacements[0];
    if (!request) {
      return;
    }
    const { slotId } = request;
    const action = new ReplaceSwordAction(slotId);
    if (!this.getActionBlocker(action) &&
        this.consumeAction(action, [`尝试锻造并置换队首槽位 ${slotId}`]) &&
        this.state.lastForgeResult?.slotId === slotId) {
      const upgrade = new UpgradeSwordMaxAction(slotId, {}, 5);
      if (!this.getActionBlocker(upgrade)) {
        this.consumeAction(upgrade, [`自动补升槽位 ${slotId} 的新武器，最高 5 级`]);
      }
    }
  }

  UpdateUI(): void {
    const tier = this.state.paidMultiplierTier;
    const curves = this.config.paidMultiplierCurves;
    const income = calculateBaseIncome(this.config, this.state.slots, this.state.swords, this.state.playerUpgradeLevels.income, tier);
    const purchasedTiers = Array.from({ length: tier - curves.input.min! + 1 }, (_, index) =>
      `×${calculatePaidMultiplier(this.config, curves.input.min! + index)}`);
    this.paidSummaryLabel.Text = `收益 ${income.toFixed(2)}/s ｜ 付费倍率 ${purchasedTiers.join(" ")} ｜ 钻石 ${this.state.diamonds}`;
    const next = getNextPaidMultiplier(this.config, tier);
    const buyBlocker = this.getActionBlocker(new BuyPaidMultiplierAction());
    this.buyPaidMultiplierButton.Disabled = buyBlocker !== null;
    this.buyPaidMultiplierButton.ButtonColor = buyBlocker ? "#f9e2ad" : "#f6ce7c";
    this.buyPaidMultiplierButton.TextColor = "#6d4817";
    this.buyPaidMultiplierButton.BorderColor = "#d9b979";
    this.buyPaidMultiplierButton.Text = next
      ? `付费 ×${next.multiplier} · ${next.price} 钻${buyBlocker ? "（不足）" : ""}`
      : "付费倍率已满档";
    this.autoBuyPaidMultiplierButton.Text = `自动${this.state.autoBuyPaidMultiplier ? "开" : "关"}`;
    this.autoBuyPaidMultiplierButton.ButtonColor = this.state.autoBuyPaidMultiplier ? "#bbdfd4" : "#e9eef5";
    this.autoBuyPaidMultiplierButton.TextColor = this.state.autoBuyPaidMultiplier ? "#24564d" : "#526782";
    this.autoBuyPaidMultiplierButton.BorderColor = this.state.autoBuyPaidMultiplier ? "#8bbfaf" : "#c6d1e1";
    this.autoUnlockSlotsButton.Text = `自动解锁：${this.state.autoUnlockSlots ? "开" : "关"}`;
    this.autoUnlockSlotsButton.ButtonColor = this.state.autoUnlockSlots ? "#bbdfd4" : "#e9eef5";
    this.autoUnlockSlotsButton.TextColor = this.state.autoUnlockSlots ? "#24564d" : "#526782";
    this.autoUnlockSlotsButton.BorderColor = this.state.autoUnlockSlots ? "#8bbfaf" : "#c6d1e1";
    const recommendedSlotIds = this.getRecommendedReplacementSlotIds();
    this.replaceRecommendedButton.Disabled = !recommendedSlotIds.some((slotId) =>
      this.getActionBlocker(new QueueSwordReplacementAction(slotId, this.state.forgeTargetOffset)) === null);
    const mutationNames = ["普通", "银质", "黄金", "冰霜", "烈焰", "星界", "钻石", "彩虹"];
    const mutationColors = ["#64748b", "#28834b", "#2872c4", "#8542bd", "#b87908", "#c23c51", "#c557be", "#e79f24"];
    const oreCounts = new Map<number, number>();
    for (const ore of this.state.miningOres) {
      oreCounts.set(ore.mutationId, (oreCounts.get(ore.mutationId) ?? 0) + 1);
    }
    const oreSummary = [...oreCounts].sort(([a], [b]) => a - b)
      .map(([id, count]) => `<span color="${mutationColors[id - 1]}">${mutationNames[id - 1]} ×${count}</span>`).join(" · ");
    this.oreSummaryLabel.Text = oreSummary ? `<b>矿石 ${this.state.miningOres.length}</b>｜${oreSummary}` : "矿石：暂无";
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
        button.Text = `${title} L${level} · ${blocker.kind === "playerUpgradeOrder" ? "待前项升级" : blocker.reason}`;
        return;
      }
      const curves = getPlayerUpgradeCurves(this.config, kind);
      button.Text = `${title} L${level} · ${calculatePlayerUpgradePrice(curves, level)}金币${blocker ? "（不足）" : ""}`;
    });
    this.slotLabels.forEach((labels, index) => {
      const slot = this.state.slots[index];
      const sword = this.state.swords.find((item) => item.id === slot.swordId);
      const recommendReplacement = recommendedSlotIds.includes(slot.id);
      labels.id.Text = `${slot.id}`;
      const hasSword = slot.unlocked && sword !== undefined;
      labels.mutation.Visible = hasSword;
      labels.mutation.Text = hasSword ? mutationNames[sword.mutationId - 1] : "";
      labels.mutation.TextColor = hasSword ? mutationColors[sword.mutationId - 1] : "#64748b";
      labels.button.Text = slot.unlocked ? (sword ? "" : "空槽位") : "未解锁";
      labels.stats.Visible = hasSword;
      labels.income.Visible = hasSword;
      if (hasSword) {
        const slotIncome = calculateBaseIncome(this.config, [slot], this.state.swords, this.state.playerUpgradeLevels.income, tier);
        const formattedIncome = slotIncomeFormat.format(slotIncome);
        const incomeText = formattedIncome.length > 8 ? slotIncome.toExponential(1) : formattedIncome;
        labels.income.Text = `<b>${incomeText}</b><span font-size="10">/s</span>`;
        labels.stats.Text = `品质 ${sword.quality} · Lv.${sword.level}`;
      }
      const queued = slot.unlocked && this.state.pendingReplacements.some((request) => request.slotId === slot.id);
      labels.queue.Visible = queued || recommendReplacement;
      labels.queue.Text = queued ? "排队中" : recommendReplacement ? "推荐置换" : "";
      labels.button.ButtonColor = recommendReplacement ? "#fff0b3" : slot.unlocked ? (sword ? "#edf7ef" : "#e0f2e5") : "#e1ecfb";
      labels.button.TextColor = recommendReplacement ? "#795611" : slot.unlocked ? "#285e3c" : "#36577f";
      labels.button.BorderColor = slot.id === this.selectedSlotId ? "#f79009" : recommendReplacement ? "#d9b64c" : slot.unlocked ? "#91c7a3" : "#a6c1e5";
    });
  }
}
