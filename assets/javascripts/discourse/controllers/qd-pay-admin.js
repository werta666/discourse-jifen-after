import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdPayAdminController extends Controller {
  @tracked isClearing = false;
  @tracked showOrders = false;
  @tracked showDebugModal = false;
  @tracked debugUsername = "";
  @tracked debugAmount = 100;
  @tracked debugReason = "";
  @tracked isAdjusting = false;
  @tracked filterDate = new Date().toISOString().split('T')[0];
  @tracked currentPage = 1;
  @tracked pageSize = 10;

  get formattedStats() {
    const stats = this.model?.stats || {};
    return {
      totalOrders: stats.total_orders || 0,
      paidOrders: stats.paid_orders || 0,
      pendingOrders: stats.pending_orders || 0,
      cancelledOrders: stats.cancelled_orders || 0,
      totalAmount: (stats.total_amount || 0).toFixed(2),
      totalPaidCoins: stats.total_paid_coins || 0
    };
  }

  get filteredOrders() {
    const orders = this.model?.orders || [];
    if (!this.filterDate) return orders;
    
    return orders.filter(order => {
      return order.created_at.startsWith(this.filterDate);
    });
  }

  get paginatedOrders() {
    const start = (this.currentPage - 1) * this.pageSize;
    const end = start + this.pageSize;
    return this.filteredOrders.slice(start, end);
  }

  get totalPages() {
    return Math.ceil(this.filteredOrders.length / this.pageSize);
  }

  get hasPreviousPage() {
    return this.currentPage > 1;
  }

  get hasNextPage() {
    return this.currentPage < this.totalPages;
  }

  get hasOrders() {
    return this.model?.orders?.length > 0;
  }

  // 辅助方法 - 格式化订单状态文本
  getStatusText(status) {
    const statusMap = {
      pending: "待支付",
      paid: "已支付",
      cancelled: "已取消",
      refunded: "已退款"
    };
    return statusMap[status] || status;
  }

  // 辅助方法 - 获取订单状态样式类
  getStatusClass(status) {
    const classMap = {
      pending: "status-pending",
      paid: "status-paid",
      cancelled: "status-cancelled",
      refunded: "status-refunded"
    };
    return classMap[status] || "";
  }

  @action
  async clearUnpaidOrders() {
    if (!confirm("确定要删除所有未付款和已取消的订单吗？此操作不可恢复！")) {
      return;
    }

    this.isClearing = true;

    try {
      const result = await ajax("/qd/pay/admin/clear_unpaid.json", {
        type: "DELETE"
      });

      if (result.success) {
        alert(`成功删除 ${result.deleted_count} 条订单`);
        // 刷新页面
        window.location.reload();
      }
    } catch (error) {
      console.error("清理订单失败:", error);
      popupAjaxError(error);
    } finally {
      this.isClearing = false;
    }
  }

  @action
  refreshData() {
    window.location.reload();
  }

  @action
  goBack() {
    window.location.href = "/qd/pay";
  }

  @action
  toggleOrders() {
    this.showOrders = !this.showOrders;
  }

  @action
  openDebugModal() {
    this.showDebugModal = true;
    this.debugUsername = "";
    this.debugAmount = 100;
    this.debugReason = "";
  }

  @action
  closeDebugModal() {
    this.showDebugModal = false;
  }

  @action
  stopPropagation(event) {
    event.stopPropagation();
  }

  @action
  updateDebugUsername(event) {
    this.debugUsername = event.target.value;
  }

  @action
  updateDebugAmount(event) {
    this.debugAmount = event.target.value;
  }

  @action
  updateDebugReason(event) {
    this.debugReason = event.target.value;
  }

  @action
  async adjustCoins(type) {
    if (!this.debugUsername) {
      alert("请输入用户名");
      return;
    }

    if (!this.debugAmount || this.debugAmount == 0) {
      alert("请输入有效的数量");
      return;
    }

    const amount = type === "add" ? Math.abs(this.debugAmount) : -Math.abs(this.debugAmount);
    const action = type === "add" ? "增加" : "减少";

    if (!confirm(`确定要给用户 ${this.debugUsername} ${action} ${Math.abs(amount)} 付费币吗？`)) {
      return;
    }

    this.isAdjusting = true;

    try {
      const result = await ajax("/qd/pay/admin/adjust_coins.json", {
        type: "POST",
        data: {
          username: this.debugUsername,
          amount: amount,
          reason: this.debugReason || `管理员手动${action}`
        }
      });

      if (result.success) {
        alert(`成功${action} ${Math.abs(amount)} 付费币\n用户: ${result.username}\n当前余额: ${result.balance}`);
        this.closeDebugModal();
      }
    } catch (error) {
      console.error("调整付费币失败:", error);
      popupAjaxError(error);
    } finally {
      this.isAdjusting = false;
    }
  }

  @action
  updateFilterDate(event) {
    this.filterDate = event.target.value;
    this.currentPage = 1;
  }

  @action
  previousPage() {
    if (this.hasPreviousPage) {
      this.currentPage--;
    }
  }

  @action
  nextPage() {
    if (this.hasNextPage) {
      this.currentPage++;
    }
  }

  @action
  goToPage(page) {
    this.currentPage = page;
  }
}
