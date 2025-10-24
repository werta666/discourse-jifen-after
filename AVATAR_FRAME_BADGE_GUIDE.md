# 🎨 Discourse 头像框与勋章系统现代化实现指南

> 基于 Discourse v3.6.0+ / Ember v6.6.0 / 使用 Glimmer Components  
> **完全避免过时的 Widget API**

---

## 📋 核心技术栈

### 现代化 API（推荐使用）
- ✅ `api.customUserAvatarClasses()` - 为头像添加自定义 CSS 类
- ✅ `api.addPosterIcons()` - 为用户名旁添加图标/勋章
- ✅ `api.decorateCooked()` - 在帖子内容渲染后处理 DOM
- ✅ `ajax()` from `discourse/lib/ajax` - 现代化 AJAX 请求
- ✅ Glimmer Components (`@tracked`, `@action`)
- ✅ User Serializer Extensions - 将自定义字段暴露给前端

### 避免使用（已过时）
- ❌ `api.decorateWidget()` - 过时的 Widget 装饰器
- ❌ `api.modifyClass()` - 过时的类修改方式
- ❌ `virtual-dom` - 过时的虚拟 DOM
- ❌ Widget System - 旧版渲染系统

---

## 🎯 技术方案架构

### 方案一：Plugin Outlet + Custom Components（最推荐）
使用 Discourse 的插件出口系统，在指定位置插入自定义组件。

**优点**：
- 官方推荐方式
- 不会被 Discourse 更新破坏
- 性能最优

**缺点**：
- 需要了解 Discourse 的 Outlet 系统
- 自定义位置有限

### 方案二：User Serializer + CSS Overlay（本项目采用）
通过用户序列化器暴露数据，使用 CSS 覆盖层显示装饰。

**优点**：
- 灵活，可以在任何位置显示
- 实现相对简单
- 适合快速原型开发

**缺点**：
- 需要手动管理 DOM
- 可能与主题冲突

---

## 🔧 实现步骤

### 第一步：扩展用户序列化器

在后端暴露自定义字段，让前端可以访问头像框和勋章数据。

**文件位置**：`app/serializers/user_serializer_extension.rb`

```ruby
# frozen_string_literal: true

module UserSerializerExtension
  def self.prepended(base)
    # 添加自定义字段到序列化器
    base.attributes :avatar_frame_id, :equipped_decoration_badge
  end

  def avatar_frame_id
    object.custom_fields["avatar_frame_id"]
  end

  def equipped_decoration_badge
    object.custom_fields["equipped_decoration_badge"]
  end
end

# 同时扩展 UserCardSerializer 和 UserSerializer
::UserCardSerializer.prepend(UserSerializerExtension)
::UserSerializer.prepend(UserSerializerExtension)
```

**在 plugin.rb 中加载**：
```ruby
after_initialize do
  require_relative "app/serializers/user_serializer_extension"
end
```

---

### 第二步：创建初始化器（头像框）

使用现代化 API 在全站显示头像框。

**文件位置**：`assets/javascripts/discourse/initializers/avatar-frame-init.js`

```javascript
import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";

export default {
  name: "avatar-frame-init",
  
  initialize() {
    withPluginApi("1.2.0", api => {
      // 加载头像框数据
      ajax("/qd/test/frames")
        .then(data => {
          window.QD_AVATAR_FRAMES = {};
          (data.frames || []).forEach(frame => {
            window.QD_AVATAR_FRAMES[frame.id] = frame;
          });
        })
        .catch(err => console.warn("Failed to load avatar frames:", err));
      
      // 方法1：使用 customUserAvatarClasses 添加标记类
      api.customUserAvatarClasses((user) => {
        if (!user || !window.QD_AVATAR_FRAMES) return [];
        
        const frameId = user.avatar_frame_id;
        if (!frameId) return [];
        
        // 返回自定义类名，可以在 CSS 中使用
        return [`has-avatar-frame-${frameId}`];
      });
      
      // 方法2：使用 decorateCooked 在帖子渲染后添加框架
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
```

**CSS 样式**：`assets/stylesheets/qd-avatar-frames.scss`

```scss
// 头像框覆盖层
.qd-avatar-frame-overlay {
  position: absolute !important;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  pointer-events: none;
  z-index: 2;
  
  img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
}

// 确保头像容器是相对定位
.topic-avatar,
.user-card-avatar {
  position: relative !important;
}
```

