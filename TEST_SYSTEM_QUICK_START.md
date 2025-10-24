# 🚀 装饰系统测试 - 快速开始指南

## ✅ 已完成的文件

### 后端文件
1. ✅ `config/routes.rb` - 添加了测试路由
2. ✅ `app/controllers/my_plugin_module/test_controller.rb` - 测试控制器
3. ✅ `app/serializers/user_serializer_extension.rb` - 用户序列化器扩展
4. ✅ `plugin.rb` - 加载序列化器扩展

### 前端文件
5. ✅ `assets/javascripts/discourse/qd-route-map.js` - 添加路由映射
6. ✅ `assets/javascripts/discourse/routes/qd-test.js` - 路由处理器
7. ✅ `assets/javascripts/discourse/controllers/qd-test.js` - 控制器
8. ✅ `assets/javascripts/discourse/templates/qd-test.hbs` - 模板
9. ✅ `assets/stylesheets/qd-test.scss` - 样式文件
10. ✅ `assets/javascripts/discourse/initializers/avatar-frame-init.js` - 头像框初始化器（现代API）
11. ✅ `assets/javascripts/discourse/initializers/decoration-badge-init.js` - 勋章初始化器（现代API）

### 文档文件
12. ✅ `AVATAR_FRAME_BADGE_GUIDE.md` - 完整技术文档
13. ✅ `TEST_SYSTEM_QUICK_START.md` - 本文档

---

## 🎯 测试步骤

### 第一步：重启 Discourse
```bash
cd /var/discourse
./launcher rebuild app
# 或
./launcher restart app
```

### 第二步：访问测试页面
打开浏览器访问：`http://你的域名/qd/test`

### 第三步：上传头像框（需要管理员权限）
1. 在"头像框测试"部分，点击"上传头像框"按钮
2. 选择一个PNG或JPG图片（建议尺寸：150x150px，透明背景）
3. 等待上传成功提示

### 第四步：装备头像框
1. 在头像框列表中，点击任一头像框的"装备"按钮
2. 等待装备成功提示，页面会自动刷新

### 第五步：上传装饰勋章（需要管理员权限）
**图片勋章**：
1. 在"装饰勋章测试"部分，确保选择"图片勋章"标签
2. 输入勋章名称
3. 点击"上传图片勋章"选择文件
4. 等待上传成功

**文字勋章**：
1. 切换到"文字勋章"标签
2. 输入勋章名称
3. 输入显示文字（如"VIP"、"管理员"）
4. 可选：输入CSS样式（如：`background: red; color: white;`）
5. 点击"上传文字勋章"

### 第六步：装备勋章
1. 在勋章列表中，点击任一勋章的"装备"按钮
2. 等待装备成功提示，页面会自动刷新

### 第七步：验证效果
1. 去论坛首页或任何帖子
2. **发一个新帖子或回复**
3. 查看你的头像 - 应该显示头像框
4. 查看你的用户名 - 应该在右侧显示勋章

---

## 🔍 调试指南

### 检查浏览器控制台
打开浏览器开发者工具（F12），查看Console标签，应该看到：
```
✅ 头像框数据已加载 {1: {id: 1, name: "..."}}
✅ 装饰勋章数据已加载 {1: {id: 1, name: "..."}}
```

### 检查网络请求
在Network标签中，应该看到以下成功的请求：
- `GET /qd/test/frames` - 状态码 200
- `GET /qd/test/badges` - 状态码 200

### 常见问题

**问题1：页面404错误**
- 检查路由是否正确添加到 `config/routes.rb`
- 检查控制器文件是否存在
- 重启 Discourse

**问题2：头像框/勋章不显示**
- 检查浏览器控制台是否有错误
- 确认数据已成功加载（查看console.log）
- 刷新页面清除缓存
- 确认用户序列化器已加载（检查 `plugin.rb`）

**问题3：上传失败**
- 检查文件格式是否正确（PNG/JPG）
- 检查是否有管理员权限
- 查看 Rails 日志：`/var/discourse/shared/standalone/log/rails/production.log`

**问题4：装备后没有效果**
- 确认已刷新页面
- 发一个新帖子测试（不是查看旧帖子）
- 检查初始化器是否正确加载

---

## 📁 文件上传位置

头像框和勋章文件会保存在：
- **头像框**：`public/uploads/default/avatar-frames/`
- **装饰勋章**：`public/uploads/default/decoration-badges/`

访问URL格式：
- 头像框：`/uploads/default/avatar-frames/frame_xxxxx.png`
- 勋章：`/uploads/default/decoration-badges/badge_xxxxx.png`

---

## 🎨 现代化 API 使用说明

本实现使用了以下现代化 Discourse API：

1. **api.customUserAvatarClasses()**
   - 为头像添加自定义CSS类
   - 在 `avatar-frame-init.js` 中使用

2. **api.addPosterIcons()**
   - 在用户名旁添加图标/徽章
   - 在 `decoration-badge-init.js` 中使用
   - 这是显示勋章的推荐方式

3. **api.decorateCooked()**
   - 在帖子内容渲染后处理DOM
   - 用于添加头像框覆盖层

4. **User Serializer Extension**
   - 将自定义字段暴露给前端
   - `avatar_frame_id` 和 `equipped_decoration_badge`

**完全避免使用**：
- ❌ `api.decorateWidget()` - 已过时
- ❌ `api.modifyClass()` - 已过时
- ❌ Widget System - 旧版系统

---

## 📚 参考文档

- **完整技术文档**：`AVATAR_FRAME_BADGE_GUIDE.md`
- **panda.md**：框架和渲染方法参考

---

## ✨ 功能特点

✅ **现代化实现** - 使用 Ember v6.6.0 和 Glimmer Components  
✅ **无过时代码** - 完全避免 Widget API  
✅ **全站显示** - 头像框和勋章在所有帖子、回复中显示  
✅ **易于扩展** - 清晰的代码结构  
✅ **性能优化** - 数据缓存和按需加载  
✅ **管理员友好** - 简单的上传界面  
✅ **用户友好** - 一键装备

---

## 🎉 完成！

现在你可以：
1. 访问 `/qd/test` 测试系统
2. 上传和装备头像框
3. 上传和装备装饰勋章
4. 在论坛中看到装饰效果

如果遇到问题，请查看完整技术文档 `AVATAR_FRAME_BADGE_GUIDE.md` 或检查浏览器控制台和 Rails 日志。
