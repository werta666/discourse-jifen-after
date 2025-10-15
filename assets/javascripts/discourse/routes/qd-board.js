import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdBoardRoute extends Route {
  async model() {
    try {
      const data = await ajax("/qd/board_data.json");
      return {
        top: data.leaderboard || [],
        updatedAt: data.updated_at || new Date().toISOString(),
        is_admin: data.is_admin || false,
        requires_login: data.requires_login || false,
        message: data.message || ""
      };
    } catch (error) {
      console.error("获取排行榜失败:", error);
      
      // 如果是401未授权错误，说明需要登录
      if (error.status === 401 || error.jqXHR?.status === 401) {
        return {
          top: [],
          updatedAt: new Date().toISOString(),
          is_admin: false,
          requires_login: true,
          message: "请登录后查看积分排行榜"
        };
      }
      
      // 其他错误的降级处理
      return {
        top: [],
        updatedAt: new Date().toISOString(),
        is_admin: false,
        requires_login: false,
        message: "加载排行榜失败，请稍后重试"
      };
    }
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    // 启动倒计时
    controller.startCountdown();
  }
}
