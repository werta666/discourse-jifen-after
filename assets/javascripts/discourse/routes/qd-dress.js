import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default DiscourseRoute.extend({
  model() {
    // 并行获取用户数据、头像框数据和勋章数据
    const userPromise = this.store.find("user", this.currentUser.username);
    const framesPromise = ajax("/qd/dress/frames");
    const badgesPromise = ajax("/qd/dress/decoration-badges");

    return Promise.all([userPromise, framesPromise, badgesPromise]).then(([user, framesData, badgesData]) => {
      return {
        user: user,
        // 获取用户的Discourse勋章
        badges: user.get("badges") || [],
        // 获取用户的头像框（从自定义字段）
        avatarFrameId: user.get("custom_fields.avatar_frame_id"),
        // 从后端获取可用的头像框
        availableFrames: framesData.frames || [],
        // 用户拥有的头像框
        ownedFrames: framesData.owned_frames || [],
        // 已装备的头像框
        equippedFrameId: framesData.equipped_frame_id,
        // 装饰勋章列表
        availableDecorationBadges: badgesData.badges || [],
        // 用户拥有的勋章
        ownedBadges: badgesData.owned_badges || [],
        // 已装备的勋章
        equippedBadgeId: badgesData.equipped_badge_id
      };
    });
  },

  setupController(controller, model) {
    this._super(controller, model);
    // 初始化控制器数据
    controller.set("ownedFrames", model.ownedFrames || []);
    controller.set("selectedFrameId", model.equippedFrameId);
  },

  actions: {
    error(error) {
      if (error.status === 404) {
        this.router.replaceWith("/404");
      }
      return true;
    }
  }
});
