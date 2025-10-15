# discourse-jifen-after 插件内部 API（Ruby 首选，v1）

本文件面向“同一 Discourse 实例内的其他插件”提供稳定的 Ruby API 门面，零网络开销，自动复用本插件的事务、风控与审计。仅中文。

- 插件名：discourse-jifen-after
- 作者：Pandacc（https://github.com/werta666/discourse-jifen-after）
- Ruby 门面模块：`::MyPluginModule::JifenAPI`
- 版本：`API_VERSION = "1.0"`
- 注意：优先使用 Ruby API。HTTP 端点仅用于跨进程/外部系统（见文末可选）。

---

## 1. 能力总览（最小稳定面）

- 查询可用积分：`available_points_for(user_id:) -> Integer`
- 管理加/减积分：`adjust_points!(target_user_id:, delta:, actor_id: nil, reason: "plugin_adjust", plugin: nil) -> Hash(最新概览)`

说明：
- delta 为整数：正数＝加分；负数＝减分；0 将抛出错误
- 所有写操作记录后台审计（StaffActionLogger），并做口径保护（可用积分不为负）
- 返回结构与本插件前端/服务保持一致，字段全中文

---

## 2. 在你的插件中调用（推荐姿势）

在你的插件 `plugin.rb` 的 `after_initialize` 中软依赖调用：

```ruby
after_initialize do
  if defined?(::MyPluginModule) && defined?(::MyPluginModule::JifenAPI)
    # ① 查询可用积分（只读）
    available = ::MyPluginModule::JifenAPI.available_points_for(user_id: current_user.id)
    Rails.logger.info("可用积分=#{available}")

    # ② 管理加/减积分（写入，自动审计）
    # actor_id 可空，默认使用系统用户 Discourse.system_user 记录审计
    summary = ::MyPluginModule::JifenAPI.adjust_points!(
      target_user_id: current_user.id,
      delta: 10,
      reason: "my_plugin_bonus",
      plugin: "my_plugin"
    )
    Rails.logger.info("调整后可用积分=#{summary[:total_score]}")
  end
end
```

软依赖说明：
- 使用 `defined?` 防止加载顺序问题
- 若你需要在引导时立即调用，可将逻辑包裹在 `DiscourseEvent.on(:site_settings_changed)` 或自定义初始化流程中

---

## 3. API 详细说明

### 3.1 查询可用积分

签名：
```ruby
::MyPluginModule::JifenAPI.available_points_for(user_id:) -> Integer
```

参数：
- user_id: Integer 目标用户 ID

返回：
- 整数，可用积分（累计签到所得 − 已消费）

可能异常：
- `Discourse::NotFound` 用户不存在

示例：
```ruby
available = ::MyPluginModule::JifenAPI.available_points_for(user_id: 42)
```

### 3.2 管理加/减积分

签名：
```ruby
::MyPluginModule::JifenAPI.adjust_points!(target_user_id:, delta:, actor_id: nil, reason: "plugin_adjust", plugin: nil) -> Hash
```

参数：
- target_user_id: Integer 目标用户 ID
- delta: Integer 正数加分，负数减分（0 将报错）
- actor_id: Integer 可选，操作者用户 ID；缺省采用 `Discourse.system_user`
- reason: String 可选，业务原因（便于审计区分）
- plugin: String 可选，调用来源插件名（便于审计区分）

返回（Hash，节选）：
- `:total_score` 调整后“可用积分”
- 其他字段与 `/qd/summary.json` 一致（例如 `:consecutive_days`、`:points` 等）

可能异常：
- `Discourse::NotFound` 用户不存在
- `StandardError` 业务校验失败（如 delta=0）

示例：
```ruby
summary = ::MyPluginModule::JifenAPI.adjust_points!(
  target_user_id: 42,
  delta: -5,
  reason: "consume_in_my_plugin",
  plugin: "my_plugin"
)
puts summary[:total_score]
```

---

## 4. 行为与口径

- “可用积分”口径：`累计签到所得（含补签与连续奖励） − 已消费`
- 写操作采用数据库事务，审计通过 `StaffActionLogger` 记录（操作者、对象、变更）
- 保护规则：可用积分不会被调成负数（内部钳制）
- 补签计分比例可通过站点设置 `jifen_makeup_ratio_percent` 配置（默认 100%）

---

## 5. 兼容与演进

- 语义化版本：门面常量 `API_VERSION = "1.0"`
- 新增字段将保持兼容；若有破坏性变更，将发布 `2.x` 并在文档说明

---

## 6. 可选：HTTP 端点（跨进程/外部系统）

若确需 HTTP（例如外部任务或跨语言），可使用：
- `GET /qd/api/v1/balance.json?username=alice`（查询）
- `POST /qd/api/v1/adjust_points.json`（调整，建议仅管理员用）
这些端点默认有权限与审计约束，谨慎使用。内部插件优先走 Ruby API。

---