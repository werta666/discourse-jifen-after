import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";

export default class QdTpController extends Controller {
  @tracked isLoading = false;
  @tracked selectedEvent = null;
  @tracked selectedOption = null;
  @tracked betAmount = 100;
  @tracked showBetModal = false;

  // 获取活跃的赛事
  get activeEvents() {
    return this.model?.events?.filter(event => event.status === "active") || [];
  }

  // 获取已结束的赛事
  get finishedEvents() {
    return this.model?.events?.filter(event => event.status === "finished") || [];
  }

  // 计算倒计时
  getTimeRemaining(endTime) {
    const now = new Date();
    const end = new Date(endTime);
    const diff = end - now;
    
    if (diff <= 0) return "⏰ 已结束";
    
    const hours = Math.floor(diff / (1000 * 60 * 60));
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    
    if (hours > 0) {
      return `⏳ ${hours}小时${minutes}分钟后结束`;
    } else {
      return `⏳ ${minutes}分钟后结束`;
    }
  }

  // 计算预期收益
  get potentialWin() {
    if (!this.selectedOption || !this.betAmount) return 0;
    return Math.floor(this.betAmount * this.selectedOption.odds);
  }

  @action
  openBetModal(event, option) {
    if (!this.model.isLoggedIn) {
      alert("请先登录后再进行投注！");
      return;
    }
    
    this.selectedEvent = event;
    this.selectedOption = option;
    this.betAmount = 100;
    this.showBetModal = true;
  }

  @action
  closeBetModal() {
    this.showBetModal = false;
    this.selectedEvent = null;
    this.selectedOption = null;
  }

  @action
  updateBetAmount(event) {
    this.betAmount = parseInt(event.target.value) || 0;
  }

  @action
  setQuickAmount(amount) {
    this.betAmount = Math.min(amount, this.model.userBalance);
  }

  @action
  stopPropagation(event) {
    event.stopPropagation();
  }

  @action
  async placeBet() {
    if (!this.selectedEvent || !this.selectedOption || this.betAmount <= 0) {
      alert("请选择有效的投注金额！");
      return;
    }

    if (this.betAmount > this.model.userBalance) {
      alert("积分不足！请减少投注金额或充值积分。");
      return;
    }

    this.isLoading = true;
    
    try {
      const result = await ajax("/qd/tp_vote.json", {
        type: "POST",
        data: {
          event_id: this.selectedEvent.id,
          option_id: this.selectedOption.id,
          bet_amount: this.betAmount
        }
      });

      if (result.success) {
        // 更新用户余额
        this.model.userBalance = result.new_balance;
        
        // 更新投票数据（模拟）
        this.selectedOption.votes += 1;
        this.selectedOption.pool += this.betAmount;
        this.selectedEvent.total_votes += 1;
        this.selectedEvent.total_pool += this.betAmount;
        
        alert(`🎉 投票成功！\n投注 ${this.betAmount} 积分到 ${this.selectedOption.name}\n预期收益: ${this.potentialWin} 积分`);
        this.closeBetModal();
      }
    } catch (error) {
      console.error("投票失败:", error);
      if (error.jqXHR?.status === 403) {
        alert("❌ 请先登录后再进行投注！");
      } else {
        alert("❌ 投票失败，请重试");
      }
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async refreshData() {
    this.isLoading = true;
    try {
      // 直接拉取最新数据并更新模型
      const result = await ajax("/qd/tp_data.json");
      if (result.success) {
        this.model = {
          events: result.events || [],
          userBalance: result.user_balance || 0,
          isLoggedIn: result.is_logged_in || false,
          isAdmin: result.is_admin || false
        };
      }
    } catch (error) {
      console.error("刷新数据失败:", error);
      alert("刷新失败，请重试");
    } finally {
      this.isLoading = false;
    }
  }
}