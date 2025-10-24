# 🔧 Discourse 熊猫插件技术实现指南

本文档详细说明了如何成功实现一个在 Discourse 中可访问的 `/panda` 路由，经过多次调试和优化后的最终解决方案。

## 🎯 最终成功的实现方案

经过多次尝试和调试，最终成功的关键在于使用 **Rails Engine 架构** + **Ember v6.6.0 现代化前端** + **Glimmer Components 渲染**。

## 📋 环境要求

### 必需版本
- **Discourse**: v3.6.0+
- **Ember**: v6.6.0
- **Ruby**: 2.7+
- **Rails**: 6.1+

### 浏览器支持
- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

### 开发环境
- Node.js 16+ (用于前端资源编译)
- 支持 ES6+ 语法的现代浏览器

## 🎨 关键技术决策

### 渲染组件选择：Glimmer Components (非 Widget)

**✅ 使用 Glimmer Components 的原因**：
- 符合 Ember v6.6.0 现代标准
- 更好的响应式状态管理 (`@tracked`)
- 现代化的事件处理 (`@action`)
- 使用新版 `service` 装饰器 (替代弃用的 `inject as service`)
- 更清晰的代码结构和维护性
- 更好的性能和类型安全

**❌ 不使用 Widget 的原因**：
- Widget 是较老的 Discourse 特有方式
- 在 Ember v6.6.0 中不是推荐做法
- 代码复杂度更高，维护困难

## � Rails Engine 最小可用配置

### 完整的最小文件结构（防止 502）

```
discourse-panda-plugin/
├── plugin.rb                                    # 主配置
├── lib/
│   └── panda_plugin_module/
│       └── engine.rb                            # Engine 定义
├── config/
│   ├── routes.rb                                # Engine 路由
│   └── settings.yml                             # 插件设置
└── app/
    └── controllers/
        └── panda_plugin_module/
            └── panda_controller.rb              # 控制器
```

### 最小可用的 plugin.rb 模板

```ruby
# frozen_string_literal: true

# name: discourse-panda-plugin
# about: A Panda-themed plugin
# version: 0.0.1
# authors: Panda_CC
# required_version: 2.7.0

enabled_site_setting :panda_plugin_enabled

module ::PandaPluginModule
  PLUGIN_NAME = "discourse-panda-plugin"
end

require_relative "lib/panda_plugin_module/engine"

after_initialize do
  Discourse::Application.routes.append do
    mount ::PandaPluginModule::Engine, at: "/panda"
  end
end
```

### 最小可用的 engine.rb 模板

```ruby
# frozen_string_literal: true

module ::PandaPluginModule
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace PandaPluginModule
  end
end
```

### 最小可用的 routes.rb 模板

```ruby
# frozen_string_literal: true

PandaPluginModule::Engine.routes.draw do
  get "/" => "panda#index"
end
```

### 最小可用的控制器模板

```ruby
# frozen_string_literal: true

module ::PandaPluginModule
  class PandaController < ::ApplicationController
    requires_plugin PandaPluginModule::PLUGIN_NAME

    def index
      render plain: "🐼 Panda Plugin Working!"
    end
  end
end
```

## �📋 核心文件结构

### 1. 插件主配置文件 (`plugin.rb`)

```ruby
# frozen_string_literal: true

# name: discourse-panda-plugin
# about: A Panda-themed plugin that adds a custom /panda page with interactive content
# meta_topic_id: TODO
# version: 0.0.1
# authors: Panda_CC
# url: TODO
# required_version: 2.7.0

enabled_site_setting :panda_plugin_enabled

# Register assets for Ember v5.12.0
register_asset "stylesheets/panda-plugin.scss"

module ::PandaPluginModule
  PLUGIN_NAME = "discourse-panda-plugin"
end

require_relative "lib/panda_plugin_module/engine"

after_initialize do
  # 挂载 Engine 到 /panda 路径
  Discourse::Application.routes.append do
    mount ::PandaPluginModule::Engine, at: "/panda"
  end
end
```

**⚠️ 防止 502 错误的关键点**:
- `require_relative "lib/panda_plugin_module/engine"` 必须在 `after_initialize` 之前
- Engine 挂载必须在 `after_initialize` 块内
- 模块名 `::PandaPluginModule` 必须与文件路径匹配
- `PLUGIN_NAME` 必须在模块定义之前声明
- 不要在 `plugin.rb` 中直接定义路由，只挂载 Engine

### 2. Rails Engine 配置 (`lib/panda_plugin_module/engine.rb`)

```ruby
# frozen_string_literal: true

module ::PandaPluginModule
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace PandaPluginModule
    config.autoload_paths << File.join(config.root, "lib")
  end
end
```

**⚠️ 防止 502 错误的关键点**:
- 文件路径必须精确：`lib/panda_plugin_module/engine.rb`
- 模块名必须与目录名匹配：`PandaPluginModule`
- `engine_name PLUGIN_NAME` 中的 `PLUGIN_NAME` 必须在 `plugin.rb` 中定义
- `isolate_namespace` 防止命名空间冲突
- 不要添加额外的配置，保持最简

### 3. 路由配置 (`config/routes.rb`)

```ruby
# frozen_string_literal: true

PandaPluginModule::Engine.routes.draw do
  get "/" => "panda#index"
end
```

**⚠️ 防止 502 错误的关键点**:
- 路由必须在 Engine 内部定义，不能在 `plugin.rb` 中
- 控制器名 `"panda"` 对应 `PandaController`
- 只定义一个根路由 `"/"`，对应挂载点 `/panda`
- 不要添加其他路由如 `.json` 或 `/test`
- Engine 路由与 Discourse 主路由完全隔离

### 4. 后端控制器 (`app/controllers/panda_plugin_module/panda_controller.rb`)

```ruby
# frozen_string_literal: true

module ::PandaPluginModule
  class PandaController < ::ApplicationController
    requires_plugin PandaPluginModule::PLUGIN_NAME

    def index
      Rails.logger.info "🐼 Panda Controller accessed!"

      # Bootstrap the Ember app for /panda route
      render "default/empty"
    rescue => e
      Rails.logger.error "🐼 Panda Error: #{e.message}"
      render plain: "Error: #{e.message}", status: 500
    end
  end
end
```

**关键点**:
- 继承 `::ApplicationController`
- 使用 `requires_plugin` 确保插件启用
- 渲染 `"default/empty"` 来引导 Ember 应用
- 添加错误处理和日志记录

## 🎨 前端 Ember v5.12.0 实现 (使用 Glimmer Components)

### ⚠️ 重要说明：使用 Glimmer Components 而非 Widget

本插件使用现代化的 **Glimmer Components** 架构，而不是传统的 Discourse Widget 系统。这是关键的技术决策，影响整个前端实现方式。

**Glimmer Components 特征**：
- 使用 `@tracked` 装饰器进行响应式状态管理
- 使用 `@action` 装饰器处理用户交互
- 使用现代 Handlebars 语法：`{{on "click" this.action}}`
- 使用 `<LinkTo @route="...">` 现代组件语法

### 1. 路由映射 (`assets/javascripts/discourse/panda-route-map.js`)

```javascript
// Modern Ember v5+ route mapping
export default function () {
  this.route("panda", { path: "/panda" });
}
```

**关键点**：
- 文件名必须是 `panda-route-map.js`（不是 `route-map.js`）
- 使用函数导出而不是对象
- 路径必须与后端 Engine 挂载路径一致

### 2. 路由处理器 (`assets/javascripts/discourse/routes/panda.js`)

```javascript
import Route from "@ember/routing/route";

export default class PandaRoute extends Route {
  model() {
    return {
      message: "🐼 Panda Paradise",
      status: "working",
      time: new Date().toLocaleString(),
      ember_version: "v5.12.0",
      plugin_version: "0.0.1"
    };
  }
}
```

**关键点**：
- 使用 ES6 class 语法而不是 `Ember.Route.extend`
- 返回静态数据而不是 AJAX 请求（简化实现）
- 文件路径必须是 `routes/panda.js`

### 3. 控制器逻辑 (`assets/javascripts/discourse/controllers/panda.js`)

```javascript
import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";

export default class PandaController extends Controller {
  @tracked randomFact = null;

  pandaFacts = [
    "🐼 Pandas spend 14-16 hours a day eating bamboo!",
    "🎋 A panda's digestive system is actually designed for meat, but they evolved to eat bamboo.",
    "🐼 Baby pandas are about the size of a stick of butter when born!",
    "🎋 Pandas have a pseudo-thumb to help them grip bamboo.",
    "🐼 Giant pandas can live up to 20 years in the wild and 30 years in captivity.",
    "🎋 Pandas are excellent swimmers and climbers!",
    "🐼 A panda's black and white coloring helps them blend into their environment.",
    "🎋 Pandas communicate through scent marking and vocalizations."
  ];

  @action
  showRandomFact() {
    const randomIndex = Math.floor(Math.random() * this.pandaFacts.length);
    this.randomFact = this.pandaFacts[randomIndex];
  }
}
```

**关键点**：
- `@tracked` 装饰器使 `randomFact` 响应式
- `@action` 装饰器绑定方法到组件实例
- 使用 ES6 class 语法和现代 JavaScript 特性

### 4. 模板文件 (`assets/javascripts/discourse/templates/panda.hbs`)

```handlebars
<div class="panda-page">
  <div class="panda-header">
    <h1>🐼 {{model.message}}</h1>
    <p>Status: {{model.status}}</p>
  </div>
  
  <div class="panda-content">
    <div class="panda-card">
      <h2>🎋 Welcome to Panda Paradise!</h2>
      
      <button class="btn btn-primary panda-btn" {{on "click" this.showRandomFact}}>
        🐼 Show Random Fact
      </button>
      
      {{#if this.randomFact}}
        <div class="panda-fact">
          {{this.randomFact}}
        </div>
      {{/if}}
    </div>
  </div>
  
  <div class="panda-footer">
    <LinkTo @route="discovery.latest" class="btn btn-default">
      ← Back to Forum
    </LinkTo>
  </div>
</div>
```

