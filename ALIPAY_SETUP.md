# 支付宝当面付充值功能配置指南

## 功能概述

本插件集成了支付宝当面付（扫码支付）功能，用户可以通过支付宝充值积分。

**访问路径**：`/qd/pay`

**核心功能**：
- ✅ 扫码支付（生成支付宝二维码）
- ✅ 充值套餐管理（可配置多个套餐）
- ✅ 订单自动查询（支付后自动到账）
- ✅ 异步通知处理（支付宝回调）
- ✅ 订单管理（查看充值记录）
- ✅ 测试模式（未配置时可使用模拟二维码测试）

---

## 一、申请支付宝开放平台账号

### 1. 注册开发者账号

访问：https://open.alipay.com/

1. 使用支付宝账号登录
2. 创建应用（选择"网页/移动应用"）
3. 填写应用信息并提交审核

### 2. 配置应用

审核通过后：

1. **获取 APPID**：
   - 进入应用详情页
   - 复制应用的 APPID（格式：2021xxxxxxxxxx）

2. **配置应用公钥**：
   - 下载"支付宝开放平台开发助手"
   - 生成 RSA2 密钥对（2048位）
   - 复制**应用公钥**到支付宝开放平台
   - 保存**应用私钥**（后续需要配置到 Discourse）
   - 获取**支付宝公钥**（用于验证支付宝签名）

3. **申请产品权限**：
   - 在应用中申请"当面付"产品
   - 等待审核通过（通常需要1-3个工作日）

4. **配置异步通知地址**：
   - 设置网关地址：`https://your-domain.com/qd/pay/notify`
   - 确保该地址可以被支付宝服务器访问

---

## 二、Discourse 插件配置

### 1. 进入管理后台

访问：`https://your-domain.com/admin/site_settings/category/jifen`

### 2. 配置支付宝参数

找到"支付宝充值"相关设置：

#### （1）启用支付宝充值

```
jifen_alipay_enabled: true
```

#### （2）配置支付宝 APPID

```
jifen_alipay_app_id: 2021xxxxxxxxxx
```
（从支付宝开放平台获取）

#### （3）配置商户私钥

```
jifen_alipay_private_key: 
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA...（完整的私钥内容）
-----END RSA PRIVATE KEY-----
```

**注意**：
- 私钥必须包含完整的头尾标识
- 如果是单行格式，需要保留 `\n` 换行符
- 或者直接粘贴多行格式的私钥

#### （4）配置支付宝公钥

```
jifen_alipay_public_key: 
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A...（完整的公钥内容）
-----END PUBLIC KEY-----
```

**注意**：这里配置的是**支付宝公钥**，不是应用公钥！

### 3. 配置充值套餐

```json
jifen_recharge_packages:
[
  {
    "amount": 10,
    "points": 100,
    "label": "体验装"
  },
  {
    "amount": 50,
    "points": 550,
    "bonus": 50
  },
  {
    "amount": 100,
    "points": 1200,
    "bonus": 200,
    "label": "热销"
  },
  {
    "amount": 500,
    "points": 6500,
    "bonus": 1500
  }
]
```

**字段说明**：
- `amount`：充值金额（元），必填
- `points`：获得积分，必填
- `bonus`：额外赠送积分，可选
- `label`：套餐标签（如"推荐"、"热销"），可选

---

## 三、测试支付流程

### 1. 测试模式（未配置支付宝时）

如果未配置支付宝参数，系统会自动进入测试模式：

- 生成模拟二维码（以 `MOCK_QR_` 开头）
- 订单查询返回模拟数据
- 可以测试前端流程和界面

### 2. 沙箱环境测试

支付宝提供沙箱环境用于测试：

1. 访问：https://openhome.alipay.com/dev/sandbox/app
2. 获取沙箱 APPID 和密钥
3. 下载"支付宝沙箱版"APP
4. 使用沙箱账号测试支付

**沙箱网关地址**：
```
https://openapi.alipaydev.com/gateway.do
```

**修改代码使用沙箱**（测试完成后记得改回）：
```ruby
# lib/my_plugin_module/alipay_service.rb
GATEWAY_URL = "https://openapi.alipaydev.com/gateway.do"  # 沙箱
# GATEWAY_URL = "https://openapi.alipay.com/gateway.do"   # 正式
```

### 3. 正式环境测试

配置完成后：

1. 访问 `/qd/pay`
2. 选择充值套餐
3. 点击"立即充值"
4. 使用支付宝扫描二维码
5. 完成支付后，积分自动到账

---

## 四、功能架构说明

### 1. 数据库表

**`jifen_payment_orders`** - 支付订单表

| 字段 | 类型 | 说明 |
|------|------|------|
| user_id | integer | 用户ID |
| out_trade_no | string | 商户订单号（唯一） |
| trade_no | string | 支付宝交易号 |
| amount | decimal | 支付金额 |
| points | integer | 兑换积分 |
| status | string | 订单状态（pending/paid/cancelled/refunded） |
| qr_code | string | 支付宝二维码地址 |
| paid_at | datetime | 支付完成时间 |
| expires_at | datetime | 订单过期时间（5分钟） |

