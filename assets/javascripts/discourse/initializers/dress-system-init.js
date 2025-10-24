import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";

export default {
  name: "dress-system-init",
  
  initialize() {
    withPluginApi("1.2.0", api => {
      // 加载头像框数据到缓存
      ajax("/qd/dress/frames")
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
      
      // 在帖子渲染后添加头像框
      api.decorateCooked($elem => {
        if (!window.QD_AVATAR_FRAMES) return;
        
        // 在帖子中查找所有头像
        $elem.find('.topic-avatar, [class*="avatar"]').each(function() {
          addFrameToAvatar($(this));
        });
      }, { id: "qd-avatar-frames" });
      
      // 在用户卡片显示时添加头像框
      api.addPosterIcon((cfs, attrs) => {
        const frameId = attrs?.user?.avatar_frame_id;
        if (!frameId || !window.QD_AVATAR_FRAMES) return;
        
        const frame = window.QD_AVATAR_FRAMES[frameId];
        if (!frame) return;
        
        // 通过 CSS 类名添加数据属性
        return {
          icon: null,
          className: 'has-avatar-frame',
          title: frame.name,
          frameId: frameId,
          frameImage: frame.image
        };
      });
      
      // 全局扫描并添加头像框
      function addFrameToAvatar($avatarContainer) {
        if (!$avatarContainer || $avatarContainer.find('.qd-avatar-frame-overlay').length > 0) {
          return; // 已经添加过了
        }
        
        // 查找用户链接
        const $userLink = $avatarContainer.find('a[data-user-card]');
        if (!$userLink.length) return;
        
        const username = $userLink.attr('data-user-card');
        if (!username) return;
        
        // 从 Discourse 用户缓存中获取用户数据
        const user = api.container.lookup('service:store').peekAll('user')
          .find(u => u.username === username);
        
        if (!user) return;
        
        const frameId = user.get('avatar_frame_id');
        if (!frameId) return;
        
        const frame = window.QD_AVATAR_FRAMES[frameId];
        if (!frame) return;
        
        // 添加头像框覆盖层
        const $overlay = $('<div class="qd-avatar-frame-overlay"></div>');
        const $img = $(`<img src="${frame.image}" alt="${frame.name}" class="qd-frame-image" />`);
        $overlay.append($img);
        
        // 找到实际的头像图片容器
        const $avatarImg = $avatarContainer.find('img.avatar').parent();
        if ($avatarImg.length) {
          $avatarImg.css('position', 'relative').append($overlay);
        } else {
          $avatarContainer.css('position', 'relative').append($overlay);
        }
      }
      
      // 使用 MutationObserver 监听新添加的头像
      const observer = new MutationObserver((mutations) => {
        if (!window.QD_AVATAR_FRAMES) return;
        
        mutations.forEach(mutation => {
          mutation.addedNodes.forEach(node => {
            if (node.nodeType === 1) { // Element node
              const $node = $(node);
              
              // 检查新添加的节点是否包含头像
              $node.find('.topic-avatar, [class*="avatar"]').each(function() {
                addFrameToAvatar($(this));
              });
              
              // 检查节点本身是否是头像
              if ($node.hasClass('topic-avatar') || $node.attr('class')?.includes('avatar')) {
                addFrameToAvatar($node);
              }
            }
          });
        });
      });
      
      observer.observe(document.body, {
        childList: true,
        subtree: true
      });
    });
  }
};
