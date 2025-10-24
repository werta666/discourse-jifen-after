import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class QdShopRoute extends DiscourseRoute {
  async model() {
    try {
      // 获取用户积分信息
      const summaryResult = await ajax("/qd/summary.json");
      const userPoints = summaryResult.total_score || 0;
      
      // 获取商品列表
      const response = await ajax("/qd/shop/products");
      
      return {
        products: response.products || [],
        userPoints: response.user_points || userPoints,
        userPaidCoins: response.user_paid_coins || 0,
        paidCoinName: response.paid_coin_name || "付费币",
        exchangeRatio: response.exchange_ratio || 100,
        isAdmin: response.is_admin || false
      };
    } catch (error) {
      console.error("获取商店数据失败:", error);
      
      // 返回默认数据
      return {
        products: [],
        userPoints: 0,
        userPaidCoins: 0,
        paidCoinName: "付费币",
        exchangeRatio: 100,
        isAdmin: false
      };
    }
  }
}