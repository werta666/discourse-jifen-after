import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default DiscourseRoute.extend({
  model() {
    // 并行获取用户数据和头像框数据
    const userPromise = this.store.find("user", this.currentUser.username);
    const framesPromise = ajax("/qd/dress/frames");

    return Promise.all([userPromise, framesPromise]).then(([user, framesData]) => {
      return {
        user: user,
        // 获取用户的勋章
        badges: user.get("badges") || [],
        // 获取用户的头像框（从自定义字段）
        avatarFrameId: user.get("custom_fields.avatar_frame_id"),
        // 从后端获取可用的头像框
        availableFrames: framesData.frames || [],
        // 用户拥有的头像框
        ownedFrames: framesData.owned_frames || [1],
        // 装饰品列表
        availableDecorations: this.getAvailableDecorations()
      };
    });
  },

  getAvailableDecorations() {
    // 可用的装饰品列表（类似勋章的展示徽章）
    return [
      { id: 1, name: "新星", icon: "fa-star", description: "论坛新人", unlocked: true },
      { id: 2, name: "活跃者", icon: "fa-fire", description: "持续活跃", unlocked: false, requirement: "连续登录30天" },
      { id: 3, name: "贡献者", icon: "fa-trophy", description: "优质内容贡献者", unlocked: false, requirement: "获得100个赞" }
    ];
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
