import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class QdVipRoute extends DiscourseRoute {
  async model() {
    try {
      const data = await ajax("/qd/vip");
      console.log("[VIP Route] 成功加载VIP数据");
      console.log("[VIP Route] 套餐数量:", data.packages?.length || 0);
      
      // 最小化数据处理 - 仅记录日志
      if (data.packages && Array.isArray(data.packages)) {
        data.packages.forEach(pkg => {
          console.log(`[VIP Route] 套餐 "${pkg.name}" pricing_plans:`, pkg.pricing_plans);
        });
      }
      
      // 直接返回原始数据，不做任何修改
      return data;
    } catch (error) {
      console.error("[VIP Route] 加载VIP数据失败:", error);
      return {
        packages: [],
        current_vip: null,
        user_paid_coins: 0,
        paid_coin_name: "付费币"
      };
    }
  }
}
