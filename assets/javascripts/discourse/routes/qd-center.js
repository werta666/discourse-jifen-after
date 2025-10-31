import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdCenterRoute extends Route {
  async model() {
    try {
      // 添加时间戳防止缓存
      const timestamp = new Date().getTime();
      const data = await ajax("/qd/center?_=" + timestamp);
      return data;
    } catch (error) {
      console.error("[Creator Center] 加载失败:", error);
      return {
        works: [],
        jifen_name: "积分",
        paid_coin_name: "付费币",
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
}
