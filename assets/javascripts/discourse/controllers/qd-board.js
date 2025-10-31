import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { service } from "@ember/service";

export default class QdBoardController extends Controller {
  @service siteSettings;
  
  @tracked isLoading = false;

  // 获取当前主题设置
  get boardTheme() {
    return this.siteSettings?.jifen_board_theme || 'neo';
  }
  @tracked nextUpdateMinutes = 3;
  @tracked countdownTimer = null;

  // 检查是否需要登录
  get requiresLogin() {
    return this.model?.requires_login || false;
  }

  get loginMessage() {
    return this.model?.message || "请登录后查看积分排行榜";
  }

  // 检查是否为管理员
  get isAdmin() {
    return this.model?.is_admin || false;
  }

  // 获取更新间隔（从站点设置读取）
  get updateIntervalMinutes() {
    return this.siteSettings?.jifen_leaderboard_update_minutes || 3;
  }

  // 排序后的前五
  get sortedTop() {
    return (this.model?.top || []).slice().sort((a, b) => a.rank - b.rank).slice(0, 5);
  }

  // 前三名选择器，便于模板定点布局
  get firstUser() {
    return this.sortedTop.find((u) => u.rank === 1) || this.sortedTop[0];
  }
  get secondUser() {
    return this.sortedTop.find((u) => u.rank === 2) || this.sortedTop[1];
  }
  get thirdUser() {
    return this.sortedTop.find((u) => u.rank === 3) || this.sortedTop[2];
  }

  // 其余 4-5 名
  get restList() {
    return this.sortedTop.filter((u) => u.rank > 3);
  }

  medalClass(rank) {
    if (rank === 1) return "board-medal board-medal--gold";
    if (rank === 2) return "board-medal board-medal--silver";
    if (rank === 3) return "board-medal board-medal--bronze";
    return "board-medal board-medal--none";
  }

  // 启动倒计时
  startCountdown() {
    // 清除之前的定时器
    if (this.countdownTimer) {
      clearInterval(this.countdownTimer);
    }

    // 基于服务器更新时间计算真实的倒计时
    this.updateCountdown();

    // 每秒更新一次倒计时，确保精确同步
    this.countdownTimer = setInterval(() => {
      this.updateCountdown();
    }, 1000); // 1秒更新一次
  }

  // 获取更新间隔（从站点设置读取）
  get updateIntervalMinutes() {
    return this.siteSettings?.jifen_leaderboard_update_minutes || 3;
  }

  updateCountdown() {
    if (!this.model?.updatedAt) {
      this.nextUpdateMinutes = this.updateIntervalMinutes;
      return;
    }

    try {
      const lastUpdated = new Date(this.model.updatedAt);
      const now = new Date();
      const timeSinceUpdate = now - lastUpdated;
      const updateInterval = this.updateIntervalMinutes * 60 * 1000; // 转换为毫秒
      
      // 计算距离下次更新的剩余时间
      const timeUntilNext = updateInterval - (timeSinceUpdate % updateInterval);
      const minutesLeft = Math.ceil(timeUntilNext / (60 * 1000));
      
      this.nextUpdateMinutes = Math.max(0, minutesLeft);
      
      // 移除自动刷新功能，只显示倒计时
    } catch (error) {
      console.error("计算倒计时失败:", error);
      this.nextUpdateMinutes = this.updateIntervalMinutes;
    }
  }

  // 清理定时器
  willDestroy() {
    super.willDestroy();
    if (this.countdownTimer) {
      clearInterval(this.countdownTimer);
    }
  }

  async loadLeaderboard() {
    try {
      const data = await ajax("/qd/board_data.json");
      // 更新模型数据
      this.model.top = data.leaderboard || [];
      this.model.updatedAt = data.updated_at || new Date().toISOString();
      this.model.is_admin = data.is_admin || false;
      this.model.requires_login = data.requires_login || false;
      this.model.message = data.message || "";
      
      // 触发页面重新渲染，确保新数据显示
      this.notifyPropertyChange('model');
    } catch (error) {
      console.error("加载排行榜失败:", error);
    }
  }

  @action
  async refreshBoard() {
    if (!this.isAdmin) {
      return; // 非管理员不显示刷新按钮，这里作为保护
    }

    this.isLoading = true;
    try {
      const result = await ajax("/qd/force_refresh_board.json", {
        type: "POST"
      });
      
      if (result.success) {
        // 更新模型数据
        this.model.top = result.leaderboard || [];
        this.model.updatedAt = result.updated_at;
        
        // 强制触发页面重新渲染
        this.notifyPropertyChange('model');
        this.notifyPropertyChange('sortedTop');
        this.notifyPropertyChange('firstUser');
        this.notifyPropertyChange('secondUser');
        this.notifyPropertyChange('thirdUser');
        this.notifyPropertyChange('restList');
        
        // 重启倒计时（基于新的更新时间）
        this.startCountdown();
        
        // 显示成功提示
        console.log("排行榜已强制刷新，新数据:", result.leaderboard);
      }
    } catch (error) {
      console.error("强制刷新排行榜失败:", error);
    } finally {
      this.isLoading = false;
    }
  }
}