### 2. 核心文件

**后端**：
```
db/migrate/20250101000003_create_payment_orders.rb  - 数据库迁移
app/models/my_plugin_module/payment_order.rb        - 订单模型
lib/my_plugin_module/alipay_service.rb              - 支付宝SDK
app/controllers/my_plugin_module/pay_controller.rb  - 支付控制器
config/routes.rb                                     - 路由配置
```

**前端**：
```
assets/javascripts/discourse/routes/qd-pay.js       - 路由处理器
assets/javascripts/discourse/controllers/qd-pay.js  - 控制器逻辑
assets/javascripts/discourse/templates/qd-pay.hbs   - 页面模板
assets/stylesheets/qd-pay.scss                      - 页面样式
```

### 3. API 接口

| 接口 | 方法 | 说明 |
|------|------|------|
| /qd/pay | GET | 充值页面（Ember引导） |
| /qd/pay/packages | GET | 获取充值套餐 |
| /qd/pay/create_order | POST | 创建充值订单 |
| /qd/pay/query_order | GET | 查询订单状态 |
| /qd/pay/orders | GET | 用户订单列表 |
| /qd/pay/notify | POST | 支付宝异步通知回调 |

---

## 五、异步通知验证

支付宝会在支付成功后，向配置的异步通知地址发送 POST 请求。

### 验证流程

1. **接收通知**：`/qd/pay/notify`
2. **验证签名**：使用支付宝公钥验证签名
3. **验证参数**：
   - 订单号是否存在
   - 金额是否匹配
   - 订单状态是否已处理
4. **处理订单**：
   - 标记订单为已支付
   - 增加用户积分
   - 记录日志
5. **返回结果**：`success` 或 `fail`

### 安全说明

- ✅ 签名验证确保请求来自支付宝
- ✅ 订单号唯一性防止重复处理
- ✅ 金额验证防止篡改
- ✅ 事务处理确保数据一致性
- ✅ 日志记录便于追踪问题

---

## 六、常见问题排查

### 1. 签名验证失败

**原因**：
- 私钥或公钥配置错误
- 密钥格式不正确（缺少头尾标识）
- 使用了错误的密钥（应用私钥 vs 支付宝公钥）

**解决**：
- 检查密钥是否包含 `-----BEGIN` 和 `-----END`
- 确认配置的是支付宝公钥，不是应用公钥
- 重新生成密钥对并重新配置

### 2. 二维码无法生成

**原因**：
- APPID 配置错误
- 应用未开通"当面付"权限
- 网络无法访问支付宝网关

**解决**：
- 检查 APPID 是否正确
- 确认应用已通过"当面付"审核
- 检查服务器是否可以访问 `openapi.alipay.com`

### 3. 支付成功但积分未到账

**原因**：
- 异步通知未收到
- 签名验证失败
- 订单处理异常

**解决**：
- 检查 Discourse 日志：`/var/discourse/shared/standalone/log/rails/production.log`
- 搜索关键词：`[支付宝]`
- 确认异步通知地址可被外网访问
- 手动查询订单状态

### 4. 订单过期

**说明**：
- 订单有效期为 5 分钟
- 过期后需要重新创建订单

**调整有效期**：
```ruby
# lib/my_plugin_module/alipay_service.rb
expires_at: 10.minutes.from_now  # 改为10分钟
```

---

## 七、生产环境部署检查清单

- [ ] 支付宝应用已通过审核
- [ ] "当面付"产品权限已开通
- [ ] APPID 配置正确
- [ ] 商户私钥配置正确（包含头尾）
- [ ] 支付宝公钥配置正确（包含头尾）
- [ ] 异步通知地址可被外网访问
- [ ] HTTPS 已启用（支付宝要求）
- [ ] 充值套餐已配置
- [ ] 测试支付流程完整
- [ ] 日志记录正常

---

## 八、技术亮点

本实现完全遵循 `panda.md` 技术规范：

✅ **Rails Engine 架构**：模块化设计，易于维护  
✅ **Ember v5.12.0**：现代化前端框架  
✅ **Glimmer Components**：响应式状态管理（`@tracked`、`@action`）  
✅ **幂等性保障**：订单唯一性约束，防止重复处理  
✅ **安全性**：RSA2 签名验证，订单金额校验  
✅ **用户体验**：实时订单查询，支付成功自动跳转  
✅ **测试友好**：支持测试模式和沙箱环境  
✅ **日志完善**：关键操作均有日志记录  

---

## 九、联系与支持

如有问题，请查看：
- Discourse 日志：`/var/discourse/shared/standalone/log/rails/production.log`
- 支付宝开发文档：https://opendocs.alipay.com/open/194
- 插件 GitHub：https://github.com/werta666/discourse-jifen-after

---

**祝您使用愉快！** 🎉
