import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { inject as service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";

export default class QdShopAdminOrdersController extends Controller {
  @service router;
  @tracked isLoading = false;
  @tracked selectedOrder = null;
  @tracked showStatusModal = false;
  @tracked newStatus = "";
  @tracked adminNotes = "";
  @tracked statusMessage = "";
  @tracked currentFilter = "all";
  @tracked currentPage = 1;
  @tracked pageSize = 8;

  // 获取订单统计数据
  get orderStats() {
    if (!this.model?.orders) return { total: 0, pending: 0, completed: 0, cancelled: 0, refunded: 0 };
    
    const orders = this.model.orders;
    return {
      total: orders.length,
      pending: orders.filter(order => order.status === "pending").length,
      completed: orders.filter(order => order.status === "completed").length,
      cancelled: orders.filter(order => order.status === "cancelled").length,
      refunded: orders.filter(order => order.status === "refunded").length
    };
  }

  // 获取所有订单
  get allOrders() {
    return this.model?.orders || [];
  }

  // 根据筛选条件获取订单
  get filteredOrders() {
    if (this.currentFilter === "all") {
      return this.allOrders;
    }
    return this.allOrders.filter(order => order.status === this.currentFilter);
  }

  // 分页订单
  get paginatedOrders() {
    const startIndex = (this.currentPage - 1) * this.pageSize;
    const endIndex = startIndex + this.pageSize;
    return this.filteredOrders.slice(startIndex, endIndex);
  }

  // 总页数
  get totalPages() {
    return Math.ceil(this.filteredOrders.length / this.pageSize);
  }

  // 是否有多页
  get hasMultiplePages() {
    return this.totalPages > 1;
  }

  // 是否有上一页
  get hasPreviousPage() {
    return this.currentPage > 1;
  }

  // 是否有下一页
  get hasNextPage() {
    return this.currentPage < this.totalPages;
  }

  @action
  goBackToShop() {
    this.router.transitionTo("qd-shop");
  }

  @action
  setFilter(filter) {
    this.currentFilter = filter;
    this.currentPage = 1; // 重置到第一页
  }

  @action
  goToPage(page) {
    if (page >= 1 && page <= this.totalPages) {
      this.currentPage = page;
    }
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
  showUpdateStatusModal(order) {
    this.selectedOrder = order;
    this.newStatus = order.status;
    this.adminNotes = "";
    this.showStatusModal = true;
    this.statusMessage = "";
  }

  @action
  closeStatusModal() {
    this.showStatusModal = false;
    this.selectedOrder = null;
    this.newStatus = "";
    this.adminNotes = "";
    this.statusMessage = "";
  }

  @action
  updateOrderStatus(event) {
    this.newStatus = event.target.value;
  }

  @action
  updateAdminNotes(event) {
    this.adminNotes = event.target.value;
  }

  @action
  async confirmUpdateOrder() {
    if (!this.selectedOrder || !this.newStatus) {
      this.statusMessage = "请选择订单状态";
      return;
    }

    this.isLoading = true;
    this.statusMessage = "";

    try {
      console.log("🔄 发送状态更新请求:", {
        orderId: this.selectedOrder.id,
        newStatus: this.newStatus,
        adminNotes: this.adminNotes || ""
      });

      const response = await ajax(`/qd/shop/admin/orders/${this.selectedOrder.id}/status`, {
        type: "PATCH",
        data: {
          status: this.newStatus,
          admin_notes: this.adminNotes || ""
        }
      });

      console.log("📥 状态更新响应:", response);

      if (response.status === "success") {
        this.statusMessage = response.message || "订单状态更新成功！";
        
        // 更新本地数据
        const orderIndex = this.model.orders.findIndex(o => o.id === this.selectedOrder.id);
        if (orderIndex !== -1) {
          this.model.orders[orderIndex].status = this.newStatus;
          this.model.orders[orderIndex].updated_at = new Date().toISOString();
          // 如果有备注，更新备注
          if (this.adminNotes) {
            const currentNotes = this.model.orders[orderIndex].notes || "";
            const timestamp = new Date().toLocaleString("zh-CN");
            this.model.orders[orderIndex].notes = currentNotes + 
              (currentNotes ? "\n" : "") + 
              `[${timestamp} 管理员备注] ${this.adminNotes}`;
          }
          // 触发界面更新
          this.notifyPropertyChange('model');
        }



        setTimeout(() => {
          this.closeStatusModal();
        }, 2000);
      } else {
        this.statusMessage = response.message || "更新失败";
      }
    } catch (error) {
      console.error("更新订单状态失败:", error);
      const errorMessage = error.jqXHR?.responseJSON?.message || error.message || "网络错误";
      this.statusMessage = "❌ 更新失败：" + errorMessage;
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async refundOrder(order) {
    const currencyName = order.currency_type === "paid_coins" 
      ? this.model.paid_coin_name 
      : "积分";
    
    if (!confirm(`确定要退款订单 #${order.id} 吗？\n\n将返还 ${order.total_price} ${currencyName} 给用户 ${order.username}`)) {
      return;
    }

    this.isLoading = true;

    try {
      const response = await ajax(`/qd/shop/admin/orders/${order.id}/refund`, {
        type: "POST"
      });

      if (response.status === "success") {
        // 更新本地订单状态
        const orderIndex = this.model.orders.findIndex(o => o.id === order.id);
        if (orderIndex !== -1) {
          this.model.orders[orderIndex].status = "refunded";
          this.notifyPropertyChange('model');
        }
        
        this.statusMessage = "✅ 退款成功！已返还 " + currencyName;
        
        setTimeout(() => {
          this.statusMessage = "";
        }, 3000);
      } else {
        this.statusMessage = "❌ " + (response.message || "退款失败");
      }
    } catch (error) {
      console.error("退款失败:", error);
      this.statusMessage = "❌ 退款失败：" + (error.jqXHR?.responseJSON?.message || error.message || "网络错误");
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async deleteOrder(order) {
    if (!confirm(`确定要删除订单 #${order.id} 吗？此操作不可恢复。`)) {
      return;
    }

    this.isLoading = true;

    try {
      const response = await ajax(`/qd/shop/admin/orders/${order.id}`, {
        type: "DELETE"
      });

      if (response.status === "success") {
        // 从本地数据中移除订单
        const orderIndex = this.model.orders.findIndex(o => o.id === order.id);
        if (orderIndex !== -1) {
          this.model.orders.splice(orderIndex, 1);
          this.notifyPropertyChange('model');
        }
        
        this.statusMessage = "✅ 订单删除成功！";
        
        setTimeout(() => {
          this.statusMessage = "";
        }, 3000);
      } else {
        this.statusMessage = "❌ " + (response.message || "删除失败");
      }
    } catch (error) {
      console.error("删除订单失败:", error);
      this.statusMessage = "❌ 删除订单失败：" + (error.message || "网络错误");
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async refreshOrders() {
    this.isLoading = true;
    this.statusMessage = "";
    
    try {
      console.log("🔄 刷新管理员订单列表");
      
      // 刷新当前路由
      this.router.refresh();
      
      console.log("✅ 页面刷新成功");
    } catch (error) {
      console.error("❌ 刷新页面失败:", error);
      this.statusMessage = "刷新失败: " + (error.message || "网络错误");
    } finally {
      this.isLoading = false;
    }
  }

  @action
  stopPropagation(event) {
    event.stopPropagation();
  }

  @action
  formatDate(dateString) {
    if (!dateString) return "";
    
    try {
      const date = new Date(dateString);
      return date.toLocaleString("zh-CN", {
        year: "numeric",
        month: "2-digit", 
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit"
      });
    } catch (e) {
      return dateString;
    }
  }

  @action
  getStatusClass(status) {
    switch (status) {
      case "completed":
        return "status-completed";
      case "pending":
        return "status-pending";
      case "cancelled":
        return "status-cancelled";
      case "refunded":
        return "status-refunded";
      default:
        return "status-unknown";
    }
  }

  @action
  getStatusText(status) {
    switch (status) {
      case "completed":
        return "已完成";
      case "pending":
        return "处理中";
      case "cancelled":
        return "已取消";
      case "refunded":
        return "已退款";
      default:
        return status || "未知";
    }
  }

  @action
  getUserAvatar(avatarTemplate) {
    if (!avatarTemplate) return "/images/avatar.png";
    return avatarTemplate.replace("{size}", "45");
  }
}