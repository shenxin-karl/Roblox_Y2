import { ChartSet, sampleCurveGroupColumn } from "@game-simulator/framework";
import { calculateSwordLevelMultiplier } from "./Formulas";
import type { ProjectConfig } from "./Main";

export class ProjectCharts extends ChartSet {
  static ChartNames = {
    chartSwordUpgrade: "武器升级",
  };

  chartSwordUpgrade() {
    const config = this.config as ProjectConfig;
    const curves = config.swordUpgradeCurves;
    const { min = 1, max = Infinity } = curves.input;
    const minX = Math.ceil(min);
    const incomeMultiplier = (level: number) => calculateSwordLevelMultiplier(curves, level);
    const costMultiplier = (level: number) => level + 1 <= max
      ? sampleCurveGroupColumn(curves, "upgradeCost", level)
      : NaN;

    return {
      variable: "level",
      xLabel: "武器等级",
      yLabel: "数值（单位见图例）",
      minX,
      maxX: Math.min(Math.floor(max), Math.max(100, minX)),
      step: 1,
      series: [
        { id: "current", label: "收益倍率（倍）", sample: incomeMultiplier },
        { id: "costMultiplier", label: "升级消耗倍率（倍）", sample: costMultiplier },
        {
          id: "secondsToUpgrade",
          label: "升级耗时（秒）",
          sample: (level: number) => {
            const income = incomeMultiplier(level);
            return income > 0 ? costMultiplier(level) / income : NaN;
          },
        },
      ],
    };
  }
}