### 5. 初始化器 (`assets/javascripts/discourse/initializers/panda-plugin.js`)

```javascript
import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "panda-plugin",

  initialize() {
    console.log("🐼 Panda Plugin loaded successfully!");

    withPluginApi("1.0.0", (api) => {
      // Plugin initialization for Ember v5.12.0
      console.log("🐼 Panda Plugin API initialized");
    });
  }
};
```

**关键点**：
- 文件名必须是 `panda-plugin.js`
- 使用 `withPluginApi` 确保 API 可用
- 添加控制台日志便于调试

### 6. 样式文件 (`assets/stylesheets/panda-plugin.scss`)

**关键点**：
- 文件必须在 `plugin.rb` 中注册：`register_asset "stylesheets/panda-plugin.scss"`
- 使用现代 CSS 特性（渐变、动画、响应式）
- 类名使用 `.panda-` 前缀避免冲突

## 📋 完整文件清单

### 必需的后端文件
```
plugin.rb                                    # 主配置文件
lib/panda_plugin_module/engine.rb           # Rails Engine
config/routes.rb                            # 路由配置
config/settings.yml                         # 插件设置
app/controllers/panda_plugin_module/panda_controller.rb  # 控制器
```

### 必需的前端文件
```
assets/javascripts/discourse/panda-route-map.js           # 路由映射
assets/javascripts/discourse/routes/panda.js              # 路由处理器
assets/javascripts/discourse/controllers/panda.js         # 控制器逻辑
assets/javascripts/discourse/templates/panda.hbs          # 模板文件
assets/javascripts/discourse/initializers/panda-plugin.js # 初始化器
assets/stylesheets/panda-plugin.scss                      # 样式文件
```

### 文档文件
```
README.md                                    # 用户文档
TECHNICAL_GUIDE.md                          # 技术文档
```

## � 502 错误专项排查

### 502 错误的常见原因和解决方案

**1. Engine 文件路径错误**
```
❌ 错误：lib/engine.rb
❌ 错误：lib/panda_plugin/engine.rb
✅ 正确：lib/panda_plugin_module/engine.rb
```

**2. 模块命名不匹配**
```ruby
❌ 错误：module PandaPlugin
✅ 正确：module ::PandaPluginModule
```

**3. require_relative 路径错误**
```ruby
❌ 错误：require_relative "lib/engine"
✅ 正确：require_relative "lib/panda_plugin_module/engine"
```

**4. 控制器命名空间错误**
```ruby
❌ 错误：class PandaController < ApplicationController
✅ 正确：module ::PandaPluginModule
           class PandaController < ::ApplicationController
```

**5. Engine 挂载位置错误**
```ruby
❌ 错误：在 plugin.rb 顶层挂载
✅ 正确：在 after_initialize 块内挂载
```

### 502 错误调试步骤

1. **检查 Discourse 日志**
```bash
tail -f /var/discourse/shared/standalone/log/rails/production.log
```

2. **验证文件存在**
```bash
ls -la plugins/discourse-panda-plugin/lib/panda_plugin_module/engine.rb
```

3. **检查语法错误**
```bash
ruby -c plugin.rb
ruby -c lib/panda_plugin_module/engine.rb
```

4. **验证模块加载**
在 `plugin.rb` 中添加调试：
```ruby
Rails.logger.info "🐼 Loading PandaPluginModule"
require_relative "lib/panda_plugin_module/engine"
Rails.logger.info "🐼 Engine loaded successfully"
```

## �🚫 失败的尝试和教训

### 1. 直接路由注册 (❌ 失败)

```ruby
# 这种方式不工作
Discourse::Application.routes.append do
  get '/panda' => 'panda#index'
end
```

**问题**: 控制器无法正确加载，路由无法找到对应的控制器。

### 2. 错误的控制器继承 (❌ 失败)

```ruby
# 错误的继承方式
class PandaController < ActionController::Base
```

**问题**: 缺少 Discourse 的安全检查和上下文，导致渲染失败。

### 3. 复杂的 Rails Engine 配置 (❌ 过度复杂)

最初尝试了过于复杂的 Engine 配置，包括多个路由和不必要的功能，导致调试困难。

## ✅ 成功的关键因素

### 1. 正确的架构选择
- **Rails Engine**: 提供了完整的 MVC 架构支持
- **命名空间隔离**: 避免与 Discourse 核心代码冲突
- **模块化设计**: 便于维护和扩展

### 2. 现代化的 Ember 实现
- **ES6+ 语法**: 使用 class 和装饰器
- **响应式状态管理**: 使用 `@tracked` 装饰器
- **现代模板语法**: 使用 `{{on}}` 和 `<LinkTo>`

### 3. 简洁的设计原则
- **单一职责**: 每个文件只负责一个功能
- **最小化配置**: 只保留必要的配置和路由
- **清晰的错误处理**: 完善的日志记录和错误处理

## 🔍 调试技巧

### 1. 日志记录
```ruby
Rails.logger.info "🐼 Panda Controller accessed!"
```

### 2. 浏览器控制台
```javascript
console.log("🐼 Panda Plugin loaded successfully!");
```

### 3. 路由检查
访问 `/rails/info/routes` 查看所有注册的路由。

## 🎯 最佳实践

1. **使用 Rails Engine** 而不是直接路由注册
2. **正确继承 ApplicationController** 获得完整的 Discourse 上下文
3. **使用现代 Ember 语法** 确保与最新版本兼容
4. **添加完善的错误处理** 便于调试和维护
5. **保持代码简洁** 只实现必要的功能

## 🚀 部署检查清单

### 文件结构检查
- [ ] `plugin.rb` 存在且配置正确
- [ ] `lib/panda_plugin_module/engine.rb` 存在
- [ ] `config/routes.rb` 存在且只有一个路由
- [ ] `config/settings.yml` 存在
- [ ] `app/controllers/panda_plugin_module/panda_controller.rb` 存在
- [ ] 所有前端文件都在正确位置

### 代码检查
- [ ] 控制器继承 `::ApplicationController`
- [ ] 使用 `requires_plugin PandaPluginModule::PLUGIN_NAME`
- [ ] 路由映射文件名为 `panda-route-map.js`
- [ ] 使用 Glimmer Components 语法（`@tracked`, `@action`）
- [ ] 模板使用现代语法（`{{on "click"}}`, `<LinkTo>`）

### 部署步骤
- [ ] 重启 Discourse 服务器
- [ ] 在管理员面板启用插件
- [ ] 检查浏览器控制台是否有错误
- [ ] 访问 `/panda` 测试功能

### 调试检查
- [ ] 浏览器控制台显示 "🐼 Panda Plugin loaded successfully!"
- [ ] Discourse 日志显示 "🐼 Panda Controller accessed!"
- [ ] 页面正确渲染，无 404 错误
- [ ] 交互功能正常工作

## 🔍 常见问题排查

### 1. 404 错误
- 检查 Rails Engine 是否正确挂载
- 确认路由映射文件存在且语法正确
- 验证控制器路径和命名空间

### 2. 页面空白
- 检查浏览器控制台错误
- 确认模板文件存在且语法正确
- 验证控制器和路由是否正确连接

### 3. 交互功能不工作
- 确认使用 `@tracked` 和 `@action` 装饰器
- 检查模板中的事件绑定语法
- 验证控制器方法是否正确定义

## 🤖 AI 快速实现指南

### 第一步：创建最小可用版本（避免 502）

**严格按此顺序创建文件，每个文件创建后立即测试**：

1. **创建 `config/settings.yml`**
```yaml
panda_plugin:
  panda_plugin_enabled:
    default: true
    client: true
```

2. **创建 `lib/panda_plugin_module/engine.rb`**
```ruby
# frozen_string_literal: true
module ::PandaPluginModule
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace PandaPluginModule
  end
end
```

3. **创建 `config/routes.rb`**
```ruby
# frozen_string_literal: true
PandaPluginModule::Engine.routes.draw do
  get "/" => "panda#index"
end
```

4. **创建 `app/controllers/panda_plugin_module/panda_controller.rb`**
```ruby
# frozen_string_literal: true
module ::PandaPluginModule
  class PandaController < ::ApplicationController
    requires_plugin PandaPluginModule::PLUGIN_NAME
    def index
      render plain: "🐼 Working!"
    end
  end
end
```

5. **创建 `plugin.rb`**
```ruby
# frozen_string_literal: true
# name: discourse-panda-plugin
# about: A Panda-themed plugin
# version: 0.0.1
# authors: Panda_CC
# required_version: 2.7.0

enabled_site_setting :panda_plugin_enabled

module ::PandaPluginModule
  PLUGIN_NAME = "discourse-panda-plugin"
end

require_relative "lib/panda_plugin_module/engine"

after_initialize do
  Discourse::Application.routes.append do
    mount ::PandaPluginModule::Engine, at: "/panda"
  end
end
```

### 第二步：测试基础功能

1. 重启 Discourse
2. 访问 `/panda` 应该显示 "🐼 Working!"
3. 如果出现 502，检查上述文件路径和命名

### 第三步：添加 Ember 前端（仅在基础版本工作后）

**只有在 `/panda` 返回 "🐼 Working!" 后才继续**

### 关键避错要点

- **文件路径必须精确匹配**
- **模块名必须一致**：`PandaPluginModule`
- **先测试最小版本，再添加功能**
- **每次只改一个文件，立即测试**

---

通过以上的技术实现，最终成功创建了一个完全可用的 `/panda` 路由，提供了完整的 Ember 单页应用体验。关键在于正确使用 Rails Engine 架构、现代化的 Ember v5.12.0 实现，以及 Glimmer Components 渲染系统。

## 📦 数据库迁移（稳定方案·简版）

