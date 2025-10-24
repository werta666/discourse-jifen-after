import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";

export default {
  name: "avatar-frame-init",
  
  initialize() {
    withPluginApi("1.2.0", api => {
      // 加载头像框数据到缓存
      ajax("/qd/test/frames")
        .then(data => {
          window.QD_AVATAR_FRAMES = {};
          (data.frames || []).forEach(frame => {
            window.QD_AVATAR_FRAMES[frame.id] = frame;
          });
          console.log("✅ 头像框数据已加载", window.QD_AVATAR_FRAMES);
        })
        .catch(err => {
          console.warn("Failed to load avatar frames:", err);
        });
      
      // 使用 customUserAvatarClasses 添加自定义类（现代API）
      api.customUserAvatarClasses((user) => {
        if (!user || !window.QD_AVATAR_FRAMES) return [];
        
        const frameId = user.avatar_frame_id;
        if (!frameId) return [];
        
        // 返回自定义类名
        return [`has-avatar-frame-${frameId}`];
      });
      
      // 在帖子渲染后添加头像框（使用 decorateCooked）
      api.decorateCooked($elem => {
        if (!window.QD_AVATAR_FRAMES) return;
        
        // 查找所有头像容器
        $elem.find('.topic-avatar').each(function() {
          const $avatar = $(this);
          const $link = $avatar.find('a[data-user-card]');
          if (!$link.length) return;
          
          const username = $link.attr('data-user-card');
          
          // 从 Discourse 的用户缓存中获取用户数据
          const user = api.container.lookup('service:store')
            .peekAll('user')
            .find(u => u.username === username);
          
          if (!user) return;
          
          const frameId = user.get('avatar_frame_id');
          if (!frameId) return;
          
          const frame = window.QD_AVATAR_FRAMES[frameId];
          if (!frame) return;
          
          // 添加头像框覆盖层
          if ($avatar.find('.qd-avatar-frame-overlay').length === 0) {
            const $overlay = $('<div class="qd-avatar-frame-overlay"></div>');
            const $img = $(`<img src="${frame.image}" alt="${frame.name}" />`);
            $overlay.append($img);
            $avatar.css('position', 'relative').append($overlay);
          }
        });
      }, { id: "qd-avatar-frames" });
    });
  }
};
