import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";

export default {
  name: "decoration-badge-init",
  
  initialize() {
    withPluginApi("1.2.0", api => {
      // 加载勋章数据到缓存
      ajax("/qd/test/badges")
        .then(data => {
          window.QD_DECORATION_BADGES = {};
          (data.badges || []).forEach(badge => {
            window.QD_DECORATION_BADGES[badge.id] = badge;
          });
          console.log("✅ 装饰勋章数据已加载", window.QD_DECORATION_BADGES);
        })
        .catch(err => {
          console.warn("Failed to load decoration badges:", err);
        });
      
      // 使用 addPosterIcons 在用户名旁添加勋章（现代API）
      api.addPosterIcons((cfs, attrs) => {
        if (!window.QD_DECORATION_BADGES) return;
        
        const user = attrs?.user;
        if (!user) return;
        
        const badgeId = user.equipped_decoration_badge;
        if (!badgeId) return;
        
        const badge = window.QD_DECORATION_BADGES[badgeId];
        if (!badge) return;
        
        // 返回图标定义
        if (badge.type === "text") {
          return {
            text: badge.text,
            className: 'qd-decoration-badge qd-badge-text',
            title: badge.name,
            attributes: {
              style: badge.style || ''
            }
          };
        } else {
          return {
            icon: null,
            emoji: null,
            url: badge.image,
            className: 'qd-decoration-badge qd-badge-image',
            title: badge.name
          };
        }
      });
    });
  }
};
