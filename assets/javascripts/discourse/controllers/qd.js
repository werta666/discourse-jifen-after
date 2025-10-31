import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";

export default class QdController extends Controller {
  // 界面状态
  @tracked isLoading = false;

  // 数据集合
  @tracked records = [];
  @tracked missingDays = [];

  // 管理员调试面板状态与表单
  @tracked showDebugModal = false;
  @tracked adminUsernameAdjust = "";
  @tracked adminDelta = 0;
  @tracked adminUsernameReset = "";
  @tracked adminMessage = null;
  @tracked adminError = null;

  // 购买确认与反馈
  @tracked showBuyConfirm = false;
  @tracked buyMessage = null;
  @tracked buyError = null;

  // 补签确认与反馈
  @tracked showMakeupConfirm = false;
  @tracked selectedMakeupDate = null;
  @tracked makeupMessage = null;
  @tracked makeupError = null;

  // VIP签到奖励提示
  @tracked showVipSigninBonus = false;
  @tracked vipSigninBonusInfo = null;

  // 奖励提示文本（基于设置中的 JSON 连续奖励与当前连续天数）
  get rewardText() {
    const rewards = this.model?.rewards || {};
    const streak = Number(this.model?.consecutive_days || 0);

    const entries = Object.keys(rewards)
      .map((k) => [parseInt(k, 10), parseInt(rewards[k], 10)])
      .filter(([d, p]) => Number.isFinite(d) && Number.isFinite(p))
      .sort((a, b) => a[0] - b[0]);

    for (const [days, pts] of entries) {
      if (days > streak) {
        const remain = days - streak;
        return `再签到 ${remain} 天可获得额外 ${pts} 积分奖励`;
      }
    }
    return "继续保持签到，可解锁更高奖励";
  }

  // 新增：避免模板依赖 lt/le helper，直接提供布尔字段
  get noMakeupCards() {
    const m = this.model || {};
    const count = Number(m.makeup_cards || 0);
    return count <= 0;
  }

  get insufficientPoints() {
    const m = this.model || {};
    const total = Number(m.total_score || 0);
    const price = Number(m.makeup_card_price || 0);
    return total < price;
  }

  // 加载签到记录（倒序），后端已限制最近 7 天
  async loadRecords() {
    try {
      const data = await ajax("/qd/records.json");
      this.records = data.records || [];
      this.missingDays = this._computeRecentMissingDays(this.records);
    } catch {
      this.records = [];
      this.missingDays = [];
    }
  }

  // 计算最近 7 天缺勤（不含今天），用于“补签功能”占位展示
  _computeRecentMissingDays(records) {
    try {
      const signedSet = new Set((records || []).map((r) => r.date));
      const result = [];
      const today = new Date();
      const installStr = this.model?.install_date;
      const installDate = installStr ? new Date(installStr) : today;

      for (let i = 1; i <= 7; i++) {
        const d = new Date(today);
        d.setDate(today.getDate() - i);
        const s = d.toISOString().slice(0, 10);

        // 仅允许系统启用日期（含）之后的日期可补签
        if (installDate && d < installDate) {
          continue;
        }

        if (!signedSet.has(s)) {
          result.push({ date: s, formatted_date: s });
        }
      }
      return result;
    } catch {
      return [];
    }
  }

  // 今日签到
  @action
  async signIn() {
    if (this.isLoading) return;
    this.isLoading = true;
    try {
      const data = await ajax("/qd/signin.json", { type: "POST" });
      // 后端返回最新 summary，直接替换 model
      this.model = data;
      await this.loadRecords();
      
      // 检查是否有VIP签到奖励
      if (data.vip_signin_bonus) {
        this.vipSigninBonusInfo = data.vip_signin_bonus;
        this.showVipSigninBonus = true;
      }
    } catch {
      // 保持静默
    } finally {
      this.isLoading = false;
    }
  }

  // 关闭VIP签到奖励提示
  @action
  closeVipSigninBonus() {
    this.showVipSigninBonus = false;
    this.vipSigninBonusInfo = null;
  }

  // 补签：先弹出确认，不直接提交
  @action
  async makeupSign(date) {
    this.openMakeupConfirm(date);
  }

  @action
  openMakeupConfirm(date) {
    this.selectedMakeupDate = date;
    this.makeupMessage = null;
    this.makeupError = null;
    this.showMakeupConfirm = true;
  }

  @action
  cancelMakeupConfirm() {
    this.showMakeupConfirm = false;
  }

