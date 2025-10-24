# 🪙 付费币系统完整实现文档

## 📋 概述

付费币系统是一个**独立于免费积分**的充值货币系统。用户通过支付宝充值获得付费币，可用于商店购物、竞猜等付费功能。

### 核心特点

✅ **完全独立** - 与免费签到积分系统完全分离  
✅ **充值专用** - 仅通过支付宝充值获得  
✅ **交易记录** - 完整的充值/消费记录  
✅ **余额查询** - 实时查询付费币余额  
✅ **管理功能** - 管理员可调整用户付费币  

---

## 🏗️ 系统架构

### 1. 数据存储方式

付费币使用 **用户自定义字段（User Custom Fields）** 存储：

```ruby
# 字段说明
paid_coins        # 付费币总额（充值累计）
paid_coins_spent  # 已消费的付费币

# 可用余额计算
available_coins = paid_coins - paid_coins_spent
```

### 2. 交易记录表

数据库表：`jifen_paid_coin_records`

| 字段 | 类型 | 说明 |
|------|------|------|
| user_id | integer | 用户ID |
| amount | integer | 变动数量（正数=增加，负数=减少） |
| action_type | string | 操作类型（recharge/consume/adjust/refund） |
| reason | string | 原因说明 |
| related_id | integer | 关联ID（如订单ID） |
| related_type | string | 关联类型（如 PaymentOrder） |
| balance_after | integer | 操作后余额 |

---

## 🔧 核心服务层：PaidCoinService

### 基础查询方法

```ruby
# 获取用户付费币总余额（充值总额）
MyPluginModule::PaidCoinService.total_coins(user)

# 获取用户已消费的付费币
MyPluginModule::PaidCoinService.spent_coins(user)

# 获取用户当前可用付费币余额
MyPluginModule::PaidCoinService.available_coins(user)

# 检查用户是否有足够的付费币
MyPluginModule::PaidCoinService.has_enough_coins?(user, 100)

# 获取用户付费币概览
MyPluginModule::PaidCoinService.summary_for(user)
# => { user_id: 1, username: "admin", total_coins: 1000, spent_coins: 200, available_coins: 800 }
```

### 核心操作方法

#### 1. 增加付费币（充值）

```ruby
MyPluginModule::PaidCoinService.add_coins!(
  user,
  100,                           # 充值数量
  reason: "支付宝充值订单",       # 原因说明
  related_id: order.id,          # 关联订单ID（可选）
  related_type: "PaymentOrder"   # 关联类型（可选）
)
# => { user_id: 1, amount: 100, before_available: 0, after_available: 100 }
```

#### 2. 扣除付费币（消费）

```ruby
MyPluginModule::PaidCoinService.deduct_coins!(
  user,
  50,                            # 扣除数量
  reason: "商店购买商品",         # 原因说明
  related_id: shop_order.id,     # 关联订单ID（可选）
  related_type: "ShopOrder"      # 关联类型（可选）
)
# => { user_id: 1, amount: 50, before_available: 100, after_available: 50 }
```

#### 3. 管理员调整付费币

```ruby
# 增加付费币（正数）
MyPluginModule::PaidCoinService.adjust_coins!(
  acting_user,    # 管理员
  target_user,    # 目标用户
  100             # +100付费币
)

# 减少付费币（负数）
MyPluginModule::PaidCoinService.adjust_coins!(
  acting_user,
  target_user,
  -50             # -50付费币
)
```

#### 4. 重置付费币（清零）

```ruby
MyPluginModule::PaidCoinService.reset_coins!(
  acting_user,    # 管理员
  target_user     # 目标用户
)
# => { before_available: 100, after_available: 0 }
```

---

## 💰 充值流程完整说明

### 用户充值流程

```
1. 用户访问 /qd/pay
   ↓
2. 选择充值套餐（如：¥10 = 100付费币 + 赠送20付费币）
   ↓
3. 点击"立即充值" → 调用 PayController#create_order
   ↓
4. 后端调用 AlipayService.create_qr_order 创建支付宝订单
   ↓
5. 返回二维码地址给前端，前端显示二维码
   ↓
6. 用户扫码支付
   ↓
7. 前端每2秒轮询查询订单状态（PayController#query_order）
   ↓
8. 支付宝异步通知 → PayController#notify
   ↓
9. 调用 AlipayService.handle_payment_success
   ↓
10. 调用 PaidCoinService.add_coins! 增加付费币
   ↓
11. 前端检测到支付成功，显示成功消息，3秒后跳转
```

### 关键代码流程

#### 后端处理支付成功

