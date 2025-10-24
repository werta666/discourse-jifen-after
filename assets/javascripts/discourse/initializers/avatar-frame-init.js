import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";

export default {
  name: "avatar-frame-init",
  
  initialize(container) {
    withPluginApi("1.2.0", api => {
      // 用户数据缓存
      window.QD_USER_FRAME_DATA = {};
      
      // 加载头像框数据到缓存
      ajax("/qd/test/frames")
        .then(data => {
          window.QD_AVATAR_FRAMES = {};
          (data.frames || []).forEach(frame => {
            window.QD_AVATAR_FRAMES[frame.id] = frame;
          });
          console.log("✅ 头像框数据已加载", Object.keys(window.QD_AVATAR_FRAMES).length, "个");
          
          // 数据加载后立即处理页面上已有的头像
          setTimeout(() => addFramesToExistingAvatars(), 500);
        })
        .catch(err => {
          console.warn("❌ 加载头像框失败:", err);
        });
      
      // 使用 decorateCooked 在帖子渲染后添加头像框
      api.decorateCooked(($elem) => {
        if (!window.QD_AVATAR_FRAMES) return;
        
        $elem.find('.topic-avatar').each(function() {
          processAvatarElement(this);
        });
      }, { id: "qd-avatar-frames" });
      
      // 处理单个头像元素
      function processAvatarElement(avatarEl) {
        if (!window.QD_AVATAR_FRAMES) return;
        if (avatarEl.querySelector('.qd-avatar-frame-overlay')) return;
        
        const link = avatarEl.querySelector('a[data-user-card]');
        if (!link) return;
        
        const username = link.getAttribute('data-user-card');
        if (!username) return;
        
        // 检查缓存
        if (window.QD_USER_FRAME_DATA[username] !== undefined) {
          const frameId = window.QD_USER_FRAME_DATA[username];
          if (frameId) {
            addFrameToAvatar(avatarEl, frameId, username);
          }
          return;
        }
        
        // 从API获取用户数据
        ajax(`/u/${username}.json`)
          .then(response => {
            const frameId = response.user?.avatar_frame_id;
            window.QD_USER_FRAME_DATA[username] = frameId || null;
            
            if (frameId) {
              addFrameToAvatar(avatarEl, frameId, username);
            }
          })
          .catch(() => {
            window.QD_USER_FRAME_DATA[username] = null;
          });
      }
      
      // 添加头像框到头像
      function addFrameToAvatar(avatarEl, frameId, username) {
        const frame = window.QD_AVATAR_FRAMES[frameId];
        if (!frame) {
          console.log(`⚠️ 头像框 ID ${frameId} 不存在`);
          return;
        }
        
        if (avatarEl.querySelector('.qd-avatar-frame-overlay')) return;
        
        const overlay = document.createElement('div');
        overlay.className = 'qd-avatar-frame-overlay';
        overlay.innerHTML = `<img src="${frame.image}" alt="${frame.name}" />`;
        avatarEl.style.position = 'relative';
        avatarEl.appendChild(overlay);
        
        console.log(`✅ 为用户 ${username} 添加了头像框 ${frame.name}`);
      }
      
      // 处理页面上已存在的所有头像
      function addFramesToExistingAvatars() {
        if (!window.QD_AVATAR_FRAMES) return;
        
        document.querySelectorAll('.topic-avatar').forEach(avatarEl => {
          processAvatarElement(avatarEl);
        });
      }
      
      // 监听新添加的头像
      const observer = new MutationObserver((mutations) => {
        if (!window.QD_AVATAR_FRAMES) return;
        
        mutations.forEach(mutation => {
          mutation.addedNodes.forEach(node => {
            if (node.nodeType !== 1) return;
            
            if (node.classList && node.classList.contains('topic-avatar')) {
              processAvatarElement(node);
            }
            
            if (node.querySelectorAll) {
              node.querySelectorAll('.topic-avatar').forEach(processAvatarElement);
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
