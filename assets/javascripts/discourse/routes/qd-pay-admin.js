import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdPayAdminRoute extends Route {
  async model() {
    try {
      const data = await ajax("/qd/pay/admin/stats.json");
      return {
        stats: data.stats || {},
        orders: data.orders || [],
        loadTime: new Date().toISOString()
      };
    } catch (error) {
      console.error("加载订单统计失败:", error);
      
      // 如果是权限错误，跳转回首页
      if (error.status === 403) {
        this.transitionTo("discovery.latest");
        return;
      }
      
      return {
        stats: {},
        orders: [],
        error: "加载失败"
      };
    }
  }
}
