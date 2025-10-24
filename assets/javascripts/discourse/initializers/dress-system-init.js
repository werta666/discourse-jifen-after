import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "dress-system-init",
  
  initialize() {
    withPluginApi("0.8", api => {
      // 在用户头像上显示头像框
      api.decorateWidget("poster-avatar:after", helper => {
        const user = helper.attrs.user;
        if (!user) return;

        const frameId = user.custom_fields?.avatar_frame_id;
        if (!frameId) return;

        // 从缓存中获取头像框信息
        const frames = window.QD_AVATAR_FRAMES || {};
        const frame = frames[frameId];
        if (!frame) return;

        return helper.h("div.qd-avatar-frame-overlay", [
          helper.h("img", {
            attributes: {
              src: frame.image,
              alt: frame.name,
              class: "qd-frame-image"
            }
          })
        ]);
      });

      // 在用户卡片中显示头像框
      api.modifyClass("component:user-card-contents", {
        pluginId: "dress-system",
        
        didInsertElement() {
          this._super(...arguments);
          this._addAvatarFrame();
        },

        _addAvatarFrame() {
          const user = this.get("user");
          if (!user) return;

          const frameId = user.custom_fields?.avatar_frame_id;
          if (!frameId) return;

          const frames = window.QD_AVATAR_FRAMES || {};
          const frame = frames[frameId];
          if (!frame) return;

          const avatarContainer = this.element.querySelector(".user-card-avatar");
          if (!avatarContainer) return;

          const frameOverlay = document.createElement("div");
          frameOverlay.className = "qd-avatar-frame-overlay";
          frameOverlay.innerHTML = `<img src="${frame.image}" alt="${frame.name}" class="qd-frame-image" />`;
          avatarContainer.appendChild(frameOverlay);
        }
      });

      // 加载头像框数据到缓存
      if (!window.QD_AVATAR_FRAMES) {
        fetch("/qd/dress/frames")
          .then(response => response.json())
          .then(data => {
            window.QD_AVATAR_FRAMES = {};
            (data.frames || []).forEach(frame => {
              window.QD_AVATAR_FRAMES[frame.id] = frame;
            });
          })
          .catch(err => console.error("Failed to load avatar frames:", err));
      }
    });
  }
};
