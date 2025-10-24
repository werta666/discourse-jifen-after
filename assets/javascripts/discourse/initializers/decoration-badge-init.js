import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";
import { htmlSafe } from "@ember/template";

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
          console.log("✅ 装饰勋章数据已加载", Object.keys(window.QD_DECORATION_BADGES).length, "个");
        })
        .catch(err => {
          console.warn("❌ 加载装饰勋章失败:", err);
        });
      
      // 使用 addPosterIcons 在用户名旁添加勋章（现代API）
      api.addPosterIcons((cfs, attrs) => {
        if (!window.QD_DECORATION_BADGES) {
          return null;
        }
        
        const user = attrs?.user;
        if (!user) {
          return null;
        }
        
        const badgeId = user.equipped_decoration_badge;
        if (!badgeId) {
          return null;
        }
        
        const badge = window.QD_DECORATION_BADGES[badgeId];
        if (!badge) {
          console.log(`⚠️ 勋章 ID ${badgeId} 不存在`);
          return null;
        }
        
        console.log(`✅ 为用户 ${user.username} 显示勋章 ${badge.name}`);
        
        // 返回图标定义（必须是数组格式）
        if (badge.type === "text") {
          // 文字勋章
          return [{
            icon: null,
            text: badge.text,
            className: 'qd-decoration-badge qd-badge-text',
            title: badge.name,
            ...(badge.style && { attributes: { style: badge.style } })
          }];
        } else {
          // 图片勋章 - 使用 emoji 字段传递图片URL
          return [{
            icon: null,
            emoji: `<img src="${badge.image}" alt="${badge.name}" style="height: 20px; width: auto; vertical-align: middle;">`,
            className: 'qd-decoration-badge qd-badge-image',
            title: badge.name
          }];
        }
      });
    });
  }
};