---

### 第三步：创建初始化器（装饰勋章）

使用 `addPosterIcons` API 在用户名旁显示勋章。

**文件位置**：`assets/javascripts/discourse/initializers/decoration-badge-init.js`

```javascript
import { withPluginApi } from "discourse/lib/plugin-api";
import { ajax } from "discourse/lib/ajax";

export default {
  name: "decoration-badge-init",
  
  initialize() {
    withPluginApi("1.2.0", api => {
      // 加载勋章数据
      ajax("/qd/test/badges")
        .then(data => {
          window.QD_DECORATION_BADGES = {};
          (data.badges || []).forEach(badge => {
            window.QD_DECORATION_BADGES[badge.id] = badge;
          });
        })
        .catch(err => console.warn("Failed to load badges:", err));
      
      // 使用 addPosterIcons 在用户名旁添加勋章
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
```

**CSS 样式**：`assets/stylesheets/qd-decoration-badges.scss`

```scss
// 装饰勋章样式
.qd-decoration-badge {
  display: inline-block;
  margin-left: 6px;
  vertical-align: middle;
  
  &.qd-badge-text {
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 12px;
    font-weight: 600;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
  }
  
  &.qd-badge-image {
    img {
      height: 20px;
      width: auto;
      vertical-align: middle;
    }
  }
}
```

---

### 第四步：后端 API 接口

创建测试页面的后端接口。

**路由配置**：`config/routes.rb`

```ruby
# 测试装饰系统
get "/test" => "test#index"
get "/test/frames" => "test#frames"
get "/test/badges" => "test#badges"
post "/test/upload-frame" => "test#upload_frame"
post "/test/upload-badge" => "test#upload_badge"
post "/test/equip-frame" => "test#equip_frame"
post "/test/equip-badge" => "test#equip_badge"
```

**控制器**：`app/controllers/my_plugin_module/test_controller.rb`

```ruby
# frozen_string_literal: true

module ::MyPluginModule
  class TestController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    before_action :ensure_logged_in
    
    def index
      render "default/empty"
    end

    def frames
      frames = PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                             .where("key LIKE ?", "test_avatar_frame_%")
                             .map { |row| JSON.parse(row.value) }
      
      render json: {
        frames: frames,
        equipped_frame_id: current_user.custom_fields["avatar_frame_id"]
      }
    end

    def badges
      badges = PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                             .where("key LIKE ?", "test_decoration_badge_%")
                             .map { |row| JSON.parse(row.value) }
      
      render json: {
        badges: badges,
        equipped_badge_id: current_user.custom_fields["equipped_decoration_badge"]
      }
    end

    def upload_frame
      return render json: { error: "无权限" }, status: 403 unless current_user.admin?
      
      file = params[:file]
      name = params[:name]
      
      # 保存文件和数据库记录
      # ...实现细节见完整代码
    end

    def equip_frame
      frame_id = params[:frame_id].to_i
      current_user.custom_fields["avatar_frame_id"] = frame_id
      current_user.save_custom_fields(true)
      
      render json: { success: true }
    end

    def equip_badge
      badge_id = params[:badge_id].to_i
      current_user.custom_fields["equipped_decoration_badge"] = badge_id
      current_user.save_custom_fields(true)
      
      render json: { success: true }
    end
  end
end
```

---

## 📁 文件上传与存储

### 公共文件夹结构
```
public/
└── uploads/
    └── default/
        ├── avatar-frames/    # 头像框文件夹
        └── decoration-badges/  # 勋章文件夹
```

### 上传处理代码
```ruby
def upload_frame
  file = params[:file]
  name = params[:name]
  
  upload_dir = File.join(Rails.root, "public", "uploads", "default", "avatar-frames")
  FileUtils.mkdir_p(upload_dir)
  
  filename = "frame_#{Time.now.to_i}_#{SecureRandom.hex(4)}.#{file.original_filename.split('.').last}"
  file_path = File.join(upload_dir, filename)
  
  File.open(file_path, "wb") do |f|
    file.rewind
    f.write(file.read)
  end
  
  image_url = "/uploads/default/avatar-frames/#{filename}"
  
  frame_data = {
    id: next_frame_id,
    name: name,
    image: image_url,
    uploaded_at: Time.current.iso8601
  }
  
  PluginStore.set(PLUGIN_NAME, "test_avatar_frame_#{frame_data[:id]}", frame_data.to_json)
  
  render json: { success: true, frame: frame_data }
end
```

