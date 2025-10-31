import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdCenterAdminRoute extends Route {
  beforeModel(transition) {
    if (!this.currentUser?.admin) {
      alert("需要管理员权限");
      this.transitionTo("qd-center");
      return;
    }
  }

  async model() {
    try {
      // 添加时间戳防止缓存
      const timestamp = new Date().getTime();
      const data = await ajax("/qd/center/admin?_=" + timestamp);
      return data;
    } catch (error) {
      console.error("[Creator Admin] 加载失败:", error);
      return {
        pending_works: [],
        approved_works: [],
        pending_shop_applications: [],
        approved_shop_works: [],
        stats: {},
        shop_standards: {},
        commission_rate: 0,
        whitelist: [],
        max_donations_per_work: 0,
        heat_config: { thresholds: [100, 200, 300, 500] },
        heat_rules: {
          like_weight: 1,
          click_weight: 1,
          paid_coin_threshold: 100,
          paid_coin_base_multiplier: 2,
          jifen_weight: 1
        }
      };
    }
  }
  
  setupController(controller, model) {
    super.setupController(controller, model);
    // 确保数据初始化
    controller.initializeData();
  }
}
