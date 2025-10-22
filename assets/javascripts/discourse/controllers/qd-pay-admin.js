import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdPayAdminController extends Controller {
  @tracked isClearing = false;

  get formattedStats() {
    const stats = this.model?.stats || {};
    return {
      totalOrders: stats.total_orders || 0,
      paidOrders: stats.paid_orders || 0,
      pendingOrders: stats.pending_orders || 0,
      cancelledOrders: stats.cancelled_orders || 0,
      totalAmount: (stats.total_amount || 0).toFixed(2),
      totalPoints: stats.total_points || 0
    };
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
}
