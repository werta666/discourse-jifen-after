import { withPluginApi } from "discourse/lib/plugin-api";
import { h } from "virtual-dom";

export default {
  name: "badge-display-init",
  
  initialize() {
    withPluginApi("0.8", api => {
      // 在用户名后面显示装饰勋章
      api.decorateWidget("poster-name:after", helper => {
        const user = helper.attrs.user;
        if (!user) return;

        const badgeId = user.custom_fields?.equipped_decoration_badge;
        if (!badgeId) return;

        // 从缓存中获取勋章信息
        const badges = window.QD_DECORATION_BADGES || {};
        const badge = badges[badgeId];
        if (!badge) return;

        if (badge.type === "text") {
          // 文字效果勋章
          return h("span.qd-decoration-badge.qd-badge-text", {
            style: badge.style || "",
            title: badge.name
          }, badge.text);
        } else {
          // 图片勋章
          return h("span.qd-decoration-badge.qd-badge-image", {
            title: badge.name
          }, [
            h("img", {
              attributes: {
                src: badge.image,
                alt: badge.name
              }
            })
          ]);
        }
      });

      // 在用户卡片中显示勋章
      api.modifyClass("component:user-card-contents", {
        pluginId: "badge-display-system",
        
        didInsertElement() {
          this._super(...arguments);
          this._addDecorationBadge();
        },

        _addDecorationBadge() {
          const user = this.get("user");
          if (!user) return;

          const badgeId = user.custom_fields?.equipped_decoration_badge;
          if (!badgeId) return;

          const badges = window.QD_DECORATION_BADGES || {};
          const badge = badges[badgeId];
          if (!badge) return;

          const usernameElement = this.element.querySelector(".username");
          if (!usernameElement) return;

          const badgeSpan = document.createElement("span");
          badgeSpan.className = "qd-decoration-badge";
          badgeSpan.title = badge.name;

          if (badge.type === "text") {
            badgeSpan.classList.add("qd-badge-text");
            badgeSpan.textContent = badge.text;
            if (badge.style) {
              badgeSpan.setAttribute("style", badge.style);
            }
          } else {
            badgeSpan.classList.add("qd-badge-image");
            badgeSpan.innerHTML = `<img src="${badge.image}" alt="${badge.name}" />`;
          }

          usernameElement.parentNode.insertBefore(badgeSpan, usernameElement.nextSibling);
        }
      });

      // 加载勋章数据到缓存
      if (!window.QD_DECORATION_BADGES) {
        fetch("/qd/dress/decoration-badges")
          .then(response => response.json())
          .then(data => {
            window.QD_DECORATION_BADGES = {};
            (data.badges || []).forEach(badge => {
              window.QD_DECORATION_BADGES[badge.id] = badge;
            });
          })
          .catch(err => console.error("Failed to load decoration badges:", err));
      }
    });
  }
};