---

## 🎨 前端测试页面实现

使用 Glimmer Components 创建测试界面。

**路由映射**：`assets/javascripts/discourse/qd-route-map.js`

```javascript
export default function () {
  this.route("qd-test", { path: "/qd/test" });
}
```

**路由处理器**：`assets/javascripts/discourse/routes/qd-test.js`

```javascript
import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdTestRoute extends Route {
  async model() {
    const [framesData, badgesData] = await Promise.all([
      ajax("/qd/test/frames"),
      ajax("/qd/test/badges")
    ]);
    
    return {
      frames: framesData.frames || [],
      badges: badgesData.badges || [],
      equippedFrameId: framesData.equipped_frame_id,
      equippedBadgeId: badgesData.equipped_badge_id
    };
  }
}
```

**控制器**：`assets/javascripts/discourse/controllers/qd-test.js`

```javascript
import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";

export default class QdTestController extends Controller {
  @service currentUser;
  @service dialog;
  
  @tracked uploadingFrame = false;
  @tracked uploadingBadge = false;
  
  @action
  async uploadFrame(event) {
    const file = event.target.files[0];
    if (!file) return;
    
    this.uploadingFrame = true;
    const formData = new FormData();
    formData.append("file", file);
    formData.append("name", file.name.split('.')[0]);
    
    try {
      await ajax("/qd/test/upload-frame", {
        type: "POST",
        data: formData,
        processData: false,
        contentType: false
      });
      
      this.dialog.alert("✅ 上传成功！");
      window.location.reload();
    } catch (error) {
      this.dialog.alert("❌ 上传失败：" + error.message);
    } finally {
      this.uploadingFrame = false;
    }
  }
  
  @action
  async equipFrame(frameId) {
    try {
      await ajax("/qd/test/equip-frame", {
        type: "POST",
        data: { frame_id: frameId }
      });
      
      this.dialog.alert("✅ 已装备头像框！");
      window.location.reload();
    } catch (error) {
      this.dialog.alert("❌ 装备失败");
    }
  }
}
```

---

## ✅ 完整检查清单

### 后端
- [ ] 用户序列化器扩展已创建
- [ ] 路由已在 `config/routes.rb` 中注册
- [ ] 控制器已创建且继承 `::ApplicationController`
- [ ] 文件上传目录权限正确

### 前端
- [ ] 初始化器使用 `withPluginApi("1.2.0")` 或更高版本
- [ ] 使用 `api.customUserAvatarClasses()` 或 `api.addPosterIcons()`
- [ ] 没有使用任何 Widget API (`decorateWidget`, `modifyClass`)
- [ ] 使用 `@tracked` 和 `@action` 装饰器
- [ ] CSS 样式使用 `!important` 确保优先级
- [ ] 路由已在 route-map.js 中注册

### 测试
- [ ] 访问 `/qd/test` 页面正常加载
- [ ] 可以上传头像框和勋章
- [ ] 装备后在测试页面能看到效果
- [ ] 浏览器控制台无错误
- [ ] 发帖后头像框和勋章在帖子中显示

---

## 🚀 最佳实践

1. **始终使用现代 API**：优先使用 `addPosterIcons`、`customUserAvatarClasses` 等现代 API
2. **数据缓存**：将头像框和勋章数据缓存在 `window` 对象中，避免重复请求
3. **性能优化**：使用 `decorateCooked` 只在帖子渲染时处理，避免全局 MutationObserver
4. **CSS 隔离**：使用独特的类名前缀（如 `qd-`）避免冲突
5. **错误处理**：所有 AJAX 请求都应有 `catch` 处理
6. **权限检查**：上传功能仅限管理员

---

## 📚 参考资源

- [Discourse Plugin API 文档](https://meta.discourse.org/t/beginners-guide-to-creating-discourse-plugins/30515)
- [Ember.js 官方文档](https://emberjs.com/)
- [Glimmer Components 指南](https://guides.emberjs.com/release/components/)
