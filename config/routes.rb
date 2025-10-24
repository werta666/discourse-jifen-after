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
  
  # 商店管理路由
  post "/shop/add_product" => "shop#add_product"
  post "/shop/create_sample" => "shop#create_sample"
  delete "/shop/products/:id" => "shop#delete_product"
  put "/shop/products/:id" => "shop#update_product"
  
  # 管理员订单管理路由
  get "/shop/admin/orders" => "shop#admin_orders"
  patch "/shop/admin/orders/:id/status" => "shop#update_order_status"
  delete "/shop/admin/orders/:id" => "shop#delete_order"

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
end
