import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";

export default {
  name: "dress-avatar-frame-loader",
  
  initialize() {
    // 只在帖子页面 (/t/) 和装饰页面 (/qd/dress) 加载
    const allowedPaths = ['/t/', '/qd/dress'];
    const currentPath = window.location.pathname;
    const shouldLoad = allowedPaths.some(path => currentPath.startsWith(path));
    
    if (!shouldLoad) return;
    
    withPluginApi("1.2.0", api => {
      // 用户数据缓存（持久化到 localStorage）
      const USER_CACHE_KEY = 'qd_dress_user_frame_data';
      const USER_CACHE_TIME_KEY = 'qd_dress_user_frame_time';
      const USER_CACHE_DURATION = 15 * 60 * 1000; // 15分钟
      
      // 从 localStorage 加载用户数据缓存
      try {
        const cached = localStorage.getItem(USER_CACHE_KEY);
        const cacheTime = localStorage.getItem(USER_CACHE_TIME_KEY);
        if (cached && cacheTime) {
          const elapsed = Date.now() - parseInt(cacheTime);
          if (elapsed < USER_CACHE_DURATION) {
            window.QD_USER_FRAME_DATA = JSON.parse(cached);
            console.log("✅ 从缓存加载用户头像框数据", Object.keys(window.QD_USER_FRAME_DATA).length, "个用户");
          } else {
            window.QD_USER_FRAME_DATA = {};
          }
        } else {
          window.QD_USER_FRAME_DATA = {};
        }
      } catch (e) {
        window.QD_USER_FRAME_DATA = {};
      }
      
      // 保存用户数据缓存
      function saveUserCache() {
        try {
          localStorage.setItem(USER_CACHE_KEY, JSON.stringify(window.QD_USER_FRAME_DATA));
          localStorage.setItem(USER_CACHE_TIME_KEY, Date.now().toString());
        } catch (e) {
          console.warn("保存用户缓存失败:", e);
        }
      }
      
      // 从 localStorage 读取装饰缓存
      const CACHE_KEY = 'qd_dress_avatar_frames';
      const CACHE_TIME_KEY = 'qd_dress_frames_time';
      const CACHE_DURATION = 30 * 60 * 1000; // 30分钟缓存
      
      function loadFromCache() {
        try {
          const cached = localStorage.getItem(CACHE_KEY);
          const cacheTime = localStorage.getItem(CACHE_TIME_KEY);
          
          if (cached && cacheTime) {
            const elapsed = Date.now() - parseInt(cacheTime);
            if (elapsed < CACHE_DURATION) {
              window.QD_AVATAR_FRAMES = JSON.parse(cached);
              console.log("✅ 从缓存加载头像框数据", Object.keys(window.QD_AVATAR_FRAMES).length, "个");
              return true;
            }
          }
        } catch (e) {
          console.warn("读取缓存失败:", e);
        }
        return false;
      }
      
      function saveToCache(frames) {
        try {
          localStorage.setItem(CACHE_KEY, JSON.stringify(frames));
          localStorage.setItem(CACHE_TIME_KEY, Date.now().toString());
        } catch (e) {
          console.warn("保存缓存失败:", e);
        }
      }
      
      // 先尝试从缓存加载
      const fromCache = loadFromCache();
      if (fromCache) {
        // 立即处理已有头像
        addFramesToExistingAvatars();
      }
      
      // 异步更新数据（即使有缓存也更新，确保数据最新）
      ajax("/qd/dress/frames")
        .then(data => {
          window.QD_AVATAR_FRAMES = {};
          (data.frames || []).forEach(frame => {
            window.QD_AVATAR_FRAMES[frame.id] = frame;
          });
          
          // 保存到缓存
          saveToCache(window.QD_AVATAR_FRAMES);
          
          // 加载完成后立即处理页面
          addFramesToExistingAvatars();
        })
        .catch(err => {
          console.warn("❌ 加载头像框失败:", err);
        });
      
      // 批量获取用户装饰数据
      let batchFetchTimer = null;
      let pendingUsernames = new Set();
      
      function batchFetchUserDecorations() {
        if (pendingUsernames.size === 0) return;
        
        const usernames = Array.from(pendingUsernames);
        pendingUsernames.clear();
        
        ajax('/qd/dress/batch-user-decorations', {
          type: 'POST',
          data: JSON.stringify({ usernames }),
          contentType: 'application/json'
        })
          .then(data => {
            Object.entries(data.users || {}).forEach(([username, userData]) => {
              window.QD_USER_FRAME_DATA[username] = {
                frameId: userData.avatar_frame_id || null,
                updatedAt: userData.updated_at
              };
              
              // 查找该用户的所有头像元素并添加头像框
              if (userData.avatar_frame_id) {
                document.querySelectorAll(`.topic-avatar a[data-user-card="${username}"]`)
                  .forEach(link => {
                    const avatarEl = link.closest('.topic-avatar');
                    if (avatarEl && !avatarEl.querySelector('.qd-avatar-frame-overlay')) {
                      addFrameToAvatar(avatarEl, userData.avatar_frame_id, username);
                    }
                  });
              }
            });
            
            saveUserCache();
          })
          .catch(error => {
            console.error('批量获取用户装饰失败:', error);
          });
      }
      
      // 处理单个头像元素
      function processAvatarElement(avatarEl) {
        if (!window.QD_AVATAR_FRAMES) return;
        
        const usernameLink = avatarEl.querySelector('a[data-user-card]');
        if (!usernameLink) return;
        
        const username = usernameLink.getAttribute('data-user-card');
        if (!username) return;
        
        // 防止重复添加
        if (avatarEl.querySelector('.qd-avatar-frame-overlay')) return;
        
        // 检查缓存
        if (window.QD_USER_FRAME_DATA[username] !== undefined) {
          const userData = window.QD_USER_FRAME_DATA[username];
          const frameId = userData?.frameId || userData;
          if (frameId) {
            addFrameToAvatar(avatarEl, frameId, username);
          }
          return;
        }
        
        // 添加到待处理队列
        pendingUsernames.add(username);
        
        // 使用防抖，等待100ms后批量请求
        clearTimeout(batchFetchTimer);
        batchFetchTimer = setTimeout(() => {
          batchFetchUserDecorations();
        }, 100);
      }
      
      // 使用 decorateCooked 在帖子渲染后添加头像框
      api.decorateCooked(($elem) => {
        if (!window.QD_AVATAR_FRAMES) return;
        
        $elem.find('.topic-avatar').each(function() {
          processAvatarElement(this);
        });
      }, { id: "qd-avatar-frames" });
      
      // 添加头像框到头像
      function addFrameToAvatar(avatarEl, frameId, username) {
        // 确保 frameId 是数字而不是对象
        const actualFrameId = (typeof frameId === 'object' && frameId !== null) ? frameId.frameId : frameId;
        
        if (!actualFrameId) return;
        
        const frame = window.QD_AVATAR_FRAMES[actualFrameId];
        if (!frame) {
          console.log(`⚠️ 头像框 ID ${actualFrameId} 不存在`);
          return;
        }
        
        if (avatarEl.querySelector('.qd-avatar-frame-overlay')) return;
        
        // 使用动态参数（默认值：width=64, height=64, top=-8, left=-8）
        const width = frame.width || 64;
        const height = frame.height || 64;
        const top = frame.top !== undefined ? frame.top : -8;
        const left = frame.left !== undefined ? frame.left : -8;
        
        const overlay = document.createElement('div');
        overlay.className = 'qd-avatar-frame-overlay';
        overlay.style.width = `${width}px`;
        overlay.style.height = `${height}px`;
        overlay.style.top = `${top}px`;
        overlay.style.left = `${left}px`;
        overlay.innerHTML = `<img src="${frame.image}" alt="${frame.name ||'头像框'}" />`;
        avatarEl.style.position = 'relative';
        
        // 直接关闭 topic-avatar 的 top calc
        // 覆盖 topic-post.scss:668 的 top: calc(var(--header-offset) - var(--space-1))
        avatarEl.style.setProperty('top', '0px', 'important');
        
        avatarEl.appendChild(overlay);
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