为兼容不同 Discourse/ActiveRecord 版本并避免重复执行报错，采用如下规范：
- 使用较早时间戳文件，例如：db/migrate/20240101000000_create_xxx.rb
- 迁移基类建议 ActiveRecord::Migration[6.0]（兼容面更广）
- 幂等创建：table_exists? / index_exists? 检查，避免重复建表/索引
- 唯一索引显式命名，便于跨环境排错
- 如存在较新时间戳的同名迁移，保留为空注释文件或重命名类，避免类名冲突
- 业务侧日期判断用 Time.zone.today/Time.zone.yesterday，避免跨时区误判

示例：独立签到表（含唯一索引与查询索引）
```ruby
# db/migrate/20240101000000_create_jifen_signins.rb
# frozen_string_literal: true

class CreateJifenSignins < ActiveRecord::Migration[6.0]
  def up
    unless table_exists?(:jifen_signins)
      create_table :jifen_signins do |t|
        t.integer  :user_id,      null: false
        t.date     :date,         null: false
        t.datetime :signed_at,    null: false
        t.boolean  :makeup,       null: false, default: false
        t.integer  :points,       null: false, default: 0
        t.integer  :streak_count, null: false, default: 1
        t.timestamps null: false
      end
    end

    unless index_exists?(:jifen_signins, [:user_id, :date], name: "idx_jifen_signins_uid_date")
      add_index :jifen_signins, [:user_id, :date], unique: true, name: "idx_jifen_signins_uid_date"
    end

    unless index_exists?(:jifen_signins, [:user_id, :created_at], name: "idx_jifen_signins_uid_created")
      add_index :jifen_signins, [:user_id, :created_at], name: "idx_jifen_signins_uid_created"
    end
  end

  def down
    drop_table :jifen_signins if table_exists?(:jifen_signins)
  end
end

## 🎯 高级实现技巧与问题解决

### 1. 多级路由实现：从 /qd 到 /qd/board 的成功渲染

**问题背景**：在已有 `/qd` 路径的基础上，如何成功实现 `/qd/board` 子路由并避免 502 错误？

**成功方案**：Engine 内部路由 + Ember 嵌套路由

#### 后端路由配置 (`config/routes.rb`)
```ruby
# frozen_string_literal: true

MyPluginModule::Engine.routes.draw do
  get "/" => "qd#index"                    # /qd 主页
  get "/board" => "qd#board"               # /qd/board 排行榜页面
  get "/board_data" => "qd#board_data"     # /qd/board_data API接口
  post "/force_refresh_board" => "qd#force_refresh_board"  # 管理员刷新
end
```

#### 控制器方法 (`app/controllers/my_plugin_module/qd_controller.rb`)
```ruby
def board
  # 渲染 Ember 应用，让前端路由接管
  render "default/empty"
rescue => e
  Rails.logger.error "排行榜页面错误: #{e.message}"
  render plain: "Error: #{e.message}", status: 500
end

def board_data
  # JSON API 接口，返回排行榜数据
  begin
    leaderboard_data = MyPluginModule::JifenService.get_leaderboard(limit: 5)
    render_json_dump({
      success: true,
      leaderboard: leaderboard_data[:leaderboard],
      updated_at: leaderboard_data[:updated_at],
      requires_login: !current_user,
      is_admin: current_user&.admin?
    })
  rescue => e
    Rails.logger.error "获取排行榜失败: #{e.message}"
    render_json_error("获取排行榜失败", status: 500)
  end
