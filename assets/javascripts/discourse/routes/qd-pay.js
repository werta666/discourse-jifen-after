import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdPayRoute extends Route {
  async model() {
    try {
      const data = await ajax("/qd/pay/packages.json");
      return {
        packages: data.packages || [],
        alipayEnabled: data.alipay_enabled || false,
        userPoints: data.user_points || 0,
        loadTime: new Date().toISOString()
      };
    } catch (error) {
      console.error("加载充值套餐失败:", error);
      return {
        packages: [],
        alipayEnabled: false,
        userPoints: 0,
        error: "加载充值套餐失败"
      };
    }
  }
}
