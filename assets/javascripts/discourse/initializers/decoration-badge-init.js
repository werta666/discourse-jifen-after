import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";

export default {
  name: "decoration-badge-init",
  
  initialize() {
    withPluginApi("1.2.0", api => {
      // 用户勋章数据缓存
      window.QD_USER_BADGE_DATA = {};
      
      // 加载勋章数据到缓存
      ajax("/qd/test/badges")
        .then(data => {
          window.QD_DECORATION_BADGES = {};
          (data.badges || []).forEach(badge => {
            window.QD_DECORATION_BADGES[badge.id] = badge;
          });
          console.log("✅ 装饰勋章数据已加载", Object.keys(window.QD_DECORATION_BADGES).length, "个");
          
          // 数据加载后立即处理页面上已有的用户名
          setTimeout(() => addBadgesToExistingUsernames(), 500);
        })
        .catch(err => {
          console.warn("❌ 加载装饰勋章失败:", err);
        });
      
      // 使用 decorateCooked 在帖子渲染后添加勋章
      api.decorateCooked(($elem) => {
        if (!window.QD_DECORATION_BADGES) return;
        
        $elem.find('.names').each(function() {
          processUsernameElement(this);
        });
      }, { id: "qd-decoration-badges" });
      
      // 处理单个用户名元素
      function processUsernameElement(nameEl) {
        if (!window.QD_DECORATION_BADGES) return;
        if (nameEl.querySelector('.qd-decoration-badge')) return;
        
        const usernameLink = nameEl.querySelector('a.username, span.username');
        if (!usernameLink) return;
        
        const username = usernameLink.textContent.trim();
        if (!username) return;
        
        // 检查缓存
        if (window.QD_USER_BADGE_DATA[username] !== undefined) {
          const badgeId = window.QD_USER_BADGE_DATA[username];
          if (badgeId) {
            addBadgeToUsername(nameEl, badgeId, username);
          }
          return;
        }
        
        // 从API获取用户数据
        ajax(`/u/${username}.json`)
          .then(response => {
            const badgeId = response.user?.equipped_decoration_badge;
            window.QD_USER_BADGE_DATA[username] = badgeId || null;
            
            if (badgeId) {
              addBadgeToUsername(nameEl, badgeId, username);
            }
          })
          .catch(() => {
            window.QD_USER_BADGE_DATA[username] = null;
          });
      }
      
      // 添加勋章到用户名
      function addBadgeToUsername(nameEl, badgeId, username) {
        const badge = window.QD_DECORATION_BADGES[badgeId];
        if (!badge) {
          console.log(`⚠️ 勋章 ID ${badgeId} 不存在`);
          return;
        }
        
        if (nameEl.querySelector('.qd-decoration-badge')) return;
        
        const badgeSpan = document.createElement('span');
        badgeSpan.className = 'qd-decoration-badge';
        badgeSpan.title = badge.name;
        
        if (badge.type === "text") {
          badgeSpan.classList.add('qd-badge-text');
          badgeSpan.textContent = badge.text;
          if (badge.style) {
            badgeSpan.setAttribute('style', badge.style);
          }
        } else {
          badgeSpan.classList.add('qd-badge-image');
          badgeSpan.innerHTML = `<img src="${badge.image}" alt="${badge.name}" style="height: 18px; width: auto; vertical-align: middle;">`;
        }
        
        // 插入到用户名容器末尾
        nameEl.appendChild(badgeSpan);
        
        console.log(`✅ 为用户 ${username} 添加了勋章 ${badge.name}`);
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