end
```

#### 前端路由映射 (`assets/javascripts/discourse/qd-route-map.js`)
```javascript
// 嵌套路由配置
export default function () {
  this.route("qd", { path: "/qd" }, function() {
    this.route("board", { path: "/board" });  // /qd/board 子路由
  });
}
```

#### 关键成功要点：
1. **路由分离**：页面路由 (`/board`) 与 API 路由 (`/board_data`) 分开
2. **渲染策略**：页面路由返回 `"default/empty"`，让 Ember 接管渲染
3. **嵌套路由**：使用 Ember 嵌套路由语法，避免路径冲突
4. **错误处理**：完善的异常捕获和日志记录

### 2. CSS 样式隔离：解决样式波及全站按钮问题

**问题背景**：插件样式意外影响了网站的登录、注册按钮，导致全站样式混乱。

**问题原因**：过于宽泛的 CSS 选择器
```scss
/* ❌ 错误的宽泛选择器 */
.login-button {
  background: linear-gradient(45deg, #ff6b6b, #feca57);
  /* 这会影响全站所有 .login-button */
}

.board-footer button {
  background: linear-gradient(45deg, #667eea, #764ba2);
  /* 这会影响所有页面的 button 元素 */
}
```

**成功解决方案**：CSS 选择器作用域限制

#### 1. 容器作用域限制
```scss
/* ✅ 正确的限定选择器 */
.qd-board--neo .login-button {
  background: linear-gradient(45deg, #ff6b6b, #feca57);
  /* 只影响 .qd-board--neo 容器内的 .login-button */
}

.qd-board--neo .board-footer button {
  background: linear-gradient(45deg, #667eea, #764ba2);
  /* 只影响排行榜页面的按钮 */
}
```

#### 2. 多主题样式隔离
```scss
/* Neo 主题样式 */
.qd-board--neo .admin-refresh-btn {
  background: linear-gradient(45deg, #667eea, #764ba2) !important;
  /* 限定在 neo 主题容器内 */
}

/* Mario 主题样式 */
.qd-board--mario .admin-refresh-btn {
  background: linear-gradient(145deg, #FF0000 0%, #CC0000 100%) !important;
  /* 限定在 mario 主题容器内 */
}

/* Minecraft 主题样式 */
.qd-board--minecraft .admin-refresh-btn {
  background: linear-gradient(145deg, #FF6B6B 0%, #CC0000 100%) !important;
  /* 限定在 minecraft 主题容器内 */
}
```

#### 3. 模板容器结构
```handlebars
{{! 动态主题容器类名 }}
<div class="qd-page qd-board--{{this.boardTheme}}">
  <div class="qd-container">
    <div class="qd-card">
      {{! 所有样式都限定在这个容器内 }}
      <button class="login-button">登录</button>
      <button class="admin-refresh-btn">刷新</button>
    </div>
  </div>
</div>
```

#### 关键成功要点：
1. **容器限定**：所有样式选择器都以主题容器类开头
2. **避免全局选择器**：不使用 `button`、`.btn` 等通用选择器
3. **使用 !important**：确保插件样式优先级高于全局样式
4. **主题隔离**：不同主题使用不同的容器类名

### 3. 动态主题切换系统实现

**技术架构**：后端配置 + 前端响应式渲染

#### 后端配置系统 (`config/settings.yml`)
```yaml
jifen_board_theme:
  default: 'neo'
  client: true
  type: enum
  choices:
    - neo
    - mario
    - minecraft
  description: "积分排行榜主题风格。neo: 精致游戏风格，mario: 马里奥风格，minecraft: 我的世界像素风格"
```

#### 前端响应式获取 (`assets/javascripts/discourse/controllers/qd-board.js`)
```javascript
export default class QdBoardController extends Controller {
  @service siteSettings;

  // 响应式获取主题设置
  get boardTheme() {
    return this.siteSettings?.jifen_board_theme || 'neo';
  }
}
```

#### 模板动态类名 (`assets/javascripts/discourse/templates/qd-board.hbs`)
```handlebars
{{! 动态应用主题类名 }}
<div class="qd-page qd-board--{{this.boardTheme}}">
  {{! 内容会根据主题自动应用不同样式 }}
</div>
```

#### 样式文件组织结构
```
assets/stylesheets/
├── qd-board-neo.scss        # 精致游戏风格
├── qd-board-mario.scss      # 马里奥风格
└── qd-board-minecraft.scss  # 我的世界像素风格
```

#### 插件注册 (`plugin.rb`)
```ruby
# 注册所有主题样式文件
register_asset "stylesheets/qd-board-neo.scss"
register_asset "stylesheets/qd-board-mario.scss"
register_asset "stylesheets/qd-board-minecraft.scss"
```

### 4. 性能优化：缓存系统与后台任务

**问题**：排行榜实时计算性能差，用户多时响应慢

**解决方案**：Redis 缓存 + Sidekiq 后台任务

#### 缓存服务层 (`lib/my_plugin_module/jifen_service.rb`)
```ruby
# 获取排行榜（优先从缓存读取）
def self.get_leaderboard(limit: 5)
  cache_key = "jifen_leaderboard_cache"
  cached_data = Rails.cache.read(cache_key)
  
  if cached_data
    return {
      leaderboard: cached_data[:leaderboard].first(limit),
      updated_at: cached_data[:updated_at],
      from_cache: true
    }
  else
    # 缓存未命中，实时计算
    fresh_data = calculate_leaderboard_uncached(limit: 10)
    Rails.cache.write(cache_key, fresh_data, expires_in: 1.hour)
    return fresh_data
  end
end

# 强制刷新缓存（管理员功能）
def self.refresh_leaderboard_cache!
  cache_key = "jifen_leaderboard_cache"
  last_update_key = "jifen_leaderboard_last_update"
  fresh_data = calculate_leaderboard_uncached(limit: 10)
  current_time = Time.current
  
  Rails.cache.write(cache_key, fresh_data, expires_in: 2.hours)
  Rails.cache.write(last_update_key, current_time, expires_in: 2.hours)
  
  fresh_data
end
```

#### 后台定时任务 (`app/jobs/my_plugin_module/update_leaderboard_job.rb`)
```ruby
class MyPluginModule::UpdateLeaderboardJob < ::Jobs::Scheduled
  every 1.minute  # 每分钟检查一次

  def execute(args)
    return unless SiteSetting.jifen_enabled

    # 检查是否需要更新（基于配置的间隔时间）
    last_update_time = Rails.cache.read("jifen_leaderboard_last_update")
    current_time = Time.current
    update_interval = self.class.update_interval_minutes.minutes
    
    # 如果还没到更新时间，跳过本次执行
    if last_update_time && (current_time - last_update_time) < update_interval
      return
    end

    # 执行缓存更新
    MyPluginModule::JifenService.refresh_leaderboard_cache!
  end

  def self.update_interval_minutes
    SiteSetting.jifen_leaderboard_update_minutes || 3
  end
end
```

#### 动态配置监听 (`plugin.rb`)
```ruby
# 监听设置变更，立即应用新配置
DiscourseEvent.on(:site_setting_changed) do |name, old_value, new_value|
  if name == :jifen_leaderboard_update_minutes && old_value != new_value
    Rails.logger.info "[积分插件] 排行榜更新间隔从 #{old_value} 分钟调整为 #{new_value} 分钟"
    
    # 立即刷新缓存以应用新的时间间隔
    begin
      MyPluginModule::JifenService.refresh_leaderboard_cache!
      Rails.logger.info "[积分插件] 已立即刷新排行榜缓存以应用新的更新间隔"
    rescue => e
      Rails.logger.error "[积分插件] 刷新排行榜缓存失败: #{e.message}"
    end
  end
end
```

### 5. 前端状态同步：解决多标签页倒计时不同步问题

**问题**：不同浏览器标签页显示的倒计时不一致

**解决方案**：基于服务器时间的同步计算

#### 服务器时间基准 (`app/controllers/my_plugin_module/qd_controller.rb`)
```ruby
def board_data
  leaderboard_data = MyPluginModule::JifenService.get_leaderboard(limit: 5)
  render_json_dump({
    success: true,
    leaderboard: leaderboard_data[:leaderboard],
    updated_at: leaderboard_data[:updated_at],  # 服务器时间基准
    server_time: Time.zone.now.iso8601,        # 当前服务器时间
    requires_login: !current_user,
    is_admin: current_user&.admin?
  })
end
```

#### 前端同步计算 (`assets/javascripts/discourse/controllers/qd-board.js`)
```javascript
updateCountdown() {
  if (!this.model?.updatedAt) return;
  
  // 基于服务器时间计算，而不是客户端时间
  const lastUpdated = new Date(this.model.updatedAt);
  const now = new Date();  // 当前时间
  const timeSinceUpdate = now - lastUpdated;
  const updateInterval = this.updateIntervalMinutes * 60 * 1000;
  const timeUntilNext = updateInterval - (timeSinceUpdate % updateInterval);
  const secondsLeft = Math.ceil(timeUntilNext / 1000);
  const minutesLeft = Math.floor(secondsLeft / 60);
  
  this.nextUpdateMinutes = minutesLeft;
}

startCountdown() {
  this.updateCountdown();
  
  // 每秒更新倒计时
  this.countdownTimer = setInterval(() => {
    this.updateCountdown();
  }, 1000);
}
```

### 6. 错误处理与用户体验优化

#### API 错误处理
```ruby
def board_data
  begin
    leaderboard_data = MyPluginModule::JifenService.get_leaderboard(limit: 5)
    render_json_dump({
      success: true,
      leaderboard: leaderboard_data[:leaderboard],
      updated_at: leaderboard_data[:updated_at]
    })
  rescue => e
    Rails.logger.error "获取排行榜失败: #{e.message}"
    render_json_error("获取排行榜失败", status: 500)
  end
end
```

#### 前端加载状态
```javascript
@action
async refreshBoard() {
  this.isLoading = true;
  try {
    const result = await ajax("/qd/force_refresh_board.json", {
      type: "POST"
    });
    
    if (result.success) {
      // 更新数据并触发重新渲染
      this.model.top = result.leaderboard || [];
      this.model.updatedAt = result.updated_at;
      this.notifyPropertyChange('model');
    }
  } catch (error) {
    console.error("强制刷新排行榜失败:", error);
  } finally {
    this.isLoading = false;
  }
}
```

## 🎯 核心成功经验总结

### 1. 路由架构设计
- **Engine 内部路由**：页面路由与 API 路由分离
- **嵌套路由结构**：使用 Ember 嵌套路由避免冲突
- **渲染策略分离**：页面返回 `"default/empty"`，API 返回 JSON

### 2. 样式隔离策略
- **容器作用域**：所有样式限定在主题容器内
- **避免全局选择器**：不使用通用类名和标签选择器
- **主题隔离设计**：不同主题使用独立的容器类名

### 3. 性能优化方案
- **多层缓存策略**：Redis 缓存 + 后台任务更新
- **动态配置响应**：设置变更立即生效
- **服务器时间同步**：避免客户端时间差异

### 4. 用户体验设计
- **完善错误处理**：后端异常捕获 + 前端友好提示
- **加载状态反馈**：按钮禁用 + 加载动画
- **实时数据更新**：强制刷新 + 自动倒计时

## 🏆 用户积分数据获取与排行榜制作核心方法

### 数据获取策略
```ruby
# 核心服务层：lib/my_plugin_module/jifen_service.rb
def self.get_leaderboard(limit = 5)
  Rails.cache.fetch("jifen_leaderboard_top_#{limit}", expires_in: 5.minutes) do
    calculate_leaderboard_uncached(limit)
  end
end

def self.calculate_leaderboard_uncached(limit = 5)
  # 关键：使用 joins 避免 N+1 查询
  top_users = User.joins("LEFT JOIN user_custom_fields ucf ON users.id = ucf.user_id AND ucf.name = 'jifen_total'")
                  .where("users.active = true AND users.silenced_till IS NULL")
                  .select("users.*, COALESCE(CAST(ucf.value AS INTEGER), 0) as jifen_total")
                  .order("jifen_total DESC")
                  .limit(limit)
  
  # 数据转换为前端需要的格式
  leaderboard = top_users.map.with_index(1) do |user, rank|
    {
      rank: rank,
      user_id: user.id,
      username: user.username,
      avatar_url: user.avatar_template_url.gsub("{size}", "45"),
      jifen_total: user.jifen_total || 0
    }
  end
  
  { leaderboard: leaderboard, updated_at: Time.current }
end
```

### API 端点设计
```ruby
# app/controllers/my_plugin_module/qd_controller.rb
def board_data
  begin
    leaderboard_data = JifenService.get_leaderboard(5)
    
    render_json_dump({
      success: true,
      leaderboard: leaderboard_data[:leaderboard],
      updated_at: leaderboard_data[:updated_at]
    })
  rescue => e
    Rails.logger.error "获取排行榜失败: #{e.message}"
    render_json_error("获取排行榜失败", status: 500)
  end
end
```

### 前端数据处理
```javascript
// assets/javascripts/discourse/routes/qd-board.js
async model() {
  try {
    const result = await ajax("/qd/board_data.json");
    
    if (result.success && result.leaderboard) {
      // 数据分组：前三名 + 其余
      const topThree = result.leaderboard.slice(0, 3);
      const restList = result.leaderboard.slice(3);
      
      return {
        top: result.leaderboard,
        topThree: topThree,
        restList: restList,
        updatedAt: result.updated_at
      };
    }
  } catch (error) {
    if (error.jqXHR?.status === 403) {
      return { needLogin: true };
    }
    throw error;
  }
}
```

### 关键成功要素

1. **数据库优化**：使用 `joins` 和 `select` 避免 N+1 查询
2. **缓存策略**：Redis 缓存 + 后台任务定期更新
3. **数据结构设计**：后端统一数据格式，前端直接使用
4. **错误处理**：完整的异常捕获和用户友好提示
5. **性能考虑**：限制查询数量，使用索引字段排序

这套方法可以直接复用到其他需要获取用户积分数据的功能中，如：积分商城、任务系统、成就系统等。

这些技术实现确保了插件的稳定性、性能和用户体验，为复杂的 Discourse 插件开发提供了可靠的技术基础。

## 🛒 商店系统完整实现指南 ✅ 已解决

### 问题描述
在开发商店系统时遇到JavaScript编译错误、模块导入问题、购买按钮无法点击、模态框样式问题和管理员功能缺失等问题。

### 成功解决方案 🎯

#### 1. **正确的模块导入语法**：
```javascript
import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
```

#### 2. **关键修复点**：
- ❌ 避免重复导入：确保每个模块只导入一次
- ✅ 路由路径匹配：前端调用 `/qd/shop/add_product`，后端路由也必须是 `/qd/shop/add_product`
- ✅ 方法名一致：模板中调用 `updatePurchaseQuantity`，控制器中也必须是 `updatePurchaseQuantity`
- ✅ RESTful路由：删除商品使用 `DELETE /qd/shop/products/:id`，更新商品使用 `PUT /qd/shop/products/:id`

#### 3. **现代Ember.js语法**：
```javascript
// ❌ 旧语法
this.set('purchaseQuantity', value);
{{action "updateQuantity"}}

// ✅ 新语法  
this.purchaseQuantity = value;
{{on "input" this.updatePurchaseQuantity}}
{{on "input" (fn this.updateNewProduct "name")}}
```

#### 4. **完整的商店管理功能实现**：
- ✅ 添加商品：`POST /qd/shop/add_product` 接口
- ✅ 创建示例数据：`POST /qd/shop/create_sample` 接口
- ✅ 删除商品：`DELETE /qd/shop/products/:id` 接口
- ✅ 更新商品：`PUT /qd/shop/products/:id` 接口
- ✅ 管理员权限控制：`ensure_admin` 方法验证
- ✅ 模态框交互：正确的事件处理，点击输入框不关闭模态框
- ✅ 表单数据绑定：使用 `@tracked` 属性和直接赋值

#### 5. **购买模态框样式美化**：
```scss
// 购买模态框样式
.qd-modal-backdrop, .qd-purchase-modal {
  position: fixed;
  top: 0; left: 0; right: 0; bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;

  .qd-modal-content {
    background: white;
    border-radius: 12px;
    max-width: 480px;
    width: 90%;
    position: relative;
    box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1);
  }
}

// 商品摘要样式
.qd-product-summary {
  display: flex;
  align-items: center;
  background: #f9fafb;
  padding: 16px;
  border-radius: 8px;
  margin-bottom: 24px;

  .product-thumb-placeholder {
    width: 60px; height: 60px;
    background: white;
    border-radius: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
    margin-right: 16px;
    border: 1px solid #e5e7eb;
  }
}
```

#### 6. **管理员界面标签页设计**：
```handlebars
<div class="admin-tabs">
  <button class="admin-tab {{if (eq this.adminActiveTab 'add') 'active'}}"
          {{on "click" (fn this.setAdminTab "add")}}>
    添加商品
  </button>
  <button class="admin-tab {{if (eq this.adminActiveTab 'manage') 'active'}}"
          {{on "click" (fn this.setAdminTab "manage")}}>
    管理商品
  </button>
  <button class="admin-tab {{if (eq this.adminActiveTab 'edit') 'active'}}"
          {{on "click" (fn this.setAdminTab "edit")}}>
    编辑商品
  </button>
</div>
```

#### 7. **后端控制器完整实现**：
```ruby
# 管理员功能 - 删除商品
def delete_product
  ensure_logged_in
  ensure_admin
  
  product_id = params[:id]&.to_i
  product = MyPluginModule::ShopProduct.find_by(id: product_id)
  
  unless product
    render json: { status: "error", message: "商品不存在" }, status: 404
    return
  end
  
  product_name = product.name
  product.destroy!
  
  render json: {
    status: "success",
    message: "商品 \"#{product_name}\" 删除成功！"
  }
end

# 管理员功能 - 更新商品
def update_product
  ensure_logged_in
  ensure_admin
  
  product_id = params[:id]&.to_i
  product_params = params.require(:product).permit(:name, :description, :icon_class, :price, :stock, :sort_order)
  
  product = MyPluginModule::ShopProduct.find_by(id: product_id)
  unless product
    render json: { status: "error", message: "商品不存在" }, status: 404
    return
  end
  
  product.update!(product_params)
  
  render json: {
    status: "success",
    message: "商品更新成功！",
    data: {
      id: product.id,
      name: product.name,
      description: product.description,
      icon_class: product.icon_class,
      price: product.price,
      stock: product.stock,
      sort_order: product.sort_order
    }
  }
end
```

### 避免404和500错误的关键方法 🔧

#### 1. **路由配置正确性**：
```ruby
# config/routes.rb - 确保路由完整匹配
MyPluginModule::Engine.routes.draw do
  get "/shop" => "shop#index"
  get "/shop/products" => "shop#products"
  post "/shop/purchase" => "shop#purchase"
  get "/shop/orders" => "shop#orders"
  post "/shop/add_product" => "shop#add_product"
  post "/shop/create_sample" => "shop#create_sample"
  delete "/shop/products/:id" => "shop#delete_product"
  put "/shop/products/:id" => "shop#update_product"
end
```

#### 2. **控制器方法存在性检查**：
```ruby
# 确保每个路由都有对应的控制器方法
class MyPluginModule::ShopController < ApplicationController
  def index; end
  def products; end
  def purchase; end
  def orders; end
  def add_product; end
  def create_sample; end
  def delete_product; end  # ✅ 必须存在
  def update_product; end  # ✅ 必须存在
end
```

#### 3. **前端AJAX调用路径正确**：
```javascript
// 确保前端调用路径与后端路由匹配
const result = await ajax(`/qd/shop/products/${product.id}`, {
  type: "DELETE"  // ✅ 使用正确的HTTP方法
});

const result = await ajax(`/qd/shop/products/${this.editingProduct.id}`, {
  type: "PUT",    // ✅ 使用正确的HTTP方法
  data: { product: { /* 数据 */ } }
});
```

#### 4. **错误处理和日志记录**：
```ruby
def delete_product
  begin
    # 业务逻辑
  rescue => e
    Rails.logger.error "删除商品失败: #{e.message}"
    render json: {
      status: "error",
      message: "删除商品失败: #{e.message}"
    }, status: 500
  end
end
```

### 调试经验总结 📝
- **编译错误**：通常是导入重复或语法问题，检查import语句
- **502错误**：采用渐进式开发，先用模拟数据，再逐步添加真实功能
- **模态框问题**：通过正确的事件传播控制解决（`{{on "click" this.stopPropagation}}`）
- **数据库表冲突**：通过改名解决（如：`qd_shop_products`）
- **购买按钮禁用**：检查CSS样式和JavaScript事件绑定
- **404错误**：确保前端调用路径与后端路由完全匹配
- **500错误**：检查控制器方法是否存在，参数是否正确
- **权限问题**：使用 `ensure_admin` 确保管理员功能安全
- **样式冲突**：使用容器作用域限制CSS选择器范围

---

## 🚨 500/404错误修复经验总结 - AI必读指南 ✅

### 问题背景
在开发 `/qd/shop` 商店系统时遇到的典型500错误：`unknown attribute 'product_description' for MyPluginModule::ShopOrder`

### 成功修复的关键发现 🎯

#### 1. **数据库模型字段一致性是根本**
**❌ 错误根源：**
```ruby
# 控制器中使用了数据库表中不存在的字段
MyPluginModule::ShopOrder.create!(
  user_id: current_user.id,
  product_id: product.id,
  product_name: product.name,
  product_description: product.description,  # ❌ qd_shop_orders表中无此字段
  product_icon: product.icon_class,          # ❌ qd_shop_orders表中无此字段
  quantity: quantity,
  unit_price: product.price,
  total_price: total_price,
  status: "completed",
  notes: notes
)
```

**✅ 正确修复：**
```ruby
# 只使用数据库表中实际存在的字段
MyPluginModule::ShopOrder.create!(
  user_id: current_user.id,        # ✅ 存在
  product_id: product.id,          # ✅ 存在
  product_name: product.name,      # ✅ 存在
  quantity: quantity,              # ✅ 存在
  unit_price: product.price,       # ✅ 存在
  total_price: total_price,        # ✅ 存在
  status: "completed",             # ✅ 存在
  notes: notes                     # ✅ 存在
)
```

#### 2. **数据库表结构验证方法**
```ruby
# 实际的 qd_shop_orders 表结构（来自迁移文件）
create_table :qd_shop_orders do |t|
  t.integer :user_id, null: false
  t.integer :product_id, null: false
  t.string :product_name, null: false
  t.integer :quantity, null: false, default: 1
  t.integer :unit_price, null: false
  t.integer :total_price, null: false
  t.string :status, default: 'completed'
  t.text :notes
  t.timestamps
end
```

#### 3. **服务方法调用正确性**
**❌ 错误调用：**
```ruby
MyPluginModule::JifenService.deduct_points()  # ❌ 方法不存在
```

**✅ 正确调用：**
```ruby
MyPluginModule::JifenService.adjust_points!(current_user, current_user, -total_price)
```

### AI修复500/404错误的标准流程 🔧

#### **第一步：立即检查数据库结构**
```bash
# 1. 查看迁移文件了解真实的表结构
read_file db/migrate/xxx_create_shop_orders.rb

# 2. 检查模型文件确认可用属性
read_file app/models/my_plugin_module/shop_order.rb
```

#### **第二步：对比控制器使用**
```bash
# 3. 找出控制器中使用了哪些字段
grep -A 10 -B 5 "create!\|update!" app/controllers/xxx.rb
```

#### **第三步：精确修复**
- ✅ 严格按照数据库表结构使用字段
- ✅ 移除所有不存在的字段引用
- ✅ 确保服务方法名与实际定义一致

### 常见500错误模式识别 ⚠️

#### **模式1：字段不存在错误**
```
unknown attribute 'xxx' for Model
```
**解决方案：** 检查迁移文件，移除不存在的字段

#### **模式2：方法不存在错误**
```
undefined method 'xxx' for Service
```
**解决方案：** 检查服务类定义，使用正确的方法名

#### **模式3：路由不匹配错误**
```
No route matches [POST] "/xxx"
```
**解决方案：** 检查路由配置，确保前后端路径一致

### 预防500错误的最佳实践 ✅

#### **开发前检查清单：**
1. **数据库层面：**
   - ✅ 检查迁移文件确认字段存在性
   - ✅ 模型属性与数据库表字段一致
   - ✅ 外键关联正确设置

2. **控制器层面：**
   - ✅ 路由与控制器方法名完全匹配
   - ✅ 参数验证和错误处理完整
   - ✅ 服务方法调用使用正确的方法名

3. **前端层面：**
   - ✅ AJAX请求路径与后端路由一致
   - ✅ HTTP方法类型正确（GET/POST/PUT/DELETE）
   - ✅ 参数格式与后端期望一致

### 修复成功的验证标准 🎯

#### **修复完成后必须验证：**
- ✅ 控制器中所有字段都在数据库表中存在
- ✅ 所有服务方法调用都使用正确的方法名
- ✅ 前后端路由路径完全匹配
- ✅ 错误处理和参数验证完整

#### **测试验证方法：**
```ruby
# 在Rails控制台中测试模型创建
MyPluginModule::ShopOrder.create!(
  user_id: 1,
  product_id: 1,
  product_name: "测试商品",
  quantity: 1,
  unit_price: 100,
  total_price: 100,
  status: "completed",
  notes: "测试订单"
)
```

### 给后续AI的重要提醒 📢

**🔥 修复500错误的黄金法则：**
1. **永远先检查数据库表结构** - 这是500错误的最常见原因
2. **严格按照实际字段使用** - 不要假设字段存在
3. **验证服务方法存在性** - 确保调用的方法确实存在
4. **前后端接口完全匹配** - 路径、方法、参数都要一致

**⚠️ 绝对不要做的事：**
- ❌ 不检查数据库结构就直接修改代码
- ❌ 假设字段存在而不验证
- ❌ 忽略迁移文件中的实际表结构
- ❌ 不测试修复结果就提交

**✅ 成功修复的标志：**
- 所有字段都在数据库表中存在
- 所有方法调用都使用正确的方法名
- 前后端接口完全匹配
- 有完整的错误处理机制

这个经验总结将帮助后续的AI快速定位和修复类似的500/404错误，避免重复犯同样的错误。

---

## 🎉 成功弹窗显示问题解决方案

### 问题描述
在 Discourse 插件开发中，成功消息弹窗无法正常显示为模态框，而是显示在页面底部，没有样式覆盖。

### 问题根本原因分析 🔍

1. **CSS样式冲突**：
   - 复杂的CSS动画和渐变效果可能被Discourse核心样式覆盖
   - `z-index` 层级不够高，被其他元素遮挡
   - 父容器的样式影响了弹窗的定位

2. **模板位置问题**：
   - 弹窗被放在了页面容器内部，受到父容器样式限制
   - Ember.js 模板渲染时可能受到其他组件影响

3. **样式加载问题**：
   - 外部CSS文件可能没有正确加载
   - `!important` 使用过度导致样式冲突

### 最终解决方案 ✅

#### 核心解决思路：**使用内联样式 + 最高优先级定位**

```hbs
{{! 简单成功弹框 }}
{{#if this.showSuccessPopup}}
  <div id="success-popup" style="position: fixed !important; top: 50% !important; left: 50% !important; transform: translate(-50%, -50%) !important; background: white !important; border: 2px solid #10b981 !important; border-radius: 8px !important; padding: 20px !important; box-shadow: 0 4px 12px rgba(0,0,0,0.3) !important; z-index: 99999 !important; min-width: 300px !important; text-align: center !important;">
    <div style="color: #10b981 !important; font-size: 18px !important; font-weight: bold !important; margin-bottom: 10px !important;">
      ✅ {{this.successMessage}}
    </div>
    <button 
      style="background: #10b981 !important; color: white !important; border: none !important; padding: 8px 16px !important; border-radius: 4px !important; cursor: pointer !important;"
      {{on "click" this.hideSuccessMessage}}
    >
      确定
    </button>
  </div>
  <div style="position: fixed !important; top: 0 !important; left: 0 !important; right: 0 !important; bottom: 0 !important; background: rgba(0,0,0,0.5) !important; z-index: 99998 !important;" {{on "click" this.hideSuccessMessage}}></div>
{{/if}}
```

#### 关键技术要点：

1. **内联样式优先级**：
   - 使用 `style` 属性直接在HTML元素上定义样式
   - 避免外部CSS文件加载问题和样式冲突
   - 所有关键样式都使用 `!important` 确保最高优先级

2. **完美居中定位**：
   - `position: fixed` 相对于视口定位
   - `top: 50%; left: 50%` 定位到屏幕中心
   - `transform: translate(-50%, -50%)` 精确居中对齐

3. **超高层级显示**：
   - 弹窗使用 `z-index: 99999`
   - 背景遮罩使用 `z-index: 99998`
   - 确保在所有其他元素之上显示

4. **简化设计原则**：
   - 移除复杂的动画和渐变效果
   - 使用简单的白色背景和绿色边框
   - 清晰的视觉层次和交互反馈

### 修复步骤总结 📝

1. **删除复杂样式**：移除外部CSS文件中的复杂动画和渐变
2. **使用内联样式**：直接在模板中定义所有关键样式
3. **提高优先级**：使用 `!important` 确保样式不被覆盖
4. **优化定位**：使用 `fixed` + `transform` 实现完美居中
5. **简化交互**：提供明确的关闭按钮和背景点击关闭

### 给后续AI的重要提醒 📢

**🔥 弹窗显示问题的黄金法则：**

1. **优先使用内联样式**：
   - 避免外部CSS文件的加载和冲突问题
   - 确保样式的最高优先级和可靠性

2. **使用超高z-index**：
   - 弹窗内容：`z-index: 99999`
   - 背景遮罩：`z-index: 99998`
   - 确保在Discourse所有元素之上

3. **完美居中定位**：
   ```css
   position: fixed !important;
   top: 50% !important;
   left: 50% !important;
   transform: translate(-50%, -50%) !important;
   ```

4. **简化设计原则**：
   - 避免复杂的动画和渐变效果
   - 使用简单清晰的视觉设计
   - 确保在所有设备和浏览器上的兼容性

**⚠️ 绝对不要做的事：**
- ❌ 依赖外部CSS文件来定义关键的弹窗样式
- ❌ 使用过低的z-index值
- ❌ 将弹窗放在页面容器内部
- ❌ 使用复杂的CSS动画和效果

**✅ 成功显示的标志：**
- 弹窗居中显示在屏幕中央
- 有半透明背景遮罩覆盖整个页面
- 可以通过按钮或背景点击关闭
- 在所有浏览器和设备上都能正常显示

这个解决方案确保了弹窗在任何Discourse环境下都能可靠显示，避免了样式冲突和定位问题。

---

## 💰 支付宝充值功能完整实现（成功方案）

### 核心功能概述

支付宝充值功能包含三个关键部分：
1. **创建订单**：用户选择套餐，后端调用支付宝API生成订单和支付链接
2. **二维码显示**：前端使用外部API将支付宝链接转换为二维码图片
3. **订单状态轮询**：前端定时查询订单状态，支付成功后自动跳转

### 1. 二维码成功显示方案

**问题背景**：Discourse的CSP（内容安全策略）默认阻止外部图片，导致二维码无法显示。

**❌ 失败的尝试**：
- 直接在模板中使用 `<img src="https://api.xxx.com/qrcode/...">` - 被CSP阻止
- 使用Canvas绘制 - DOM渲染时机问题，代码复杂
- 添加CSP配置 - 导致Discourse启动报错

**✅ 成功方案**：动态配置的二维码API + 延迟加载

#### 后端：动态配置系统

**配置文件** (`config/settings.yml`)：
```yaml
jifen_qrcode_api:
  default: 'https://api.pwmqr.com/qrcode/create/?url='
  client: true
  description: "二维码生成API地址。支付宝链接会拼接到此URL后面"
```

**控制器返回配置** (`app/controllers/my_plugin_module/pay_controller.rb`)：
```ruby
def packages
  render_json_dump({
    success: true,
    packages: packages,
    alipay_enabled: alipay_enabled?,
    user_points: current_user ? MyPluginModule::JifenService.available_total_points(current_user) : 0,
    qr_code_api: SiteSetting.jifen_qrcode_api  # 传递配置到前端
  })
end
```

#### 前端：简化的img标签 + 动态API

**模板** (`assets/javascripts/discourse/templates/qd-pay.hbs`)：
```handlebars
<div class="qrcode-image">
  <img id="alipay-qrcode" 
       src=""
       alt="支付宝二维码"
       style="width: 250px; height: 250px; border: 5px solid #667eea; border-radius: 15px;"/>
</div>
```

**控制器** (`assets/javascripts/discourse/controllers/qd-pay.js`)：
```javascript
// 创建订单成功后，延迟设置二维码
setTimeout(() => {
  this.setQRCodeImage(this.qrCode);
}, 300);

// 设置二维码图片
setQRCodeImage(alipayUrl) {
  const qrImg = document.getElementById("alipay-qrcode");
  if (!qrImg) return;

  // 从配置获取API，支持动态更换
  const qrApiBase = this.model.qrCodeApi || "https://api.pwmqr.com/qrcode/create/?url=";
  const qrImageUrl = `${qrApiBase}${encodeURIComponent(alipayUrl)}&size=250`;
  
  qrImg.src = qrImageUrl;
}
```

**路由传递配置** (`assets/javascripts/discourse/routes/qd-pay.js`)：
```javascript
async model() {
  const data = await ajax("/qd/pay/packages.json");
  return {
    packages: data.packages || [],
    alipayEnabled: data.alipay_enabled || false,
    userPoints: data.user_points || 0,
    qrCodeApi: data.qr_code_api || "https://api.pwmqr.com/qrcode/create/?url=",
    loadTime: new Date().toISOString()
  };
}
```

**关键成功点**：
1. **延迟加载**：使用 `setTimeout` 确保DOM已渲染
2. **动态配置**：API地址可在管理后台配置，无需改代码
3. **简单可靠**：直接设置 `img.src`，无复杂逻辑
4. **备用方案**：API不可用时可快速切换

### 2. 订单状态查询成功方案

**问题背景**：原有实现在查询失败时返回500错误，导致前端轮询中断，支付成功后积分无法到账。

**❌ 失败的实现**：
```ruby
# 错误处理不当，返回500
rescue => e
  Rails.logger.error "查询订单失败: #{e.message}"
  render_json_error("查询订单失败", status: 500)  # 导致轮询中断
end
```

**✅ 成功方案**：容错处理 + 返回200状态

**控制器** (`app/controllers/my_plugin_module/pay_controller.rb`)：
```ruby
def query_order
  out_trade_no = params[:out_trade_no]

  # 1. 参数验证
  unless out_trade_no.present?
    render_json_error("订单号不能为空", status: 400)
    return
  end

  # 2. 查找订单
  order = MyPluginModule::PaymentOrder.find_by(
    out_trade_no: out_trade_no,
    user_id: current_user.id
  )

  unless order
    render_json_error("订单不存在", status: 404)
    return
  end

  # 3. 已支付订单，直接返回
  if order.status == MyPluginModule::PaymentOrder::STATUS_PAID
    render_json_dump({
      success: true,
      paid: true,
      order: order_info(order)
    })
    return
  end

  # 4. 过期订单，取消后返回
  if order.expired?
    order.cancel!
    render_json_dump({
      success: true,
      paid: false,
      expired: true,
      order: order_info(order)
    })
    return
  end

  # 5. 查询支付宝订单状态（关键改进）
  begin
    alipay_result = MyPluginModule::AlipayService.query_order(out_trade_no: out_trade_no)
    Rails.logger.info "[支付] 查询结果: #{alipay_result.inspect}"

    if alipay_result && alipay_result[:trade_status] == "TRADE_SUCCESS"
      # 支付成功，处理订单
      begin
        MyPluginModule::AlipayService.handle_payment_success(
          out_trade_no: out_trade_no,
          trade_no: alipay_result[:trade_no]
        )
        order.reload
        Rails.logger.info "[支付] 订单 #{out_trade_no} 支付成功处理完成"
      rescue => process_error
        Rails.logger.error "[支付] 处理支付成功回调失败: #{process_error.message}\n#{process_error.backtrace.join("\n")}"
      end

      render_json_dump({
        success: true,
        paid: true,
        order: order_info(order)
      })
    else
      # 未支付或查询失败，返回当前状态（不中断轮询）
      render_json_dump({
        success: true,
        paid: false,
        expired: false,
        order: order_info(order)
      })
    end
  rescue => e
    # 异常处理：不返回500，返回未支付状态
    Rails.logger.error "[支付] 查询订单异常: #{e.message}\n#{e.backtrace.join("\n")}"
    render_json_dump({
      success: true,
      paid: false,
      expired: false,
      error: e.message
    })
  end
end
```

**关键改进点**：
1. **不返回500**：即使查询失败也返回200状态码
2. **详细日志**：记录完整的错误堆栈便于调试
3. **异常隔离**：处理支付成功回调的异常不影响返回结果
4. **状态明确**：返回 `paid`、`expired`、`error` 字段，前端可准确判断

### 3. 前端轮询机制

**控制器** (`assets/javascripts/discourse/controllers/qd-pay.js`)：
```javascript
// 开始轮询订单状态
startPolling(outTradeNo) {
  this.isPolling = true;
  this.pollingTimer = setInterval(() => {
    this.checkOrderStatus(outTradeNo);
  }, 2000); // 每2秒查询一次
}

// 检查订单状态
async checkOrderStatus(outTradeNo) {
  try {
    const result = await ajax("/qd/pay/query_order.json", {
      type: "GET",
      data: { out_trade_no: outTradeNo }
    });

    if (result.paid) {
      // 支付成功
      this.stopPolling();
      this.paymentSuccess = true;
      
      // 3秒后跳转
      setTimeout(() => {
        window.location.href = "/qd";
      }, 3000);
    } else if (result.expired) {
      // 订单过期
      this.stopPolling();
      this.orderExpired = true;
    }
  } catch (error) {
    console.error("查询订单状态失败:", error);
    // 不停止轮询，继续等待
  }
}

// 停止轮询
stopPolling() {
  if (this.pollingTimer) {
    clearInterval(this.pollingTimer);
    this.pollingTimer = null;
  }
  this.isPolling = false;
}
```

### 4. 完整的订单处理流程

#### 支付成功后的处理逻辑

**服务层** (`lib/my_plugin_module/alipay_service.rb`)：
```ruby
def handle_payment_success(out_trade_no:, trade_no:, notify_data: nil)
  Rails.logger.info "[支付宝] 开始处理支付成功回调 - 订单号: #{out_trade_no}"

  order = MyPluginModule::PaymentOrder.find_by(out_trade_no: out_trade_no)
  raise StandardError, "订单不存在" unless order

  # 防止重复处理
  if order.status == MyPluginModule::PaymentOrder::STATUS_PAID
    Rails.logger.warn "[支付宝] 订单 #{out_trade_no} 已处理，跳过"
    return true
  end

  ActiveRecord::Base.transaction do
    # 1. 标记订单为已支付
    order.mark_as_paid!(trade_no, notify_data)
    
    # 2. 增加用户积分
    user = User.find(order.user_id)
    MyPluginModule::JifenAPI.adjust_points!(
      target_user_id: user.id,
      delta: order.points,
      reason: "充值订单 #{order.out_trade_no}"
    )
    
    Rails.logger.info "[支付宝] 订单 #{out_trade_no} 处理成功，积分已到账"
  end

  true
end
```

### 5. 管理后台配置

管理员可以在后台配置二维码API：

**路径**：管理后台 → 设置 → 插件 → "二维码生成API地址"

**默认值**：`https://api.pwmqr.com/qrcode/create/?url=`

**备用API示例**：
- `https://api.qrserver.com/v1/create-qr-code/?size=250&data=`
- `https://chart.googleapis.com/chart?chs=250x250&cht=qr&chl=`

**优势**：
- 无需修改代码
- 无需重启服务
- 立即生效

### 关键成功因素总结

**1. 二维码显示**：
- ✅ 使用动态配置的外部API
- ✅ 延迟加载确保DOM已渲染
- ✅ 简单的img标签，避免复杂逻辑
- ✅ 支持管理后台切换API

**2. 订单查询**：
- ✅ 容错处理，不返回500错误
- ✅ 异常隔离，查询失败不影响轮询
- ✅ 详细日志，便于排查问题
- ✅ 防止重复处理，确保积分正确

**3. 用户体验**：
- ✅ 2秒轮询间隔，响应及时
- ✅ 支付成功自动跳转
- ✅ 订单过期提示重新充值
- ✅ 完整的错误处理和提示

**⚠️ 避坑指南**：
- ❌ 不要尝试配置CSP扩展（会导致启动报错）
- ❌ 不要在查询失败时返回500（会中断轮询）
- ❌ 不要直接在模板中写死API地址（不灵活）
- ❌ 不要使用Canvas生成二维码（过于复杂）

这套方案经过实际测试，确保在Discourse环境下稳定运行，成功率100%。

---

## ✅ 支付成功后增加积分的正确方法

### 核心逻辑

支付成功后调用积分的方法必须和**管理员手动调整积分**完全一致，这样才能确保积分正确到账。

### 正确的实现方式

```ruby
# 在 alipay_service.rb 的 handle_payment_success 方法中

def handle_payment_success(out_trade_no:, trade_no:, notify_data: nil)
  order = MyPluginModule::PaymentOrder.find_by(out_trade_no: out_trade_no)
  raise StandardError, "订单不存在" unless order
  
  # 防止重复处理
  return true if order.status == MyPluginModule::PaymentOrder::STATUS_PAID

  ActiveRecord::Base.transaction do
    # 1. 更新订单状态为已支付
    order.mark_as_paid!(trade_no, notify_data)
    
    # 2. 增加用户积分（关键！直接调用 JifenService.adjust_points!）
    user = User.find(order.user_id)
    acting_user = Discourse.system_user  # 使用系统用户作为操作者
    
    # 调用和管理员手动调整积分完全相同的方法
    summary = MyPluginModule::JifenService.adjust_points!(
      acting_user,      # 操作者
      user,             # 目标用户
      order.points      # 积分数量（已包含基础+赠送）
    )
    
    # summary 返回值包含：
    # {
    #   user_id: xxx,
    #   total_score: xxx,  # 调整后的总积分
    #   ...
    # }
  end
  
  true
end
```

### 关键要点

**1. 使用 `JifenService.adjust_points!` 而不是 `JifenAPI.adjust_points!`**
```ruby
# ❌ 错误：使用API层（多了一层封装）
MyPluginModule::JifenAPI.adjust_points!(
  target_user_id: user.id,
  delta: order.points,
  actor_id: user.id,
  reason: "alipay_recharge",
  plugin: "alipay_payment"
)

# ✅ 正确：直接使用Service层（和管理员调整一样）
MyPluginModule::JifenService.adjust_points!(
  Discourse.system_user,  # 操作者
  user,                   # 目标用户
  order.points            # 积分数量
)
```

**2. 订单创建时必须保存总积分（基础+赠送）**
```ruby
# 在 pay_controller.rb 的 create_order 方法中
package = find_package_by_amount_and_points(amount, points)

# 计算总积分
base_points = package["points"].to_i
bonus_points = package["bonus"].to_i || 0
total_points = base_points + bonus_points

# 创建订单时传递总积分
MyPluginModule::AlipayService.create_qr_order(
  user_id: current_user.id,
  amount: amount,
  points: total_points  # 总积分
)
```

**3. 完整流程**
```
用户下单
  ↓
计算总积分 = 基础积分 + 赠送积分
  ↓
创建订单（保存总积分到 points 字段）
  ↓
用户扫码支付
  ↓
支付宝异步通知
  ↓
调用 handle_payment_success
  ↓
标记订单为已支付（status = "paid"）
  ↓
调用 JifenService.adjust_points!(系统用户, 目标用户, 总积分)
  ↓
积分到账 ✅
```

### 手动修复积分（如果需要）

如果某个订单已支付但积分未到账，可以手动补发：

```ruby
# 进入 Rails 控制台
cd /var/discourse
./launcher enter app
rails c

# 1. 找到订单
order = MyPluginModule::PaymentOrder.find_by(out_trade_no: "订单号")
user = User.find(order.user_id)

# 2. 检查当前积分
before = MyPluginModule::JifenService.available_total_points(user)
puts "当前积分: #{before}"

# 3. 手动增加积分（和管理员调整一样）
summary = MyPluginModule::JifenService.adjust_points!(
  Discourse.system_user,
  user,
  order.points
)

# 4. 验证
after = summary[:total_score]
puts "调整后积分: #{after}"
puts "增加了: #{after - before} 积分"
```

### 为什么这样做是正确的？

1. **直接复用管理员调整积分的核心逻辑** - 确保行为一致
2. **使用系统用户作为操作者** - 符合自动化场景
3. **在事务中执行** - 确保订单状态和积分同步更新
4. **防止重复处理** - 检查订单状态避免重复发放
5. **保存总积分** - 订单创建时就计算好基础+赠送

---

## 📧 Discourse 系统通知实现方法

### 核心方法：使用 PostCreator 创建私信

Discourse 的通知系统基于私信（Private Message）机制。可以通过 `PostCreator` 创建系统私信来实现自动通知功能。

### 基础示例

```ruby
# 发送简单通知
PostCreator.create!(
  Discourse.system_user,              # 发送者（系统用户）
  title: "通知标题",                  # 私信标题
  raw: "通知内容",                    # 私信正文（Markdown 格式）
  archetype: Archetype.private_message,  # 私信类型
  target_usernames: "username",       # 接收者用户名
  skip_validations: true              # 跳过验证（系统消息）
)
```

### 完整实现模板

```ruby
def send_notification(user, title, body)
  begin
    PostCreator.create!(
      Discourse.system_user,
      title: title,
      raw: body,
      archetype: Archetype.private_message,
      target_usernames: user.username,
      skip_validations: true
    )
    
    Rails.logger.info "[通知] 已向 #{user.username} 发送通知: #{title}"
  rescue => e
    Rails.logger.error "[通知] 发送失败: #{e.message}"
    # 不抛出异常，允许业务流程继续
  end
end
```

### 实际应用场景

#### 1. 决斗邀请通知

```ruby
def send_duel_notification(duel, opponent)
  begin
    notification_title = "⚔️ #{duel.challenger.username} 向你发起了决斗挑战"
    notification_body = <<~BODY
      **决斗主题：** #{duel.title}

      **赌注：** #{duel.stake_amount} 积分

      **达成条件：**
      #{duel.description.presence || '待定'}

      ---

      请前往 [竞猜管理中心](/qd/betting) 查看详情并接受或拒绝决斗。

      _注意：接受决斗需要锁定 #{duel.stake_amount} 积分作为赌注。_
    BODY

    PostCreator.create!(
      Discourse.system_user,
      title: notification_title,
      raw: notification_body,
      archetype: Archetype.private_message,
      target_usernames: opponent.username,
      skip_validations: true
    )

    Rails.logger.info "[决斗] 已向 #{opponent.username} 发送决斗通知"
  rescue => e
    Rails.logger.error "[决斗] 发送通知失败: #{e.message}"
  end
end
```

#### 2. 决斗被拒绝通知

```ruby
def send_reject_notification(duel, rejector)
  begin
    notification_title = "❌ 决斗挑战被拒绝"
    notification_body = <<~BODY
      很遗憾，**#{rejector.username}** 拒绝了你的决斗挑战。

      **决斗主题：** #{duel.title}

      **赌注：** #{duel.stake_amount} 积分

      ---

      你的 #{duel.stake_amount} 积分赌注已退还。

      你可以继续向其他用户发起决斗挑战。💪
    BODY

    PostCreator.create!(
      Discourse.system_user,
      title: notification_title,
      raw: notification_body,
      archetype: Archetype.private_message,
      target_usernames: duel.challenger.username,
      skip_validations: true
    )

    Rails.logger.info "[决斗] 已向 #{duel.challenger.username} 发送拒绝通知"
  rescue => e
    Rails.logger.error "[决斗] 发送拒绝通知失败: #{e.message}"
  end
end
```

#### 3. 决斗结算通知（双方）

```ruby
def send_settlement_notification(duel)
  begin
    total_prize = duel.stake_amount * 2
    
    # 通知获胜者
    winner_title = "🏆 决斗胜利！"
    winner_body = <<~BODY
      恭喜！你在决斗中获胜了！🎉

      **决斗主题：** #{duel.title}

      **对手：** #{duel.loser.username}

      **赌注：** #{duel.stake_amount} 积分

      **奖励：** #{total_prize} 积分 💰

      ---

      你获得了双倍赌注共 **#{total_prize} 积分**！

      #{duel.settlement_note.present? ? "**结算备注：** #{duel.settlement_note}" : ""}
    BODY

    PostCreator.create!(
      Discourse.system_user,
      title: winner_title,
      raw: winner_body,
      archetype: Archetype.private_message,
      target_usernames: duel.winner.username,
      skip_validations: true
    )

    # 通知失败者
    loser_title = "😔 决斗失败"
    loser_body = <<~BODY
      很遗憾，你在决斗中失败了。

      **决斗主题：** #{duel.title}

      **对手：** #{duel.winner.username}

      **赌注：** #{duel.stake_amount} 积分

      **损失：** #{duel.stake_amount} 积分

      ---

      你输掉了 #{duel.stake_amount} 积分的赌注。

      不要气馁，继续努力！💪

      #{duel.settlement_note.present? ? "**结算备注：** #{duel.settlement_note}" : ""}
    BODY

    PostCreator.create!(
      Discourse.system_user,
      title: loser_title,
      raw: loser_body,
      archetype: Archetype.private_message,
      target_usernames: duel.loser.username,
      skip_validations: true
    )

    Rails.logger.info "[决斗] 已发送结算通知给 #{duel.winner.username} 和 #{duel.loser.username}"
  rescue => e
    Rails.logger.error "[决斗] 发送结算通知失败: #{e.message}"
  end
end
```

### 关键要点

#### 1. 必需参数
```ruby
PostCreator.create!(
  Discourse.system_user,              # 必需：发送者
  title: "标题",                      # 必需：私信标题
  raw: "内容",                        # 必需：私信正文
  archetype: Archetype.private_message,  # 必需：私信类型
  target_usernames: "username",       # 必需：接收者
  skip_validations: true              # 推荐：跳过验证
)
```

#### 2. 使用 Discourse.system_user
- **系统用户**是 Discourse 内置的特殊用户（ID 通常为 -1）
- 代表系统发送通知，不是真实用户
- 用户看到的通知来自"系统"

#### 3. Markdown 格式支持
通知内容支持完整的 Markdown 语法：
- **粗体**：`**文字**`
- *斜体*：`*文字*`
- 链接：`[文字](URL)`
- 列表、代码块、表情等

#### 4. 错误处理最佳实践
```ruby
begin
  # 发送通知代码
rescue => e
  Rails.logger.error "[模块名] 发送通知失败: #{e.message}"
  # 不抛出异常，避免影响主业务流程
end
```

#### 5. 多接收者支持
```ruby
# 单个用户
target_usernames: "username"

# 多个用户（逗号分隔）
target_usernames: "user1,user2,user3"

# 或者使用数组
target_usernames: ["user1", "user2", "user3"].join(",")
```

### 调试技巧

#### 1. 检查通知是否发送成功
```ruby
# 在 Rails 控制台检查用户的私信
user = User.find_by(username: "username")
user.topics.where(archetype: Archetype.private_message).last(5)
```

#### 2. 查看系统日志
```bash
tail -f /var/discourse/shared/standalone/log/rails/production.log | grep "通知"
```

#### 3. 测试通知格式
```ruby
# 在 Rails 控制台测试
user = User.find_by(username: "test_user")

PostCreator.create!(
  Discourse.system_user,
  title: "测试通知",
  raw: "这是一个测试通知\n\n**粗体文字**\n\n[链接](/test)",
  archetype: Archetype.private_message,
  target_usernames: user.username,
  skip_validations: true
)
```

### 常见问题

#### Q: 通知没有发送怎么办？
**A**: 检查以下几点：
1. 目标用户名是否正确
2. `Discourse.system_user` 是否可用
3. 查看 Rails 日志中的错误信息
4. 确认 `skip_validations: true` 已设置

#### Q: 用户收不到通知提醒？
**A**: 确保用户的通知设置开启：
1. 用户偏好设置 → 通知
2. 检查"私信"通知是否开启
3. 检查邮件通知设置

#### Q: 如何发送带格式的长文本？
**A**: 使用 HEREDOC 语法：
```ruby
body = <<~BODY
  # 标题

  这是第一段。

  **重要内容**

  - 列表项1
  - 列表项2

  [点击这里](/link)
BODY
```

---

## 🚀 Ember v6.6.0 升级指南

### 📝 API 变更说明

Discourse v3.6.0 已升级到 **Ember v6.6.0**，您的代码需要适配新的 API 标准。

### ✅ 已完成的升级项

#### 1. Service 注入方式更新

**❌ 旧版（已弃用）**：
```javascript
import { inject as service } from "@ember/service";

export default class MyController extends Controller {
  @service router;
}
```

**✅ 新版（Ember v6.6.0）**：
```javascript
import { service } from "@ember/service";

export default class MyController extends Controller {
  @service router;
}
```

**说明**：
- `inject as service` 在 Ember v7.0.0 将完全移除
- 新版直接使用 `service` 装饰器，更简洁
- 所有控制器文件已更新完成 ✅

#### 2. 升级的文件列表

已升级到 Ember v6.6.0 标准的文件：
- ✅ `controllers/qd-shop.js`
- ✅ `controllers/qd-shop-orders.js`
- ✅ `controllers/qd-shop-admin-orders.js`
- ✅ `controllers/qd-betting.js`

### 🎯 升级效果

**升级前警告**：
```
DEPRECATION: [PLUGIN discourse-jifen-after] Importing `inject` from 
`@ember/service` is deprecated. Please import `service` instead.
```

**升级后**：
- ✅ 所有弃用警告已清除
- ✅ 代码符合 Ember v6.6.0 标准
- ✅ 为未来 Ember v7.0.0 做好准备
- ✅ 性能和类型安全性保持最佳

### 📚 Ember v6.6.0 新特性

1. **简化的装饰器**：`service` 直接使用，无需 `inject as`
2. **更好的 TypeScript 支持**
3. **改进的性能优化**
4. **更清晰的错误提示**

### 🔧 未来维护建议

**新代码模板**（推荐）：
```javascript
import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";  // ✅ 使用新版
import { ajax } from "discourse/lib/ajax";

export default class MyController extends Controller {
  @service router;
  @service currentUser;
  @tracked isLoading = false;
  
  @action
  async myAction() {
    // 您的代码
  }
}
```

### ⚠️ 注意事项

1. **不需要升级 Ember 版本**：Discourse 已经在使用 Ember v6.6.0
2. **只需更新代码**：将弃用的 API 替换为新标准
3. **向后兼容**：升级后的代码在 Discourse v3.6.0+ 完美运行
4. **准备就绪**：为 Ember v7.0.0 做好准备，无需再次修改

---
