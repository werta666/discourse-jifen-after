# frozen_string_literal: true

# 仅在 Engine 内定义后端接口，主挂载在 plugin.rb 的 after_initialize 中完成
MyPluginModule::Engine.routes.draw do
  # Ember 引导页（/qd 和 /qd/board）
  get "/" => "qd#index"
  get "/board" => "qd#index"

  # 签到/积分数据接口（仅中文 JSON）
  get "/summary" => "qd#summary"         # 返回页面所需概览：是否登录、今日/总积分、连续天数、基础分、今日是否已签、安装日期、补签卡信息等
  get "/records" => "qd#records"         # 返回签到记录（时间、是否补签、获得积分），按时间倒序
  get "/board_data" => "qd#board"        # 返回积分排行榜前五名用户数据
  post "/force_refresh_board" => "qd#force_refresh_board"  # 管理员强制刷新排行榜缓存
  post "/signin" => "qd#signin"          # 今日签到
  post "/makeup" => "qd#makeup"          # 补签（占位，后续可实现）
  post "/buy_makeup_card" => "qd#buy_makeup_card"  # 购买补签卡（占位，后续可实现）

  # API v1（供内部/自动化集成使用）
  scope "/api" do
    scope "/v1" do
      get "/balance" => "api#balance"             # /qd/api/v1/balance.json
      post "/adjust_points" => "api#adjust_points" # /qd/api/v1/adjust_points.json
    end
  end

  # 管理端调试/同步（qd.hbs 中的“管理员调试”）
  post "/admin/sync" => "admin#sync"
  post "/admin/adjust_points" => "admin#adjust_points"
  post "/admin/reset_today" => "admin#reset_today"

  # 电竞竞猜路由（新版）
  get "/betting" => "betting#index"                          # 竞猜页面
  get "/betting/events" => "betting#events"                  # 事件列表
  get "/betting/events/:id" => "betting#show"                # 事件详情
  post "/betting/place_bet" => "betting#place_bet"           # 投注/投票
  get "/betting/my_records" => "betting#my_records"          # 我的投注记录
  get "/betting/my_stats" => "betting#my_stats"              # 我的统计
  get "/betting/admin" => "qd#betting_admin_page"            # 管理后台页面
  
  # 竞猜管理路由（管理员）
  post "/betting/admin/create_event" => "betting_admin#create_event"        # 创建事件
  put "/betting/admin/events/:id" => "betting_admin#update_event"           # 更新事件
  post "/betting/admin/events/:id/activate" => "betting_admin#activate_event"  # 激活事件
  post "/betting/admin/events/:id/finish" => "betting_admin#finish_event"      # 结束事件
  post "/betting/admin/events/:id/cancel" => "betting_admin#cancel_event"      # 取消事件
  delete "/betting/admin/events/:id" => "betting_admin#delete_event"           # 删除事件
  post "/betting/admin/events/:id/set_winner" => "betting_admin#set_winner"    # 设置获胜选项
  post "/betting/admin/events/:id/settle" => "betting_admin#settle_event"      # 结算事件
  get "/betting/admin/events" => "betting_admin#events_list"                   # 管理员事件列表
  get "/betting/admin/events/:id/stats" => "betting_admin#event_stats"         # 事件统计

  # 决斗路由
  post "/duel/create" => "duel#create_duel"                  # 发起决斗
  post "/duel/:id/accept" => "duel#accept_duel"              # 接受决斗
  post "/duel/:id/reject" => "duel#reject_duel"              # 拒绝决斗
  post "/duel/:id/cancel" => "duel#cancel_duel"              # 取消决斗
  get "/duel/my" => "duel#my_duels"                          # 我的决斗
  get "/duel/pending" => "duel#pending_duels"                # 待处理的决斗
  get "/duel/active" => "duel#active_duels"                  # 正在进行的决斗

  # 决斗管理路由（管理员）
  get "/duel/admin/list" => "duel_admin#index"               # 决斗列表
  post "/duel/admin/:id/settle" => "duel_admin#settle"       # 结算决斗
  post "/duel/admin/:id/cancel" => "duel_admin#cancel"       # 取消决斗（审核失败）
  delete "/duel/admin/:id" => "duel_admin#destroy"           # 删除决斗

  # 商店路由
  get "/shop" => "shop#index"
  get "/shop/products" => "shop#products"
  post "/shop/purchase" => "shop#purchase"
  get "/shop/orders" => "shop#orders"
  post "/shop/exchange_coins" => "shop#exchange_coins"  # 付费币兑换积分
  
  # 商店管理路由
  post "/shop/add_product" => "shop#add_product"
  post "/shop/create_sample" => "shop#create_sample"
  delete "/shop/products/:id" => "shop#delete_product"
  put "/shop/products/:id" => "shop#update_product"
  
  # 管理员订单管理路由
  get "/shop/admin/orders" => "shop#admin_orders"
  patch "/shop/admin/orders/:id/status" => "shop#update_order_status"
  delete "/shop/admin/orders/:id" => "shop#delete_order"
  post "/shop/admin/orders/:id/refund" => "shop#refund_order"

  # 支付宝充值路由（付费币系统）
  get "/pay" => "pay#index"                    # 充值页面
  get "/pay/balance" => "pay#balance"          # 获取付费币余额
  get "/pay/packages" => "pay#packages"        # 获取充值套餐
  post "/pay/create_order" => "pay#create_order"  # 创建充值订单
  get "/pay/query_order" => "pay#query_order"  # 查询订单状态
  post "/pay/cancel_order" => "pay#cancel_order"  # 取消订单
  get "/pay/orders" => "pay#orders"            # 用户订单列表
  post "/pay/notify" => "pay#notify"           # 支付宝异步通知回调
  post "/pay/wechat_notify" => "pay#wechat_notify"  # 微信支付异步通知回调
  
  # 管理员订单管理
  get "/pay/admin" => "pay#admin"
  get "/pay/admin/stats" => "pay#admin_stats"
  delete "/pay/admin/clear_unpaid" => "pay#clear_unpaid_orders"
  post "/pay/admin/adjust_coins" => "pay#adjust_coins"
  
  # 装饰系统 - 个人页面
  get "/dress" => "dress#index"
  post "/dress/equip-frame" => "dress#equip_frame"
  post "/dress/equip-badge" => "dress#equip_badge"
  post "/dress/batch-user-decorations" => "dress#batch_user_decorations"
  
  # 装饰系统 - 管理界面（管理员）
  get "/dress/admin" => "dress#admin"
  get "/dress/frames" => "dress#frames"
  get "/dress/badges" => "dress#badges"
  get "/dress/my-decorations" => "dress#my_decorations"
  post "/dress/upload-frame" => "dress#upload_frame"
  post "/dress/upload-badge" => "dress#upload_badge"
  put "/dress/update-frame-params" => "dress#update_frame_params"
  put "/dress/update-badge-params" => "dress#update_badge_params"
  delete "/dress/delete-frame" => "dress#delete_frame"
  delete "/dress/delete-badge" => "dress#delete_badge"
  
  # 装饰授予系统（管理员）
  post "/dress/grant" => "dress#grant_decoration"
  post "/dress/revoke" => "dress#revoke_grant"
  get "/dress/grants" => "dress#grants"
  delete "/dress/delete_revoked_grants" => "dress#delete_revoked_grants"
  
  # VIP系统
  get "/vip" => "vip#index"                           # VIP购买页面
  post "/vip/purchase" => "vip#purchase"              # 购买VIP
  get "/vip/subscriptions" => "vip#user_subscriptions" # 用户订阅历史
  
  # VIP管理后台（管理员）
  get "/vip/admin" => "vip#admin"                     # 管理页面
  post "/vip/admin/packages" => "vip#create_package" # 创建套餐
  put "/vip/admin/packages/:id" => "vip#update_package" # 更新套餐
  delete "/vip/admin/packages/:id" => "vip#delete_package" # 删除套餐
  # VIP用户管理（管理员）
  get "/vip/admin/users" => "vip#admin_users"            # 分页获取VIP用户
  get "/vip/admin/usens" => "vip#admin_users"            # 兼容错误拼写
  put "/vip/admin/users/:user_id" => "vip#update_user_vip" # 更新指定用户的VIP
  delete "/vip/admin/users/:user_id" => "vip#cancel_user_vip" # 取消指定用户的VIP
  
  # 创作者申请系统
  get "/apply" => "creator#apply_page"                # 申请页面（非创作者用户）
  post "/apply/submit" => "creator#submit_application" # 提交申请
  get "/apply/status" => "creator#application_status" # 查询申请状态
  
  # 创作者中心
  get "/center" => "creator#index"                    # 作品墙（所有人可访问）
  get "/center/make" => "creator#make"                # 创作者操作页面（白名单用户）
  post "/center/create_work" => "creator#create_work" # 上传作品
  post "/center/like" => "creator#like_work"          # 点赞作品
  post "/center/click" => "creator#record_click"      # 记录点击
  post "/center/donate" => "creator#donate"           # 打赏作品
  delete "/center/delete_rejected_work" => "creator#delete_rejected_work" # 删除被驳回的作品
  post "/center/apply_shop" => "creator#apply_shop"   # 申请上架商品
  get "/center/work/:id" => "creator#work_detail"     # 作品详情数据API
  get "/center/zp/:id" => "creator#work_page"         # 作品详情页面（Ember引导）
  post "/center/toggle_like" => "creator#toggle_like" # 切换点赞状态
  
  # 创作者中心 - 管理后台（管理员）
  get "/center/admin" => "creator#admin"                              # 管理后台
  post "/center/admin/approve_work" => "creator#approve_work"         # 审核通过作品
  post "/center/admin/reject_work" => "creator#reject_work"           # 驳回作品
  post "/center/admin/update_work_status" => "creator#update_work_status"  # 更新已通过作品状态
  delete "/center/admin/delete_work" => "creator#delete_work"         # 删除作品
  post "/center/admin/update_shop_standards" => "creator#update_shop_standards"  # 更新上架标准
  post "/center/admin/update_commission_rate" => "creator#update_commission_rate"  # 更新抽成比例
  post "/center/admin/update_max_donations" => "creator#update_max_donations"  # 更新打赏次数限制
  post "/center/admin/approve_shop" => "creator#approve_shop"         # 审核通过上架申请
  post "/center/admin/reject_shop" => "creator#reject_shop"           # 驳回上架申请
  post "/center/admin/update_whitelist" => "creator#update_whitelist" # 更新白名单
  post "/center/admin/update_heat_config" => "creator#update_heat_config" # 更新热度颜色配置
  post "/center/admin/update_heat_rules" => "creator#update_heat_rules" # 更新热度规则
  post "/center/admin/recalculate_heat" => "creator#recalculate_heat" # 重新计算所有热度
  
  # 创作者申请审核（管理员）
  post "/center/admin/approve_application" => "creator#approve_application" # 通过申请
  post "/center/admin/reject_application" => "creator#reject_application"   # 拒绝申请
  
  # 创作者管理（管理员）
  post "/center/admin/revoke_creator" => "creator#revoke_creator"           # 撤销创作者资格

end