```ruby
# lib/my_plugin_module/alipay_service.rb
def handle_payment_success(out_trade_no:, trade_no:, notify_data: nil)
  order = MyPluginModule::PaymentOrder.find_by(out_trade_no: out_trade_no)
  
  # 防止重复处理
  return true if order.status == MyPluginModule::PaymentOrder::STATUS_PAID

  ActiveRecord::Base.transaction do
    # 1. 标记订单为已支付
    order.mark_as_paid!(trade_no, notify_data)
    
    # 2. 给用户增加付费币
    user = User.find(order.user_id)
    
    MyPluginModule::PaidCoinService.add_coins!(
      user,
      order.points,  # 付费币数量 = 订单积分数（已包含基础+赠送）
      reason: "支付宝充值订单 #{out_trade_no}",
      related_id: order.id,
      related_type: "PaymentOrder"
    )
  end
  
  true
end
```

---

## 🛠️ API 接口说明

### 1. 获取充值套餐（包含付费币余额）

**请求**：`GET /qd/pay/packages.json`

**响应**：
```json
{
  "success": true,
  "packages": [
    {
      "amount": 10,
      "points": 100,
      "bonus": 20,
      "label": "热销"
    }
  ],
  "alipay_enabled": true,
  "wechat_enabled": false,
  "user_paid_coins": 500,  // 用户当前付费币余额
  "qr_code_api": "https://api.pwmqr.com/qrcode/create/?url="
}
```

### 2. 获取付费币余额详情

**请求**：`GET /qd/pay/balance.json`

**响应**：
```json
{
  "success": true,
  "balance": {
    "user_id": 1,
    "username": "admin",
    "total_coins": 1000,
    "spent_coins": 200,
    "available_coins": 800
  }
}
```

### 3. 创建充值订单

**请求**：`POST /qd/pay/create_order.json`
```json
{
  "amount": 10,
  "points": 100,
  "payment_method": "alipay"
}
```

**响应**：
```json
{
  "success": true,
  "order_id": 123,
  "out_trade_no": "JIFEN20250124153000ABCD",
  "qr_code": "https://qr.alipay.com/xxx",
  "amount": 10.0,
  "points": 120,  // 包含基础100 + 赠送20
  "expires_at": "2025-01-24T15:32:00Z"
}
```

### 4. 查询订单状态

**请求**：`GET /qd/pay/query_order.json?out_trade_no=xxx`

**响应**：
```json
{
  "success": true,
  "paid": true,
  "order": {
    "id": 123,
    "out_trade_no": "JIFEN20250124153000ABCD",
    "amount": 10.0,
    "points": 120,
    "status": "paid",
    "paid_at": "2025-01-24T15:31:30Z"
  }
}
```

---

## 🎯 使用场景示例

### 场景1：商店购物扣除付费币

```ruby
# app/controllers/my_plugin_module/shop_controller.rb
def purchase
  product = MyPluginModule::ShopProduct.find(params[:product_id])
  quantity = params[:quantity].to_i
  total_price = product.price * quantity
  
  # 检查付费币余额
  unless MyPluginModule::PaidCoinService.has_enough_coins?(current_user, total_price)
    render_json_error("付费币余额不足", status: 400)
    return
  end
  
  ActiveRecord::Base.transaction do
    # 1. 创建订单
    order = MyPluginModule::ShopOrder.create!(
      user_id: current_user.id,
      product_id: product.id,
      quantity: quantity,
      total_price: total_price
    )
    
    # 2. 扣除付费币
    MyPluginModule::PaidCoinService.deduct_coins!(
      current_user,
      total_price,
      reason: "购买商品：#{product.name}",
      related_id: order.id,
      related_type: "ShopOrder"
    )
    
    # 3. 扣除商品库存
    product.decrement!(:stock, quantity)
  end
  
  render_json_dump({ success: true, message: "购买成功" })
end
```

### 场景2：管理员补偿用户付费币

```ruby
# Rails 控制台
user = User.find_by(username: "某用户")

# 补偿100付费币
MyPluginModule::PaidCoinService.adjust_coins!(
  Discourse.system_user,
  user,
  100
)

# 查看调整后余额
MyPluginModule::PaidCoinService.summary_for(user)
```

### 场景3：退款返还付费币

```ruby
def refund_order
  order = MyPluginModule::ShopOrder.find(params[:id])
  
  # 返还付费币
  MyPluginModule::PaidCoinService.add_coins!(
    order.user,
    order.total_price,
    reason: "订单退款：#{order.product_name}",
    related_id: order.id,
    related_type: "ShopOrder"
  )
  
  order.update!(status: "refunded")
  
  render_json_dump({ success: true, message: "退款成功" })
end
```

---

## 📊 数据库迁移

### 运行迁移

```bash
cd /var/discourse
./launcher enter app
rake db:migrate
```

### 创建的表

1. **jifen_paid_coin_records** - 付费币交易记录表

### 新增的索引

