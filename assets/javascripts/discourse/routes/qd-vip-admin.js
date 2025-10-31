import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class QdVipAdminRoute extends DiscourseRoute {
  beforeModel() {
    const user = this.currentUser;
    
    // 检查是否为管理员
    if (!user || !user.admin) {
      this.transitionTo("qd-vip");
      return;
    }
  }

  async model() {
    try {
      console.log("[VIP Admin Route] 开始加载数据...");
      const data = await ajax("/qd/vip/admin");
      
      console.log("[VIP Admin Route] ✅ 成功加载数据");
      console.log("[VIP Admin Route] packages 数量:", data.packages?.length || 0);
      
      return data;
    } catch (error) {
      console.error("[VIP Admin Route] ❌ 加载失败:", error);
      console.error("[VIP Admin Route] 错误状态:", error.jqXHR?.status);
      console.error("[VIP Admin Route] 错误响应:", error.jqXHR?.responseJSON);
      console.error("[VIP Admin Route] 错误文本:", error.jqXHR?.responseText);
      
      return {
        packages: [],
        paid_coin_name: "付费币"
      };
    }
  }
}
