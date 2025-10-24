import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";

export default {
  name: "badge-display-init",
  
  initialize() {
    withPluginApi("1.2.0", api => {
      // 加载勋章数据到缓存
      ajax("/qd/dress/decoration-badges")
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
      
      // 在帖子渲染后添加勋章
      api.decorateCooked($elem => {
        if (!window.QD_DECORATION_BADGES) return;
        
        // 在帖子中查找所有用户名
        $elem.find('.names, .username, [class*="username"]').each(function() {
          addBadgeToUsername($(this));
        });
      }, { id: "qd-decoration-badges" });
      
      // 全局扫描并添加勋章
      function addBadgeToUsername($usernameContainer) {
        if (!$usernameContainer || $usernameContainer.find('.qd-decoration-badge').length > 0) {
          return; // 已经添加过了
        }
        
        // 查找用户链接
        const $userLink = $usernameContainer.find('a[data-user-card]').first();
        if (!$userLink.length) {
          // 尝试在父元素中查找
          const $parentUserLink = $usernameContainer.closest('[data-user-card]');
          if (!$parentUserLink.length) return;
        }
        
        const username = $userLink.attr('data-user-card') || 
                        $usernameContainer.closest('[data-user-card]').attr('data-user-card');
        if (!username) return;
        
        // 从 Discourse 用户缓存中获取用户数据
        const user = api.container.lookup('service:store').peekAll('user')
          .find(u => u.username === username);
        
        if (!user) return;
        
        const badgeId = user.get('equipped_decoration_badge');
        if (!badgeId) return;
        
        const badge = window.QD_DECORATION_BADGES[badgeId];
        if (!badge) return;
        
        // 创建勋章元素
        const $badgeSpan = $('<span class="qd-decoration-badge"></span>');
        $badgeSpan.attr('title', badge.name);
        
        if (badge.type === "text") {
          $badgeSpan.addClass('qd-badge-text');
          $badgeSpan.text(badge.text);
          if (badge.style) {
            $badgeSpan.attr('style', badge.style);
          }
        } else {
          $badgeSpan.addClass('qd-badge-image');
          const $img = $(`<img src="${badge.image}" alt="${badge.name}" />`);
          $badgeSpan.append($img);
        }
        
        // 插入到用户名后面
        const $targetUsername = $userLink.length ? $userLink : $usernameContainer.find('.username, .name').first();
        if ($targetUsername.length) {
          $targetUsername.after($badgeSpan);
        } else {
          $usernameContainer.append($badgeSpan);
        }
      }
      
      // 使用 MutationObserver 监听新添加的用户名
      const observer = new MutationObserver((mutations) => {
        if (!window.QD_DECORATION_BADGES) return;
        
        mutations.forEach(mutation => {
          mutation.addedNodes.forEach(node => {
            if (node.nodeType === 1) { // Element node
              const $node = $(node);
              
              // 检查新添加的节点是否包含用户名
              $node.find('.names, .username, [class*="username"]').each(function() {
                addBadgeToUsername($(this));
              });
              
              // 检查节点本身是否是用户名容器
              if ($node.hasClass('names') || $node.hasClass('username') || 
                  $node.attr('class')?.includes('username')) {
                addBadgeToUsername($node);
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
