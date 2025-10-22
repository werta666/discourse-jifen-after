import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdBettingRoute extends Route {
  async model() {
    try {
      const result = await ajax("/qd/betting/events.json");
      
      return {
        events: result.events || [],
        userBalance: result.user_balance || 0,
        isLoggedIn: result.is_logged_in || false,
        isAdmin: result.is_admin || false
      };
    } catch (error) {
      console.error("加载竞猜数据失败:", error);
      return {
        events: [],
        userBalance: 0,
        isLoggedIn: false,
        isAdmin: false,
        error: true
      };
    }
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    // 启动自动刷新
    controller.startAutoRefresh();
  }

  resetController(controller, isExiting) {
    super.resetController(controller, isExiting);
    if (isExiting) {
      // 停止自动刷新
      controller.stopAutoRefresh();
    }
  }
}
