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
          console.log("✅ 头像框数据已加载", Object.keys(window.QD_AVATAR_FRAMES).length, "个");
          
          // 数据加载后立即处理页面上已有的头像
          addFramesToExistingAvatars();
        })
        .catch(err => {
          console.warn("❌ 加载头像框失败:", err);
        });
      
      // 处理页面上已存在的所有头像
      function addFramesToExistingAvatars() {
        if (!window.QD_AVATAR_FRAMES) return;
        
        document.querySelectorAll('.topic-avatar').forEach(avatarEl => {
          const link = avatarEl.querySelector('a[data-user-card]');
          if (!link) return;
          
          const username = link.getAttribute('data-user-card');
          if (!username) return;
          
          // 从用户缓存获取数据
          const store = api.container.lookup('service:store');
          const user = store.peekAll('user').find(u => u.username === username);
          
          if (!user) {
            console.log(`⚠️ 未找到用户 ${username} 的数据`);
            return;
          }
          
          const frameId = user.get('avatar_frame_id');
          if (!frameId) return;
          
          const frame = window.QD_AVATAR_FRAMES[frameId];
          if (!frame) {
            console.log(`⚠️ 头像框 ID ${frameId} 不存在`);
            return;
          }
          
          // 避免重复添加
          if (avatarEl.querySelector('.qd-avatar-frame-overlay')) return;
          
          // 添加头像框
          const overlay = document.createElement('div');
          overlay.className = 'qd-avatar-frame-overlay';
          overlay.innerHTML = `<img src="${frame.image}" alt="${frame.name}" />`;
          avatarEl.style.position = 'relative';
          avatarEl.appendChild(overlay);
          
          console.log(`✅ 为用户 ${username} 添加了头像框 ${frame.name}`);
        });
      }
      
      // 监听新添加的头像（使用 MutationObserver）
      const observer = new MutationObserver((mutations) => {
        if (!window.QD_AVATAR_FRAMES) return;
        
        mutations.forEach(mutation => {
          mutation.addedNodes.forEach(node => {
            if (node.nodeType !== 1) return;
            
            // 检查节点本身
            if (node.classList && node.classList.contains('topic-avatar')) {
              processAvatar(node);
            }
            
            // 检查子节点
            if (node.querySelectorAll) {
              node.querySelectorAll('.topic-avatar').forEach(processAvatar);
            }
          });
        });
      });
      
      function processAvatar(avatarEl) {
        if (avatarEl.querySelector('.qd-avatar-frame-overlay')) return;
        
        const link = avatarEl.querySelector('a[data-user-card]');
        if (!link) return;
        
        const username = link.getAttribute('data-user-card');
        if (!username) return;
        
        const store = api.container.lookup('service:store');
        const user = store.peekAll('user').find(u => u.username === username);
        if (!user) return;
        
        const frameId = user.get('avatar_frame_id');
        if (!frameId) return;
        
        const frame = window.QD_AVATAR_FRAMES[frameId];
        if (!frame) return;
        
        const overlay = document.createElement('div');
        overlay.className = 'qd-avatar-frame-overlay';
        overlay.innerHTML = `<img src="${frame.image}" alt="${frame.name}" />`;
        avatarEl.style.position = 'relative';
        avatarEl.appendChild(overlay);
      }
      
      // 开始观察
      observer.observe(document.body, {
        childList: true,
        subtree: true
      });
    });
  }
};
