import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdBettingAdminRoute extends Route {
  async beforeModel() {
    // 检查管理员权限
    if (!this.currentUser || !this.currentUser.admin) {
      this.router.transitionTo("discovery.latest");
      return;
    }
  }

  async model() {
    try {
      const result = await ajax("/qd/betting/admin/events.json");
      
      return {
        events: result.events || []
      };
    } catch (error) {
      console.error("加载管理数据失败:", error);
      return {
        events: [],
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
