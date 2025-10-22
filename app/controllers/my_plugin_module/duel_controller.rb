# frozen_string_literal: true

module ::MyPluginModule
  class DuelController < ::ApplicationController
    requires_login
    
    before_action :ensure_duel_enabled

    # 发起决斗
    def create_duel
      opponent_username = params.require(:opponent_username)
      title = params.require(:title)
      description = params[:description]
      stake_amount = params.require(:stake_amount).to_i

      # 检查冷却时间
      cooldown_minutes = SiteSetting.jifen_duel_cooldown_minutes || 60
      if cooldown_minutes > 0
        last_duel_time = current_user.custom_fields["jifen_last_duel_time"]
        if last_duel_time.present?
          last_time = Time.parse(last_duel_time) rescue nil
          if last_time && (Time.now - last_time) < (cooldown_minutes * 60)
            remaining_minutes = ((cooldown_minutes * 60 - (Time.now - last_time)) / 60).ceil
            render_json_error("发起决斗冷却中，请等待 #{remaining_minutes} 分钟后再试", status: 422)
            return
          end
        end
      end

      # 查找对手
      opponent = User.find_by(username: opponent_username)
      unless opponent
        render_json_error("找不到用户：#{opponent_username}", status: 404)
        return
      end

      # 验证不能向自己决斗
      if opponent.id == current_user.id
        render_json_error("不能向自己发起决斗", status: 422)
        return
      end

      # 获取发起决斗费用
      creation_cost = SiteSetting.jifen_duel_creation_cost || 0
      
      # 验证积分是否足够（发起费用 + 赌注）
      total_required = creation_cost + stake_amount
      available = MyPluginModule::JifenService.available_total_points(current_user)
      
      if available < total_required
        render_json_error("积分不足。需要 #{total_required} 积分（发起费用 #{creation_cost} + 赌注 #{stake_amount}），当前可用 #{available}", status: 422)
        return
      end

      ActiveRecord::Base.transaction do
        # 扣除发起费用
        if creation_cost > 0
          MyPluginModule::JifenService.adjust_points!(
            current_user,
            current_user,
            -creation_cost
          )
        end

        # 锁定赌注积分（先扣除）
        MyPluginModule::JifenService.adjust_points!(
          current_user,
          current_user,
          -stake_amount
        )

        # 创建决斗
        duel = MyPluginModule::Duel.create!(
          challenger_id: current_user.id,
          opponent_id: opponent.id,
          title: title,
          description: description,
          stake_amount: stake_amount,
          status: MyPluginModule::Duel::STATUS_PENDING
        )

        # 更新冷却时间
        current_user.custom_fields["jifen_last_duel_time"] = Time.now.iso8601
        current_user.save_custom_fields(true)

        # 发送通知给对手
        send_duel_notification(duel, opponent)

        render_json_dump({
          success: true,
          message: "决斗邀请已发送",
          duel: duel_data(duel)
        })
      end
    rescue ActiveRecord::RecordInvalid => e
      render_json_error(e.record.errors.full_messages.join(", "), status: 422)
    rescue => e
      Rails.logger.error "[决斗] 创建失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("创建决斗失败: #{e.message}", status: 500)
    end

    # 接受决斗
    def accept_duel
      duel = MyPluginModule::Duel.find(params[:id])

      # 验证是否为对手
      unless duel.opponent_id == current_user.id
        render_json_error("无权操作", status: 403)
        return
      end

      # 验证积分是否足够
      available = MyPluginModule::JifenService.available_total_points(current_user)
      if available < duel.stake_amount
        render_json_error("积分不足。需要 #{duel.stake_amount}，当前可用 #{available}", status: 422)
        return
      end

      ActiveRecord::Base.transaction do
        # 锁定对手的赌注积分
        MyPluginModule::JifenService.adjust_points!(
          current_user,
          current_user,
          -duel.stake_amount
        )

        duel.accept!

        render_json_dump({
          success: true,
          message: "已接受决斗",
          duel: duel_data(duel)
        })
      end
    rescue StandardError => e
      render_json_error(e.message, status: 422)
    rescue => e
      Rails.logger.error "[决斗] 接受失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("接受决斗失败", status: 500)
    end

    # 拒绝决斗
    def reject_duel
      duel = MyPluginModule::Duel.find(params[:id])

      # 验证是否为对手
      unless duel.opponent_id == current_user.id
        render_json_error("无权操作", status: 403)
        return
      end

      ActiveRecord::Base.transaction do
        duel.reject!

        # 退还发起者的赌注
        MyPluginModule::JifenService.adjust_points!(
          Discourse.system_user,
          duel.challenger,
          duel.stake_amount
        )

        # 通知发起者决斗被拒绝
        send_reject_notification(duel, current_user)

        render_json_dump({
          success: true,
          message: "已拒绝决斗"
        })
      end
    rescue StandardError => e
      render_json_error(e.message, status: 422)
    rescue => e
      Rails.logger.error "[决斗] 拒绝失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("拒绝决斗失败", status: 500)
    end

    # 取消决斗（发起者）
    def cancel_duel
      duel = MyPluginModule::Duel.find(params[:id])

      # 验证是否为发起者
      unless duel.challenger_id == current_user.id
        render_json_error("无权操作", status: 403)
        return
      end

      ActiveRecord::Base.transaction do
        duel.cancel!

        # 退还赌注
        MyPluginModule::JifenService.adjust_points!(
          Discourse.system_user,
          current_user,
          duel.stake_amount
        )

        render_json_dump({
          success: true,
          message: "已取消决斗"
        })
      end
    rescue StandardError => e
      render_json_error(e.message, status: 422)
    rescue => e
      Rails.logger.error "[决斗] 取消失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("取消决斗失败", status: 500)
    end

    # 我的决斗列表
    def my_duels
      duels = MyPluginModule::Duel
        .where("challenger_id = ? OR opponent_id = ?", current_user.id, current_user.id)
        .recent
        .limit(50)

      render_json_dump({
        success: true,
        duels: duels.map { |d| duel_data(d) }
      })
    rescue => e
      Rails.logger.error "[决斗] 获取列表失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("获取决斗列表失败", status: 500)
    end

    # 待处理的决斗（对手视角）
    def pending_duels
      duels = MyPluginModule::Duel
        .where(opponent_id: current_user.id, status: MyPluginModule::Duel::STATUS_PENDING)
        .recent

      render_json_dump({
        success: true,
        duels: duels.map { |d| duel_data(d) }
      })
    rescue => e
      Rails.logger.error "[决斗] 获取待处理失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("获取待处理决斗失败", status: 500)
    end

    # 正在进行的决斗（已接受状态）
    def active_duels
      duels = MyPluginModule::Duel
        .where("(challenger_id = ? OR opponent_id = ?) AND status = ?", 
               current_user.id, current_user.id, MyPluginModule::Duel::STATUS_ACCEPTED)
        .recent

      render_json_dump({
        success: true,
        duels: duels.map { |d| duel_data(d) }
      })
    rescue => e
      Rails.logger.error "[决斗] 获取进行中决斗失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("获取进行中决斗失败", status: 500)
    end

    private

    def ensure_duel_enabled
      unless SiteSetting.jifen_duel_enabled
        render_json_error("决斗功能未启用", status: 403)
      end
    end

    def send_duel_notification(duel, opponent)
      # 创建系统通知
      begin
        # 通知标题和内容
        notification_title = "⚔️ #{duel.challenger.username} 向你发起了决斗挑战"
        notification_body = <<~BODY
          **决斗主题：** #{duel.title}

          **赌注：** #{duel.stake_amount} 积分

          **达成条件：**
          #{duel.description.presence || '待定'}

          ---

          请前往 [竞猜管理中心](/qd/betting) 查看详情并接受或拒绝决斗。

          _注意：接受决斗需要锁定 #{duel.stake_amount} 积分作为赌注。_
        BODY

        # 使用Discourse的PostCreator创建私信
        PostCreator.create!(
          Discourse.system_user,
          title: notification_title,
          raw: notification_body,
          archetype: Archetype.private_message,
          target_usernames: opponent.username,
          skip_validations: true
        )

        Rails.logger.info "[决斗] 已向 #{opponent.username} 发送决斗通知"
      rescue => e
        Rails.logger.error "[决斗] 发送通知失败: #{e.message}"
        # 不抛出异常，允许决斗创建继续
      end
    end

    def send_reject_notification(duel, rejector)
      # 通知发起者决斗被拒绝
      begin
        notification_title = "❌ 决斗挑战被拒绝"
        notification_body = <<~BODY
          很遗憾，**#{rejector.username}** 拒绝了你的决斗挑战。

          **决斗主题：** #{duel.title}

          **赌注：** #{duel.stake_amount} 积分

          ---

          你的 #{duel.stake_amount} 积分赌注已退还。

          你可以继续向其他用户发起决斗挑战。💪
        BODY

        PostCreator.create!(
          Discourse.system_user,
          title: notification_title,
          raw: notification_body,
          archetype: Archetype.private_message,
          target_usernames: duel.challenger.username,
          skip_validations: true
        )

        Rails.logger.info "[决斗] 已向 #{duel.challenger.username} 发送拒绝通知"
      rescue => e
        Rails.logger.error "[决斗] 发送拒绝通知失败: #{e.message}"
      end
    end

    def duel_data(duel)
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
        winner_id: duel.winner_id,
        settled_at: duel.settled_at&.iso8601,
        created_at: duel.created_at.iso8601
      }
    end
  end
end
