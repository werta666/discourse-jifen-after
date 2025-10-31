import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";

export default {
  name: "dress-badge-loader",
  
  initialize() {
    // 只在帖子页面 (/t/) 和装饰页面 (/qd/dress) 加载
    const allowedPaths = ['/t/', '/qd/dress'];
    const currentPath = window.location.pathname;
    const shouldLoad = allowedPaths.some(path => currentPath.startsWith(path));
    
    if (!shouldLoad) return;
    
    withPluginApi("1.2.0", api => {
      
      // 用户勋章数据缓存（持久化到 localStorage）
      const USER_CACHE_KEY = 'qd_dress_user_badge_data';
      const USER_CACHE_TIME_KEY = 'qd_dress_user_badge_time';
      const USER_CACHE_DURATION = 15 * 60 * 1000; // 15分钟
      
      // 从 localStorage 加载用户数据缓存
      try {
        const cached = localStorage.getItem(USER_CACHE_KEY);
        const cacheTime = localStorage.getItem(USER_CACHE_TIME_KEY);
        if (cached && cacheTime) {
          const elapsed = Date.now() - parseInt(cacheTime);
          if (elapsed < USER_CACHE_DURATION) {
            window.QD_USER_BADGE_DATA = JSON.parse(cached);
            console.log("✅ 从缓存加载用户勋章数据", Object.keys(window.QD_USER_BADGE_DATA).length, "个用户");
          } else {
            window.QD_USER_BADGE_DATA = {};
          }
        } else {
          window.QD_USER_BADGE_DATA = {};
        }
      } catch (e) {
        window.QD_USER_BADGE_DATA = {};
      }
      
      // 保存用户数据缓存
      function saveUserCache() {
        try {
          localStorage.setItem(USER_CACHE_KEY, JSON.stringify(window.QD_USER_BADGE_DATA));
          localStorage.setItem(USER_CACHE_TIME_KEY, Date.now().toString());
        } catch (e) {
          console.warn("保存用户缓存失败:", e);
        }
      }
      
      // 从 localStorage 读取装饰缓存
      const CACHE_KEY = 'qd_dress_decoration_badges';
      const CACHE_TIME_KEY = 'qd_dress_badges_time';
      const CACHE_DURATION = 30 * 60 * 1000; // 30分钟缓存
      
      function loadFromCache() {
        try {
          const cached = localStorage.getItem(CACHE_KEY);
          const cacheTime = localStorage.getItem(CACHE_TIME_KEY);
          
          if (cached && cacheTime) {
            const elapsed = Date.now() - parseInt(cacheTime);
            if (elapsed < CACHE_DURATION) {
              window.QD_DECORATION_BADGES = JSON.parse(cached);
              console.log("✅ 从缓存加载勋章数据", Object.keys(window.QD_DECORATION_BADGES).length, "个");
              return true;
            }
          }
        } catch (e) {
          console.warn("读取缓存失败:", e);
        }
        return false;
      }
      
      function saveToCache(badges) {
        try {
          localStorage.setItem(CACHE_KEY, JSON.stringify(badges));
          localStorage.setItem(CACHE_TIME_KEY, Date.now().toString());
        } catch (e) {
          console.warn("保存缓存失败:", e);
        }
      }
      
      // 先尝试从缓存加载
      const fromCache = loadFromCache();
      if (fromCache) {
        // 立即处理已有用户名
        addBadgesToExistingUsernames();
      }
      
      // 异步更新数据（即使有缓存也更新，确保数据最新）
      ajax("/qd/dress/badges")
        .then(data => {
          window.QD_DECORATION_BADGES = {};
          (data.badges || []).forEach(badge => {
            window.QD_DECORATION_BADGES[badge.id] = badge;
          });
          
          // 保存到缓存
          saveToCache(window.QD_DECORATION_BADGES);
          
          // 加载完成后立即处理页面
          addBadgesToExistingUsernames();
        })
        .catch(err => {
          console.error("❌ [勋章] 加载失败:", err);
        });
      
      // 使用 decorateCooked 在帖子渲染后添加勋章
      api.decorateCooked(($elem) => {
        if (!window.QD_DECORATION_BADGES) return;
        
        $elem.find('.names').each(function() {
          processUsernameElement(this);
        });
      }, { id: "qd-decoration-badges" });
      
      // 批量获取用户装饰数据
      let badgeBatchFetchTimer = null;
      let badgePendingUsernames = new Set();
      
      function batchFetchBadgeDecorations() {
        if (badgePendingUsernames.size === 0) return;
        
        const usernames = Array.from(badgePendingUsernames);
        badgePendingUsernames.clear();
        
        ajax('/qd/dress/batch-user-decorations', {
          type: 'POST',
          data: JSON.stringify({ usernames }),
          contentType: 'application/json'
        })
          .then(data => {
            Object.entries(data.users || {}).forEach(([username, userData]) => {
              window.QD_USER_BADGE_DATA[username] = {
                badgeId: userData.decoration_badge_id || null,
                updatedAt: userData.updated_at
              };
              
              // 查找该用户的所有用户名元素并添加勋章
              if (userData.decoration_badge_id) {
                document.querySelectorAll('.names').forEach(nameEl => {
                  const usernameLink = nameEl.querySelector('a.username[data-user-card]') ||
                                      nameEl.querySelector('a.username') ||
                                      nameEl.querySelector('span.username a') ||
                                      nameEl.querySelector('a');
                  
                  if (!usernameLink) return;
                  
                  const elUsername = usernameLink.getAttribute('data-user-card') ||
                                    usernameLink.textContent.trim();
                  
                  if (elUsername === username && !nameEl.querySelector('.qd-decoration-badge')) {
                    addBadgeToUsername(nameEl, userData.decoration_badge_id, username);
                  }
                });
              }
            });
            
            saveUserCache();
          })
          .catch(error => {
            console.error('批量获取勋章装饰失败:', error);
          });
      }
      
      // 处理单个用户名元素
      function processUsernameElement(nameEl) {
        if (!window.QD_DECORATION_BADGES) return;
        if (nameEl.querySelector('.qd-decoration-badge')) return;
        
        // 尝试多种方式获取用户名
        const usernameLink = nameEl.querySelector('a.username[data-user-card]') || 
                            nameEl.querySelector('a.username') ||
                            nameEl.querySelector('span.username a') ||
                            nameEl.querySelector('a');
        
        if (!usernameLink) return;
        
        // 优先使用 data-user-card，否则使用 textContent
        const username = usernameLink.getAttribute('data-user-card') || 
                        usernameLink.textContent.trim();
        
        if (!username) return;
        
        // 检查缓存
        if (window.QD_USER_BADGE_DATA[username] !== undefined) {
          const userData = window.QD_USER_BADGE_DATA[username];
          const badgeId = userData?.badgeId || userData;
          if (badgeId) {
            addBadgeToUsername(nameEl, badgeId, username);
          }
          return;
        }
        
        // 添加到待处理队列
        badgePendingUsernames.add(username);
        
        // 使用防抖，等待100ms后批量请求
        clearTimeout(badgeBatchFetchTimer);
        badgeBatchFetchTimer = setTimeout(() => {
          batchFetchBadgeDecorations();
        }, 100);
      }
      
      // 添加勋章到用户名
      function addBadgeToUsername(nameEl, badgeId, username) {
        // 确保 badgeId 是数字而不是对象
        const actualBadgeId = (typeof badgeId === 'object' && badgeId !== null) ? badgeId.badgeId : badgeId;
        
        if (!actualBadgeId) return;
        
        const badge = window.QD_DECORATION_BADGES[actualBadgeId];
        if (!badge) return;
        
        // 防止重复添加
        if (nameEl.querySelector('.qd-decoration-badge')) return;
        
        const badgeSpan = document.createElement('span');
        badgeSpan.className = 'qd-decoration-badge';
        badgeSpan.title = badge.name;
        badgeSpan.dataset.badgeId = actualBadgeId;
        badgeSpan.dataset.username = username;
        
        if (badge.type === "text") {
          badgeSpan.classList.add('qd-badge-text');
          badgeSpan.textContent = badge.text;
          if (badge.style) {
            badgeSpan.setAttribute('style', badge.style);
          }
        } else if (badge.type === "image") {
          badgeSpan.classList.add('qd-badge-image');
          const height = badge.height || 25;
          badgeSpan.innerHTML = `<img src="${badge.image}" alt="${badge.name}" style="height: ${height}px; width: auto; vertical-align: middle;" />`;
        }
        
        nameEl.appendChild(badgeSpan);
      }
      
      // 处理页面上已存在的所有用户名
      function addBadgesToExistingUsernames() {
        if (!window.QD_DECORATION_BADGES) return;
        
        document.querySelectorAll('.names').forEach(nameEl => {
          processUsernameElement(nameEl);
        });
      }
      
      // 监听新添加的用户名
      const observer = new MutationObserver((mutations) => {
        if (!window.QD_DECORATION_BADGES) return;
        
        mutations.forEach(mutation => {
          mutation.addedNodes.forEach(node => {
            if (node.nodeType !== 1) return;
            
            if (node.classList && node.classList.contains('names')) {
              processUsernameElement(node);
            }
            
            if (node.querySelectorAll) {
              node.querySelectorAll('.names').forEach(processUsernameElement);
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
