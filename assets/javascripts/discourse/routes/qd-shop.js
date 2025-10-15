import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class QdShopRoute extends DiscourseRoute {
  async model() {
    try {
      // 获取用户积分信息（学习 qd-tp 的方式）
      const summaryResult = await ajax("/qd/summary.json");
      const userPoints = summaryResult.total_score || 0;
      
      // 获取商品列表
      const response = await ajax("/qd/shop/products");
      
      return {
        products: response.products || [],
        userPoints: userPoints,
        isAdmin: response.is_admin || false
      };
    } catch (error) {
      console.error("获取商店数据失败:", error);
      
      // 返回默认数据
      return {
        products: [],
        userPoints: 0,
        isAdmin: false
      };
    }
  }
}