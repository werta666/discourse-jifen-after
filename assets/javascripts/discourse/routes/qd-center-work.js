import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdCenterWorkRoute extends Route {
  async model(params) {
    try {
      const data = await ajax(`/qd/center/work/${params.work_id}.json`);
      return data;
    } catch (error) {
      console.error("加载作品详情失败:", error);
      popupAjaxError(error);
      // 返回到作品墙
      window.location.href = "/qd/center";
      return null;
    }
  }
  
  setupController(controller, model) {
    super.setupController(controller, model);
    
    // 初始化tracked属性
    if (model) {
      controller.workData = { ...model.work };
      controller.creatorData = { ...model.creator };
      controller.userJifenData = model.user_jifen || 0;
      controller.userPaidCoinData = model.user_paid_coin || 0;
    }
  }
}
