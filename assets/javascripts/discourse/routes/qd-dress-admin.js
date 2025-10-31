import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class QdDressAdminRoute extends DiscourseRoute {
  beforeModel() {
    const user = this.currentUser;
    
    // 检查是否为管理员
    if (!user || !user.admin) {
      this.transitionTo("qd-dress");
      return;
    }
  }

  async model() {
    try {
      const response = await ajax("/qd/dress/admin");
      return {
        frames: response.avatar_frames || [],
        badges: response.badges || [],
        grantsSummary: response.grants_summary || {}
      };
    } catch (error) {
      console.error("加载装饰系统数据失败:", error);
      return {
        frames: [],
        badges: [],
        grantsSummary: {}
      };
    }
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    controller.set("frames", model.frames);
    controller.set("badges", model.badges);
    controller.set("grantsSummary", model.grantsSummary);
  }
}