  @action
  async confirmMakeupSign() {
    if (this.isLoading) return;
    this.isLoading = true;
    this.makeupMessage = null;
    this.makeupError = null;
    try {
      const data = await ajax("/qd/makeup.json", {
        type: "POST",
        data: { date: this.selectedMakeupDate }
      });
      // 应用后端最新概览（可用积分、补签卡数、连续天数等）
      this.model = data;
      // 优先使用 summary 携带的 recent_records，避免额外请求
      this.records = Array.isArray(data.recent_records) ? data.recent_records : [];
      // 重新计算“可补签日期”（已包含启用日过滤）
      this.missingDays = this._computeRecentMissingDays(this.records);
      this.makeupMessage = `补签成功：${this.selectedMakeupDate} 已补签（消耗 1 张补签卡）`;
      this.showMakeupConfirm = false;
    } catch (e) {
      this.makeupError =
        (e?.jqXHR?.responseJSON?.errors?.[0]) || e?.message || "补签失败";
    } finally {
      this.isLoading = false;
    }
  }

  // 购买补签卡：先弹出二次确认，不直接下单
  @action
  async buyMakeupCard() {
    if (this.isLoading) return;
    this.buyMessage = null;
    this.buyError = null;
    this.showBuyConfirm = true;
  }

  // 确认购买补签卡
  @action
  async confirmBuyMakeupCard() {
    if (this.isLoading) return;
    this.isLoading = true;
    this.buyMessage = null;
    this.buyError = null;
    try {
      const data = await ajax("/qd/buy_makeup_card.json", { type: "POST" });
      // 应用后端最新概览（可用积分、补签卡数、连续天数等）
      this.model = data;
      await this.loadRecords();
      this.buyMessage = "购买成功：已增加 1 张补签卡，并更新可用积分";
      this.showBuyConfirm = false;
    } catch (e) {
      this.buyError = (e?.jqXHR?.responseJSON?.errors?.[0]) || e?.message || "购买失败";
    } finally {
      this.isLoading = false;
    }
  }

  // 取消购买
  @action
  cancelBuyConfirm() {
    this.showBuyConfirm = false;
  }

  // 管理员调试：打开/关闭弹窗
  @action
  openAdminDebug() {
    this.adminMessage = null;
    this.adminError = null;
    this.showDebugModal = true;
  }

  @action
  closeAdminDebug() {
    this.showDebugModal = false;
  }

  // 管理员调试：手动调整积分（可增可减）
  @action
  async adjustPoints() {
    if (this.isLoading) return;
    this.adminMessage = null;
    this.adminError = null;
    this.isLoading = true;
    try {
      const resp = await ajax("/qd/admin/adjust_points.json", {
        type: "POST",
        data: {
          username: this.adminUsernameAdjust,
          delta: this.adminDelta
        }
      });
      this.adminMessage = `已调整用户 ${resp.target_username} 的可用积分：${resp.before_available} → ${resp.after_available}`;
      // 若调整的是当前登录用户，同步刷新概览（以服务器为准）
      if (
        this.model &&
        this.currentUser &&
        this.adminUsernameAdjust &&
        this.adminUsernameAdjust.toLowerCase() === this.currentUser.username_lower
      ) {
        try {
          this.model = await ajax("/qd/summary.json");
        } catch {}
      }
    } catch (e) {
      this.adminError = (e?.jqXHR?.responseJSON?.errors?.[0]) || e?.message || "调整失败";
    } finally {
      this.isLoading = false;
    }
  }

  // 管理员调试：重置指定用户“今日签到”状态
  @action
  async resetToday() {
    if (this.isLoading) return;
    this.adminMessage = null;
    this.adminError = null;
    this.isLoading = true;
    try {
      const resp = await ajax("/qd/admin/reset_today.json", {
        type: "POST",
        data: {
          username: this.adminUsernameReset
        }
      });
      this.adminMessage = `已重置 ${resp.target_username} 的今日签到（删除记录：${resp.removed} 条）`;
      // 如重置的是当前用户，刷新概览与记录
      if (
        this.model &&
        this.currentUser &&
        this.adminUsernameReset &&
        this.adminUsernameReset.toLowerCase() === this.currentUser.username_lower
      ) {
        try {
          this.model = await ajax("/qd/summary.json");
          await this.loadRecords();
        } catch {}
      }
    } catch (e) {
      this.adminError = (e?.jqXHR?.responseJSON?.errors?.[0]) || e?.message || "重置失败";
    } finally {
      this.isLoading = false;
    }
  }



  // 兼容旧按钮名（已改为开启调试面板）
  @action
  async syncAllScores() {
    this.openAdminDebug();
  }
}
