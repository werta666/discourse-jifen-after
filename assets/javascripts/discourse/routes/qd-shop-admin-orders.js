import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class QdShopAdminOrdersRoute extends DiscourseRoute {
  beforeModel() {
    // 检查管理员权限
    if (!this.currentUser?.admin) {
      this.router.transitionTo("qd-shop");
      return;
    }
  }

  async model(params) {
    try {
      const page = params.page || 1;
      const response = await ajax(`/qd/shop/admin/orders?page=${page}`);
      
      if (response.status === "success") {
        return {
          orders: response.data.orders || [],
          pagination: {
            current_page: response.data.current_page || 1,
            total_pages: response.data.total_pages || 1,
            total_count: response.data.total_count || 0,
            per_page: response.data.per_page || 20
          },
          paid_coin_name: response.data.paid_coin_name || "付费币",
          status: response.status,
          message: response.message || ""
        };
      } else {
        throw new Error(response.message || "获取订单失败");
      }
    } catch (error) {
      console.error("获取管理员订单失败:", error);
      
      return {
        orders: [],
        pagination: {
          current_page: 1,
          total_pages: 1,
          total_count: 0,
          per_page: 20
        },
        status: "error",
        message: "获取订单失败"
      };
    }
  }
}