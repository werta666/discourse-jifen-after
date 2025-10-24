import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdTestRoute extends Route {
  async model() {
    try {
      const [framesData, badgesData] = await Promise.all([
        ajax("/qd/test/frames"),
        ajax("/qd/test/badges")
      ]);
      
      return {
        frames: framesData.frames || [],
        badges: badgesData.badges || [],
        equippedFrameId: framesData.equipped_frame_id,
        equippedBadgeId: badgesData.equipped_badge_id
      };
    } catch (error) {
      console.error("加载测试数据失败:", error);
      return {
        frames: [],
        badges: [],
        equippedFrameId: null,
        equippedBadgeId: null
      };
    }
  }
}
