# frozen_string_literal: true

module ::MyPluginModule
  class DuelAdminController < ::ApplicationController
    requires_login
    
    before_action :ensure_admin
    before_action :ensure_duel_enabled

    # 获取所有决斗列表
    def index
      status_filter = params[:status]
      
      duels_query = MyPluginModule::Duel.includes(:challenger, :opponent, :winner, :admin).recent

      if status_filter.present?
        duels_query = duels_query.where(status: status_filter)
      end

      duels = duels_query.limit(100)

      render_json_dump({
        success: true,
        duels: duels.map { |d| admin_duel_data(d) }
      })
    rescue => e
      Rails.logger.error "[决斗管理] 获取列表失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("获取决斗列表失败", status: 500)
    end

    # 结算决斗
    def settle
      duel = MyPluginModule::Duel.find(params[:id])
      winner_id = params.require(:winner_id).to_i
      note = params[:note]

      ActiveRecord::Base.transaction do
        duel.settle!(winner_id, current_user.id, note: note)

        # 将赌注给获胜者（双倍）
        total_prize = duel.stake_amount * 2
        MyPluginModule::JifenService.adjust_points!(
          Discourse.system_user,
          duel.winner,
          total_prize
        )

        # 发送结算通知给双方
        send_settlement_notification(duel)

        # 记录日志
        Rails.logger.info "[决斗管理] 决斗 ##{duel.id} 已结算，获胜者: #{duel.winner.username}，奖金: #{total_prize}"

        render_json_dump({
          success: true,
          message: "决斗已结算，#{duel.winner.username} 获胜，获得 #{total_prize} 积分",
          duel: admin_duel_data(duel)
        })
      end
    rescue StandardError => e
      render_json_error(e.message, status: 422)
    rescue => e
      Rails.logger.error "[决斗管理] 结算失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("结算决斗失败", status: 500)
    end

    # 取消决斗（管理员审核失败）
    def cancel
      duel = MyPluginModule::Duel.find(params[:id])
      cancel_reason = params[:reason]

      unless duel.status == MyPluginModule::Duel::STATUS_ACCEPTED
        render_json_error("只能取消已接受状态的决斗", status: 422)
        return
      end

      ActiveRecord::Base.transaction do
        # 退还双方的赌注
        MyPluginModule::JifenService.adjust_points!(
          Discourse.system_user,
          duel.challenger,
          duel.stake_amount
        )
        MyPluginModule::JifenService.adjust_points!(
          Discourse.system_user,
          duel.opponent,
          duel.stake_amount
        )

        # 发送审核失败通知给双方
        send_cancel_notification(duel, cancel_reason)

        # 删除决斗
        duel.destroy!

        Rails.logger.info "[决斗管理] 管理员 #{current_user.username} 取消了决斗 ##{duel.id}，理由: #{cancel_reason}"

        render_json_dump({
          success: true,
          message: "决斗已取消，双方积分已退还"
        })
      end
    rescue ActiveRecord::RecordNotFound
      render_json_error("决斗不存在", status: 404)
    rescue => e
      Rails.logger.error "[决斗管理] 取消失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("取消决斗失败", status: 500)
    end

    # 删除决斗
    def destroy
      duel = MyPluginModule::Duel.find(params[:id])
      
      ActiveRecord::Base.transaction do
        # 根据状态退还积分
        case duel.status
        when MyPluginModule::Duel::STATUS_PENDING
          # 待接受状态：只退还发起者的赌注
          MyPluginModule::JifenService.adjust_points!(
            Discourse.system_user,
            duel.challenger,
            duel.stake_amount
          )
        when MyPluginModule::Duel::STATUS_ACCEPTED
          # 已接受状态：退还双方的赌注
          MyPluginModule::JifenService.adjust_points!(
            Discourse.system_user,
            duel.challenger,
            duel.stake_amount
          )
          MyPluginModule::JifenService.adjust_points!(
            Discourse.system_user,
            duel.opponent,
            duel.stake_amount
          )
        end
        # 已拒绝、已取消、已结算状态：不退还积分

        duel.destroy!

        Rails.logger.info "[决斗管理] 管理员 #{current_user.username} 删除了决斗 ##{duel.id}"

        render_json_dump({
          success: true,
          message: "决斗已删除"
        })
      end
    rescue ActiveRecord::RecordNotFound
      render_json_error("决斗不存在", status: 404)
    rescue => e
      Rails.logger.error "[决斗管理] 删除失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("删除决斗失败", status: 500)
    end

    private

    def ensure_admin
      unless current_user.admin?
        render_json_error("需要管理员权限", status: 403)
      end
    end

    def ensure_duel_enabled
      unless SiteSetting.jifen_duel_enabled
        render_json_error("决斗功能未启用", status: 403)
      end
    end

    def send_cancel_notification(duel, reason)
      # 发送审核失败通知给双方
      begin
        notification_title = "❌ 决斗已被管理员取消"
        notification_body = <<~BODY
          你参与的决斗已被管理员取消。

          **决斗主题：** #{duel.title}

          **赌注：** #{duel.stake_amount} 积分

          **取消理由：** #{reason.presence || '无'}

          ---

          你的 #{duel.stake_amount} 积分赌注已退还。
        BODY

        # 通知发起者
        PostCreator.create!(
          Discourse.system_user,
          title: notification_title,
          raw: notification_body,
          archetype: Archetype.private_message,
          target_usernames: duel.challenger.username,
          skip_validations: true
        )

        # 通知对手
        PostCreator.create!(
          Discourse.system_user,
          title: notification_title,
          raw: notification_body,
          archetype: Archetype.private_message,
          target_usernames: duel.opponent.username,
          skip_validations: true
        )

        Rails.logger.info "[决斗] 已发送取消通知给 #{duel.challenger.username} 和 #{duel.opponent.username}"
      rescue => e
        Rails.logger.error "[决斗] 发送取消通知失败: #{e.message}"
      end
    end

    def send_settlement_notification(duel)
      # 发送结算通知给获胜者和失败者
      begin
        total_prize = duel.stake_amount * 2
        
        # 通知获胜者
        winner_title = "🏆 决斗胜利！"
        winner_body = <<~BODY
          恭喜！你在决斗中获胜了！🎉

          **决斗主题：** #{duel.title}

          **对手：** #{duel.loser.username}

          **赌注：** #{duel.stake_amount} 积分

          **奖励：** #{total_prize} 积分 💰

          ---

          你获得了双倍赌注共 **#{total_prize} 积分**！

          #{duel.settlement_note.present? ? "**结算备注：** #{duel.settlement_note}" : ""}
        BODY

        PostCreator.create!(
          Discourse.system_user,
          title: winner_title,
          raw: winner_body,
          archetype: Archetype.private_message,
          target_usernames: duel.winner.username,
          skip_validations: true
        )

        # 通知失败者
        loser_title = "😔 决斗失败"
        loser_body = <<~BODY
          很遗憾，你在决斗中失败了。

          **决斗主题：** #{duel.title}

          **对手：** #{duel.winner.username}

          **赌注：** #{duel.stake_amount} 积分

          **损失：** #{duel.stake_amount} 积分

          ---

          你输掉了 #{duel.stake_amount} 积分的赌注。

          不要气馁，继续努力！💪

          #{duel.settlement_note.present? ? "**结算备注：** #{duel.settlement_note}" : ""}
        BODY

        PostCreator.create!(
          Discourse.system_user,
          title: loser_title,
          raw: loser_body,
          archetype: Archetype.private_message,
          target_usernames: duel.loser.username,
          skip_validations: true
        )

        Rails.logger.info "[决斗] 已发送结算通知给 #{duel.winner.username} 和 #{duel.loser.username}"
      rescue => e
        Rails.logger.error "[决斗] 发送结算通知失败: #{e.message}"
      end
    end

    def admin_duel_data(duel)
      {
        id: duel.id,
        challenger: {
          id: duel.challenger.id,
          username: duel.challenger.username,
          avatar_template: duel.challenger.avatar_template
        },
        opponent: {
          id: duel.opponent.id,
          username: duel.opponent.username,
          avatar_template: duel.opponent.avatar_template
        },
        title: duel.title,
        description: duel.description,
        stake_amount: duel.stake_amount,
        status: duel.status,
        winner: duel.winner ? {
          id: duel.winner.id,
          username: duel.winner.username
        } : nil,
        loser: duel.loser ? {
          id: duel.loser.id,
          username: duel.loser.username
        } : nil,
        admin: duel.admin ? {
          id: duel.admin.id,
          username: duel.admin.username
        } : nil,
        settlement_note: duel.settlement_note,
        settled_at: duel.settled_at&.strftime("%Y-%m-%d %H:%M"),
        created_at: duel.created_at.strftime("%Y-%m-%d %H:%M")
      }
    end
  end
end
