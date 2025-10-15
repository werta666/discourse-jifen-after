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

  # 投票竞猜页面路由
  get "/tp" => "qd#tp"
  get "/tp_data" => "qd#tp_data"
  post "/tp_vote" => "qd#tp_vote"

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
end