- `idx_paid_coin_records_user` - 用户ID索引
- `idx_paid_coin_records_created` - 创建时间索引
- `idx_paid_coin_records_user_created` - 复合索引（用户+时间）

---

## ⚠️ 重要注意事项

### 1. 付费币 vs 免费积分

| 项目 | 付费币 | 免费积分 |
|------|--------|----------|
| 获取方式 | 支付宝充值 | 每日签到 |
| 存储位置 | `paid_coins` 字段 | `jifen_total` 累计 |
| 服务层 | `PaidCoinService` | `JifenService` |
| 用途 | 商店购物、高级功能 | 基础功能 |
| 可退款 | ✅ 支持 | ❌ 不支持 |

### 2. 事务安全

所有涉及付费币变动的操作**必须在事务中**执行：

```ruby
ActiveRecord::Base.transaction do
  # 1. 业务操作
  # 2. 付费币变动
end
```

### 3. 防止重复处理

支付成功回调必须检查订单状态：

```ruby
return true if order.status == MyPluginModule::PaymentOrder::STATUS_PAID
```

### 4. 余额检查

扣除付费币前必须检查余额：

```ruby
unless MyPluginModule::PaidCoinService.has_enough_coins?(user, amount)
  raise StandardError, "付费币余额不足"
end
```

---

## 🧪 测试验证

### 1. 测试充值流程

```ruby
# Rails 控制台
user = User.find_by(username: "test_user")

# 模拟充值100付费币
MyPluginModule::PaidCoinService.add_coins!(
  user,
  100,
  reason: "测试充值"
)

# 查看余额
MyPluginModule::PaidCoinService.available_coins(user)
# => 100
```

### 2. 测试消费流程

```ruby
# 扣除50付费币
MyPluginModule::PaidCoinService.deduct_coins!(
  user,
  50,
  reason: "测试消费"
)

# 查看余额
MyPluginModule::PaidCoinService.available_coins(user)
# => 50
```

### 3. 测试余额不足

```ruby
# 尝试扣除超过余额的付费币
begin
  MyPluginModule::PaidCoinService.deduct_coins!(user, 1000, reason: "测试")
rescue => e
  puts e.message
  # => "付费币余额不足（当前: 50，需要: 1000）"
end
```

### 4. 查看交易记录

```ruby
# 查看用户的所有交易记录
records = MyPluginModule::PaidCoinRecord
  .where(user_id: user.id)
  .order(created_at: :desc)
  .limit(10)

records.each do |r|
  puts "#{r.action_type}: #{r.amount} - #{r.reason} (余额: #{r.balance_after})"
end
```

---

## 🔍 故障排查

### 问题1：充值后付费币未到账

**排查步骤**：

1. 检查订单状态：
```ruby
order = MyPluginModule::PaymentOrder.find_by(out_trade_no: "订单号")
puts order.status  # 应为 "paid"
```

2. 检查付费币余额：
```ruby
user = User.find(order.user_id)
MyPluginModule::PaidCoinService.summary_for(user)
```

3. 查看日志：
```bash
tail -f /var/discourse/shared/standalone/log/rails/production.log | grep "付费币"
```

### 问题2：扣除付费币失败

**可能原因**：
- 余额不足
- 用户不存在
- 未在事务中执行

**解决方法**：
```ruby
# 检查余额
MyPluginModule::PaidCoinService.available_coins(user)

# 确保在事务中
ActiveRecord::Base.transaction do
  MyPluginModule::PaidCoinService.deduct_coins!(user, amount, reason: "xxx")
end
```

---

## 📈 后续扩展建议

1. **付费币流水查询页面** - 用户可查看自己的充值/消费记录
2. **付费币转账功能** - 用户之间可以转账付费币
3. **付费币奖励系统** - 完成任务奖励付费币
4. **付费币套餐优惠** - 限时充值优惠活动
5. **付费币统计报表** - 管理员查看充值/消费统计

---

## ✅ 总结

付费币系统现已完整实现，具备以下特性：

- ✅ 完全独立的充值货币体系
- ✅ 完整的增删查改功能
- ✅ 交易记录追溯
- ✅ 管理员调整功能
- ✅ 事务安全保障
- ✅ 防重复处理
- ✅ 详细的日志记录

**核心文件清单**：
- `lib/my_plugin_module/paid_coin_service.rb` - 服务层
- `app/models/my_plugin_module/paid_coin_record.rb` - 模型
- `db/migrate/20250124000001_create_paid_coin_records.rb` - 迁移
- `lib/my_plugin_module/alipay_service.rb` - 支付集成
- `app/controllers/my_plugin_module/pay_controller.rb` - 控制器
- `assets/javascripts/discourse/templates/qd-pay.hbs` - 前端模板
