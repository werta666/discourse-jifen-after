# frozen_string_literal: true

module ::MyPluginModule
  class ApiController < ::ApplicationController
    requires_plugin MyPluginModule::PLUGIN_NAME

    before_action :ensure_logged_in

    # GET /qd/api/v1/balance.json?user_id=123 或 ?username=alice
    # 权限：
    # - 当前登录用户可查询自己
    # - 管理员可查询任意用户
    def balance
      user = find_user_by_param!
      unless current_user.admin? || current_user.id == user.id
        raise Discourse::InvalidAccess.new
      end

      available = MyPluginModule::JifenService.available_total_points(user)
      total_signed = MyPluginModule::JifenService.total_points(user.id)
      render_json_dump(
        user_id: user.id,
        username: user.username,
        available_points: available,
        total_signed_points: total_signed
      )
    rescue Discourse::NotFound
      render_json_error("用户不存在", status: 404)
    rescue Discourse::InvalidAccess
      render_json_error("无权限执行此操作", status: 403)
    rescue => e
      render_json_error(e.message)
    end

    # POST /qd/api/v1/adjust_points.json
    # 参数：
    # - username: 目标用户名（必填，或支持 user_id）
    # - delta: 整数，正数加分，负数减分（必填）
    # 权限：仅管理员
    def adjust_points
      raise Discourse::InvalidAccess.new unless current_user.admin?

      user = params[:user_id].present? ? User.find_by(id: params[:user_id].to_i) : User.find_by_username(params[:username].to_s)
      raise Discourse::NotFound unless user

      delta = params.require(:delta).to_i

      # 委托服务层以保证审计与风控逻辑
      summary = MyPluginModule::JifenService.adjust_points!(current_user, user, delta)

      # 为便于集成，附加调整前后对比
      render_json_dump(
        ok: true,
        target_user_id: user.id,
        target_username: user.username,
        delta: delta,
        after_available: summary[:total_score],
        message: "已调整 #{user.username} 的可用积分：变化 #{delta} 分"
      )
    rescue ActionController::ParameterMissing
      render_json_error("参数缺失：delta", status: 400)
    rescue Discourse::NotFound
      render_json_error("用户不存在", status: 404)
    rescue Discourse::InvalidAccess
      render_json_error("无权限执行此操作", status: 403)
    rescue => e
      render_json_error(e.message)
    end

    private

    def find_user_by_param!
      if params[:user_id].present?
        u = User.find_by(id: params[:user_id].to_i)
        raise Discourse::NotFound unless u
        return u
      end
      if params[:username].present?
        u = User.find_by_username(params[:username].to_s)
        raise Discourse::NotFound unless u
        return u
      end
      raise ActionController::ParameterMissing, "user_id/username"
    end
  end
end