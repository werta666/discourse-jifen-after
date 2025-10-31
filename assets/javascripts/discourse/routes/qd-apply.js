import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdApplyRoute extends Route {
  async model() {
    try {
      const data = await ajax("/qd/apply.json");
      return data;
    } catch (error) {
      console.error("加载申请页面失败:", error);
      return {
        is_creator: false,
        has_pending_application: false,
        application_fee: 100,
        user_points: 0,
        can_afford: false,
        error: error.jqXHR?.responseJSON?.errors?.[0] || "加载失败"
      };
    }
  }
}
