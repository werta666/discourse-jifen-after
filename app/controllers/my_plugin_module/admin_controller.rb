# frozen_string_literal: true

module ::MyPluginModule
  class AdminController < ::ApplicationController
    requires_plugin MyPluginModule::PLUGIN_NAME
    before_action :ensure_admin

    # 管理员触发的同步任务占位（保留）
    def sync
      render_json_dump(ok: true, message: "已触发同步（占位）")
    end

    # 手动调整指定用户的插件积分（可增可减）
    # 参数：username, delta
    def adjust_points
      username = params.require(:username).to_s
      delta = params.require(:delta).to_i
      target = find_user!(username)

      before_available = MyPluginModule::JifenService.available_total_points(target)
      summary = MyPluginModule::JifenService.adjust_points!(current_user, target, delta)
      after_available = summary[:total_score]

      render_json_dump(
        ok: true,
        target_username: target.username,
        delta: delta,
        before_available: before_available,
        after_available: after_available
      )
    rescue StandardError => e
      render_json_error(e.message)
    end

    # 重置指定用户"今日签到"状态，使其可重新签到
    # 参数：username
    def reset_today
      username = params.require(:username).to_s
      target = find_user!(username)
      removed = MyPluginModule::JifenService.reset_today!(current_user, target)

      render_json_dump(ok: true, target_username: target.username, removed: removed)
    rescue StandardError => e
      render_json_error(e.message)
    end



    private

    def find_user!(username)
      u = User.find_by(username_lower: username.downcase)
      raise Discourse::NotFound, "用户不存在" unless u
      u
    end


  end
end