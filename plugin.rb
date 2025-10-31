# frozen_string_literal: true

# name: discourse-jifen-after
# about: 多样化的社区功能合集-[签到/经济/商城/装扮/竞猜/决斗/会员/创作者/排行榜/充值等]
# version: 1.0.0
# authors: Pandacc
# url: https://github.com/werta666/discourse-jifen-after
# required_version: 2.7.0

# 站点设置开关（仅中文）
enabled_site_setting :jifen_enabled

# 注册样式表（qd 页面样式）
register_asset "stylesheets/fontawesome.scss"
register_asset "stylesheets/qd-plugin.scss"
register_asset "stylesheets/qd-board.scss"
register_asset "stylesheets/qd-board-neo.scss"
register_asset "stylesheets/qd-board-mario.scss"
register_asset "stylesheets/qd-board-minecraft.scss"
register_asset "stylesheets/qd-betting.scss"
register_asset "stylesheets/qd-betting-my-records.scss"
register_asset "stylesheets/qd-betting-admin.scss"
register_asset "stylesheets/qd-shop.scss"
register_asset "stylesheets/qd-shop-tabs.scss"
register_asset "stylesheets/qd-shop-orders.scss"
register_asset "stylesheets/qd-shop-admin-orders.scss"
register_asset "stylesheets/qd-pay-modern.scss"
register_asset "stylesheets/qd-pay-admin.scss"
register_asset "stylesheets/qd-dress-admin.scss"
register_asset "stylesheets/qd-dress.scss"
register_asset "stylesheets/qd-vip.scss"
register_asset "stylesheets/qd-vip-admin.scss"
register_asset "stylesheets/qd-center.scss"
register_asset "stylesheets/qd-apply.scss"
register_asset "stylesheets/qd-center-work.scss"

# 插件命名空间（沿用现有 MyPluginModule 以避免大规模重命名）
module ::MyPluginModule
  PLUGIN_NAME = "discourse-jifen-after"
end

# 加载 Rails Engine
require_relative "lib/my_plugin_module/engine"

# 在 Rails 初始化完成后挂载 Engine，路径为 /qd
after_initialize do
  # 加载用户序列化器扩展（让前端可以访问头像框和勋章数据）
  require_relative "app/serializers/user_serializer_extension"
  
  Discourse::Application.routes.append do
    mount ::MyPluginModule::Engine, at: "/qd"
  end

  # 延迟加载后台任务，避免启动时的常量问题
  Rails.application.config.to_prepare do
    if SiteSetting.jifen_enabled
      # 初始化排行榜缓存
      begin
        MyPluginModule::JifenService.get_leaderboard(limit: 5)
      rescue => e
        Rails.logger.warn "[积分插件] 初始化排行榜缓存失败: #{e.message}"
      end
    end
  end

  # 监听设置变更，动态调整后台任务间隔
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
end
