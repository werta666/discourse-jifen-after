# frozen_string_literal: true

module Jobs
  class MyPluginModule::ExpireDuelsJob < ::Jobs::Scheduled
    every 10.minutes  # 每10分钟检查一次

    def execute(args)
      return unless SiteSetting.jifen_duel_enabled

      expire_hours = SiteSetting.jifen_duel_expire_hours || 72
      expire_time = expire_hours.hours.ago

      # 查找所有过期的待接受决斗
      expired_duels = ::MyPluginModule::Duel
        .where(status: ::MyPluginModule::Duel::STATUS_PENDING)
        .where("created_at < ?", expire_time)

      expired_count = 0

      expired_duels.each do |duel|
        begin
          ActiveRecord::Base.transaction do
            # 拒绝决斗
            duel.reject!

            # 退还发起者的赌注
            ::MyPluginModule::JifenService.adjust_points!(
              Discourse.system_user,
              duel.challenger,
              duel.stake_amount
            )

            # 发送过期通知
            send_expire_notification(duel, expire_hours)

            expired_count += 1
            Rails.logger.info "[决斗] 决斗 ##{duel.id} 已自动拒绝（过期）"
          end
        rescue => e
          Rails.logger.error "[决斗] 自动拒绝决斗 ##{duel.id} 失败: #{e.message}"
        end
      end

      Rails.logger.info "[决斗] 自动拒绝过期决斗任务完成，处理了 #{expired_count} 个决斗" if expired_count > 0
    end

    private

    def send_expire_notification(duel, expire_hours)
      # 通知发起者决斗已过期
      begin
        notification_title = "⏰ 决斗申请已过期"
        notification_body = <<~BODY
          你的决斗申请因超时未接受已被自动拒绝。

          **决斗主题：** #{duel.title}

          **对手：** #{duel.opponent.username}

          **赌注：** #{duel.stake_amount} 积分

          **过期时间：** #{expire_hours} 小时

          ---

          你的 #{duel.stake_amount} 积分赌注已退还。

          你可以重新发起决斗挑战。
        BODY

        PostCreator.create!(
          Discourse.system_user,
          title: notification_title,
          raw: notification_body,
          archetype: Archetype.private_message,
          target_usernames: duel.challenger.username,
          skip_validations: true
        )

        Rails.logger.info "[决斗] 已向 #{duel.challenger.username} 发送过期通知"
      rescue => e
        Rails.logger.error "[决斗] 发送过期通知失败: #{e.message}"
      end
    end
  end
end
