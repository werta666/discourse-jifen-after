import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdCenterMakeRoute extends Route {
  beforeModel(transition) {
    if (!this.currentUser) {
      this.transitionTo("qd-center");
      return;
    }
  }

  async model() {
    try {
      console.log("[Creator Make] 加载创作者数据...");
      const data = await ajax("/qd/center/make");
      console.log("[Creator Make] ✅ 数据加载成功:", data);
      return data;
    } catch (error) {
      console.error("[Creator Make] ❌ 加载失败:", error);
      
      if (error.jqXHR?.status === 403) {
        alert("您没有权限访问创作者功能");
        this.transitionTo("qd-center");
        return;
      }
      
      return {
        my_works: [],
        donations: [],
        shop_standards: {},
        jifen_name: "积分",
        paid_coin_name: "付费币"
      };
    }
  }
}
