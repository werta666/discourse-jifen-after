import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default class QdDressRoute extends DiscourseRoute {
  async model() {
    try {
      const response = await ajax("/qd/dress");
      
      console.log("[Dress Route] 服务器返回数据:", response);
      console.log("[Dress Route] equipped_frame_id:", response.equipped_frame_id, "类型:", typeof response.equipped_frame_id);
      console.log("[Dress Route] equipped_badge_id:", response.equipped_badge_id, "类型:", typeof response.equipped_badge_id);
      console.log("[Dress Route] owned_frames:", response.owned_frames);
      console.log("[Dress Route] owned_badges:", response.owned_badges);
      
      // 确保 ID 是数字类型
      if (response.equipped_frame_id) {
        response.equipped_frame_id = parseInt(response.equipped_frame_id);
      }
      if (response.equipped_badge_id) {
        response.equipped_badge_id = parseInt(response.equipped_badge_id);
      }
      
      console.log("[Dress Route] 处理后 equipped_frame_id:", response.equipped_frame_id);
      console.log("[Dress Route] 处理后 equipped_badge_id:", response.equipped_badge_id);
      
      return response;
    } catch (error) {
      console.error("[Dress Route] 加载装饰数据失败:", error);
      if (error.jqXHR?.status === 401) {
        this.transitionTo("login");
      }
      return {
        owned_frames: [],
        owned_badges: [],
        equipped_frame_id: null,
        equipped_badge_id: null
      };
    }
  }
}
