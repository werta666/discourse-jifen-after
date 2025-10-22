import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdRoute extends Route {
  async model() {
    try {
      // 加载概览数据（后端已包含 recent_records：最近 7 天签到记录）
      return await ajax("/qd/summary.json");
    } catch (e) {
      // 未登录或接口不可用时，返回占位数据以渲染未登录分支
      return {
        user_logged_in: false,
        signed: false,
        consecutive_days: 0,
        total_score: 0,
        today_score: 0,
        points: 0,
        makeup_cards: 0,
        makeup_card_price: 0,
        install_date: new Date().toISOString().slice(0, 10),
        rewards: {},
        recent_records: []
      };
    }
  }

  async setupController(controller, model) {
    super.setupController(controller, model);
    controller.model = model;

    if (model.user_logged_in) {
      // 优先使用 summary 返回的最近 7 天记录，避免首屏“暂无记录”闪烁
      controller.records = Array.isArray(model.recent_records) ? model.recent_records : [];
      if (controller.records.length > 0) {
        controller.missingDays = controller._computeRecentMissingDays(controller.records);
      } else {
        await controller.loadRecords();
      }
    } else {
      controller.records = [];
      controller.missingDays = [];
    }
  }
}