import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class QdShopOrdersRoute extends DiscourseRoute {
  async model() {
    try {
      const response = await ajax("/qd/shop/orders");
      
      // 后端返回格式: { status: "success", data: [...] }
      return {
        orders: response.data || [],
        total_count: response.data ? response.data.length : 0,
        paid_coin_name: response.paid_coin_name || "付费币",
        status: response.status,
        message: response.message || ""
      };
    } catch (error) {
      console.error("获取订单历史失败:", error);
      
      return {
        orders: [],
        total_count: 0,
        status: "error",
        message: "获取订单历史失败"
      };
    }
  }
}