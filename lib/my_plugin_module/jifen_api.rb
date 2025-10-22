# frozen_string_literal: true

# discourse-jifen-after 插件对外的内部 Ruby API（插件间调用，首选）
# 用途：
# - 供同一 Discourse 实例内的其他插件直接调用
# - 无需 HTTP/管理员权限，复用本插件的事务、风控与审计
#
# 约定：
# - actor_id 可选；缺省时使用 Discourse.system_user 作为操作人（审计可见）
# - delta 为整数（正数加分，负数减分）
# - 如需更多能力（补签、最近记录等），建议直接使用 summary_for 或扩展本门面
#
# 返回：
# - 与服务层一致的 Ruby Hash（仅中文字段），便于直接渲染或序列化
#
module ::MyPluginModule
  module JifenAPI
    API_VERSION = "1.0".freeze

    # 获取用户完整概览（结构与 /qd/summary.json 一致）
    # @param user_id [Integer]
    # @return [Hash]
    def self.summary_for(user_id:)
      user = User.find_by(id: user_id)
      raise Discourse::NotFound unless user
      ::MyPluginModule::JifenService.summary_for(user)
    end

    # 获取用户可用积分（available = 累计签到所得 - 已消费）
    # @param user_id [Integer]
    # @return [Integer]
    def self.available_points_for(user_id:)
      user = User.find_by(id: user_id)
      raise Discourse::NotFound unless user
      ::MyPluginModule::JifenService.available_total_points(user)
    end

    # 调整用户可用积分（加/减），内部自动记录审计
    # @param target_user_id [Integer] 目标用户
    # @param delta [Integer] 正数加分，负数减分
    # @param actor_id [Integer, nil] 作为操作者记录到审计日志；缺省采用系统用户
    # @param reason [String] 业务原因标记，默认 "plugin_adjust"
    # @param plugin [String, nil] 调用方插件名，用于审计说明
    # @return [Hash] 最新 summary（含 total_score 可用积分等）
    def self.adjust_points!(target_user_id:, delta:, actor_id: nil, reason: "plugin_adjust", plugin: nil)
      target = User.find_by(id: target_user_id)
      raise Discourse::NotFound unless target

      actor = actor_id ? User.find_by(id: actor_id) : Discourse.system_user
      actor ||= Discourse.system_user

      summary = ::MyPluginModule::JifenService.adjust_points!(actor, target, delta.to_i)

      # 附加一条插件维度的审计记录，便于区分来源
      begin
        StaffActionLogger.new(actor).log_custom(
          "jifen_adjust_points_plugin",
          target_user_id: target.id,
          target_username: target.username,
          delta: delta.to_i,
          plugin: (plugin || "unknown_plugin"),
          reason: reason
        )
      rescue StandardError
        # 忽略日志异常
      end

      summary
    end
  end
end