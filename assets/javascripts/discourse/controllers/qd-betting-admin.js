import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";

export default class QdBettingAdminController extends Controller {
  @tracked isLoading = false;
  @tracked selectedEvent = null;
  @tracked showSettleModal = false;
  @tracked selectedWinnerOptionId = null;
  
  // 决斗相关
  @tracked showDuels = false;
  @tracked duels = [];
  @tracked duelStatusFilter = "all";
  @tracked showDuelSettleModal = false;
  @tracked showDuelCancelModal = false;
  @tracked selectedDuel = null;
  @tracked selectedDuelWinnerId = null;
  @tracked duelSettleNote = "";
  @tracked duelCancelReason = "";

  // 获取待处理的事件
  get pendingEvents() {
    return this.model?.events?.filter(e => e.status === "pending") || [];
  }

  // 获取进行中的事件
  get activeEvents() {
    return this.model?.events?.filter(e => e.status === "active") || [];
  }

  // 获取已结束的事件
  get finishedEvents() {
    return this.model?.events?.filter(e => e.status === "finished") || [];
  }

  @action
  async activateEvent(event) {
    if (!confirm(`确定要激活事件 "${event.title}" 吗？`)) {
      return;
    }

    this.isLoading = true;

    try {
      const result = await ajax(`/qd/betting/admin/events/${event.id}/activate.json`, {
        type: "POST"
      });

      if (result.success) {
        alert("✅ 事件已激活");
        this.refreshData();
      }
    } catch (error) {
      console.error("激活失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "激活失败";
      alert("❌ " + errorMsg);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async finishEvent(event) {
    if (!confirm(`确定要结束事件 "${event.title}" 吗？`)) {
      return;
    }

    this.isLoading = true;

    try {
      const result = await ajax(`/qd/betting/admin/events/${event.id}/finish.json`, {
        type: "POST"
      });

      if (result.success) {
        alert("✅ 事件已结束");
        this.refreshData();
      }
    } catch (error) {
      console.error("结束失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "结束失败";
      alert("❌ " + errorMsg);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async cancelEvent(event) {
    const statusText = event.status === 'active' ? '【进行中】' : event.status === 'pending' ? '【待开始】' : '';
    let message;
    
    if (event.event_type === 'vote') {
      // 普通投票：不涉及积分退还
      message = `确定要取消${statusText}事件 "${event.title}" 吗？\n\n📊 这是一个普通投票，无需退还积分。`;
    } else if (event.total_bets > 0) {
      // 积分竞猜且有投注：需要退款
      message = `确定要取消${statusText}事件 "${event.title}" 吗？\n\n⚠️ 此事件有 ${event.total_bets} 笔投注，取消后将自动退还所有积分给参与者。`;
    } else {
      // 无投注
      message = `确定要取消${statusText}事件 "${event.title}" 吗？`;
    }
    
    if (!confirm(message)) {
      return;
    }

    this.isLoading = true;

    try {
      const result = await ajax(`/qd/betting/admin/events/${event.id}/cancel.json`, {
        type: "POST"
      });

      if (result.success) {
        alert("✅ " + result.message);
        this.refreshData();
      }
    } catch (error) {
      console.error("取消失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "取消失败";
      alert("❌ " + errorMsg);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async deleteEvent(event) {
    if (!confirm(`确定要删除事件《${event.title}》吗？\n此操作不可撤销！`)) {
      return;
    }

    this.isLoading = true;

    try {
      const result = await ajax(`/qd/betting/admin/events/${event.id}.json`, {
        type: "DELETE"
      });

      if (result.success) {
        alert("✅ " + result.message);
        this.refreshData();
      }
    } catch (error) {
      console.error("删除失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "删除失败";
      alert("❌ " + errorMsg);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  openSettleModal(event) {
    this.selectedEvent = event;
    this.selectedWinnerOptionId = null;
    this.showSettleModal = true;
  }

  @action
  closeSettleModal() {
    this.showSettleModal = false;
    this.selectedEvent = null;
    this.selectedWinnerOptionId = null;
  }

  @action
  selectWinner(optionId) {
    this.selectedWinnerOptionId = optionId;
  }

  @action
  async settleEvent() {
    if (!this.selectedWinnerOptionId) {
      alert("请先选择获胜选项");
      return;
    }

    if (!confirm("确定要结算该事件吗？此操作不可撤销。")) {
      return;
    }

    this.isLoading = true;

    try {
      // 先设置获胜选项
      await ajax(`/qd/betting/admin/events/${this.selectedEvent.id}/set_winner.json`, {
        type: "POST",
        data: {
          option_id: this.selectedWinnerOptionId
        }
      });

      // 再执行结算
      const result = await ajax(`/qd/betting/admin/events/${this.selectedEvent.id}/settle.json`, {
        type: "POST"
      });

      if (result.success) {
        const settlement = result.settlement_result;
        let message = "✅ 结算完成！\n\n";
        message += `总奖池: ${settlement.total_pool}\n`;
        message += `获胜者: ${settlement.winner_count} 人\n`;
        message += `失败者: ${settlement.loser_count} 人\n`;
        message += `总发放: ${settlement.total_payout}\n`;
        message += `平台手续费: ${settlement.platform_fee}`;
        
        alert(message);
        this.closeSettleModal();
        this.refreshData();
      }
    } catch (error) {
      console.error("结算失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "结算失败";
      alert("❌ " + errorMsg);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async refreshData() {
    this.isLoading = true;
    try {
      const result = await ajax("/qd/betting/admin/events.json");
      if (result.success) {
        // 使用set触发响应式更新
        this.set("model.events", result.events || []);
        this.notifyPropertyChange("model.events");
        
        console.log("[管理后台] 数据已更新:", {
          events: result.events?.length || 0
        });
      }
    } catch (error) {
      console.error("刷新失败:", error);
    } finally {
      this.isLoading = false;
    }
  }

  // 启动自动刷新
  startAutoRefresh() {
    // 先停止之前的定时器（如果有）
    this.stopAutoRefresh();
    // 每15秒自动刷新一次
    this.autoRefreshInterval = setInterval(() => {
      console.log("[管理后台] 自动刷新数据...");
      this.refreshData();
    }, 15000);
  }

  // 停止自动刷新
  stopAutoRefresh() {
    if (this.autoRefreshInterval) {
      clearInterval(this.autoRefreshInterval);
      this.autoRefreshInterval = null;
    }
  }

  @action
  stopPropagation(event) {
    event.stopPropagation();
  }

  // ========== 决斗管理相关方法 ==========

  // 切换到决斗tab时加载数据
  @action
  async switchToDuels() {
    this.showDuels = true;
    if (this.duels.length === 0) {
      await this.loadDuels();
    }
  }

  // 筛选后的决斗列表
  get filteredDuels() {
    if (this.duelStatusFilter === "all") {
      return this.duels;
    }
    return this.duels.filter(d => d.status === this.duelStatusFilter);
  }

  @action
  async loadDuels() {
    this.isLoading = true;
    try {
      const result = await ajax("/qd/duel/admin/list.json", {
        type: "GET",
        data: {
          status: this.duelStatusFilter === "all" ? null : this.duelStatusFilter
        }
      });

      if (result.success) {
        this.duels = result.duels || [];
      }
    } catch (error) {
      console.error("加载决斗失败:", error);
      alert("加载决斗列表失败");
    } finally {
      this.isLoading = false;
    }
  }

  @action
  setDuelFilter(status) {
    this.duelStatusFilter = status;
    this.loadDuels();
  }

  @action
  openDuelSettleModal(duel) {
    this.selectedDuel = duel;
    this.selectedDuelWinnerId = null;
    this.duelSettleNote = "";
    this.showDuelSettleModal = true;
  }

  @action
  closeDuelSettleModal() {
    this.showDuelSettleModal = false;
    this.selectedDuel = null;
    this.selectedDuelWinnerId = null;
    this.duelSettleNote = "";
  }

  @action
  selectDuelWinner(userId) {
    this.selectedDuelWinnerId = userId;
  }

  @action
  updateDuelSettleNote(event) {
    this.duelSettleNote = event.target.value;
  }

  @action
  async settleDuel() {
    if (!this.selectedDuelWinnerId) {
      alert("请选择获胜者");
      return;
    }

    if (!confirm("确定要结算此决斗吗？此操作不可撤销。")) {
      return;
    }

    this.isLoading = true;

    try {
      const result = await ajax(`/qd/duel/admin/${this.selectedDuel.id}/settle.json`, {
        type: "POST",
        data: {
          winner_id: this.selectedDuelWinnerId,
          note: this.duelSettleNote || null
        }
      });

      if (result.success) {
        alert("✅ " + result.message);
        this.closeDuelSettleModal();
        this.loadDuels();
      }
    } catch (error) {
      console.error("结算失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "结算失败";
      alert("❌ " + errorMsg);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  openDuelCancelModal(duel) {
    this.selectedDuel = duel;
    this.duelCancelReason = "";
    this.showDuelCancelModal = true;
  }

  @action
  closeDuelCancelModal() {
    this.showDuelCancelModal = false;
    this.selectedDuel = null;
    this.duelCancelReason = "";
  }

  @action
  updateDuelCancelReason(event) {
    this.duelCancelReason = event.target.value;
  }

  @action
  async cancelDuel() {
    if (!this.duelCancelReason || this.duelCancelReason.trim().length < 5) {
      alert("请输入取消理由（至少5个字符）");
      return;
    }

    if (!confirm("确定要取消此决斗吗？\n\n双方积分将退还，并发送通知。此操作不可撤销。")) {
      return;
    }

    this.isLoading = true;

    try {
      const result = await ajax(`/qd/duel/admin/${this.selectedDuel.id}/cancel.json`, {
        type: "POST",
        data: {
          reason: this.duelCancelReason.trim()
        }
      });

      if (result.success) {
        alert("✅ " + result.message);
        this.closeDuelCancelModal();
        this.loadDuels();
      }
    } catch (error) {
      console.error("取消决斗失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "取消决斗失败";
      alert("❌ " + errorMsg);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async deleteDuel(duel) {
    const statusText = {
      pending: "待接受",
      accepted: "已接受",
      rejected: "已拒绝",
      cancelled: "已取消",
      settled: "已结算"
    }[duel.status] || duel.status;

    if (!confirm(`确定要删除此决斗吗？\n\n决斗主题：${duel.title}\n状态：${statusText}\n\n此操作不可撤销，符合条件的积分将自动退还。`)) {
      return;
    }

    this.isLoading = true;

    try {
      const result = await ajax(`/qd/duel/admin/${duel.id}.json`, {
        type: "DELETE"
      });

      if (result.success) {
        alert("✅ " + result.message);
        this.loadDuels();
      }
    } catch (error) {
      console.error("删除决斗失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "删除决斗失败";
      alert("❌ " + errorMsg);
    } finally {
      this.isLoading = false;
    }
  }
}
