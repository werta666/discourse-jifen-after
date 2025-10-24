# frozen_string_literal: true

module ::MyPluginModule
  module PaidCoinService
    module_function

    # 用户自定义字段键名
    PAID_COINS_FIELD = "paid_coins"           # 付费币总余额
    PAID_COINS_SPENT_FIELD = "paid_coins_spent"  # 已消费的付费币

    # ========== 核心查询方法 ==========

    # 获取用户付费币总余额（充值总额）
    def total_coins(user)
      (user.custom_fields[PAID_COINS_FIELD].presence || 0).to_i
    end

    # 获取用户已消费的付费币
    def spent_coins(user)
      (user.custom_fields[PAID_COINS_SPENT_FIELD].presence || 0).to_i
    end

    # 获取用户当前可用付费币余额
    def available_coins(user)
      total_coins(user) - spent_coins(user)
    end

    # 检查用户是否有足够的付费币
    def has_enough_coins?(user, amount)
      available_coins(user) >= amount.to_i
    end

    # ========== 付费币操作方法 ==========

    # 增加付费币（充值）
    # @param user [User] 目标用户
    # @param amount [Integer] 增加的付费币数量（必须>0）
    # @param reason [String] 增加原因（日志记录）
    # @param related_id [Integer] 关联ID（如订单ID）
    # @param related_type [String] 关联类型（如 "PaymentOrder"）
    # @return [Hash] 返回操作后的余额信息
    def add_coins!(user, amount, reason: "充值", related_id: nil, related_type: nil)
      amount = amount.to_i
      raise StandardError, "充值数量必须大于0" if amount <= 0

      before_total = total_coins(user)
      before_available = available_coins(user)

      # 增加付费币总额
      new_total = before_total + amount
      user.custom_fields[PAID_COINS_FIELD] = new_total
      user.save_custom_fields(true)

      after_available = available_coins(user)

      Rails.logger.info "[付费币] 用户 #{user.username} 增加 #{amount} 付费币，原因: #{reason}，余额: #{before_available} -> #{after_available}"

      # 创建充值记录
      begin
        MyPluginModule::PaidCoinRecord.create_recharge!(
          user: user,
          amount: amount,
          reason: reason,
          related_id: related_id,
          related_type: related_type
        )
      rescue => e
        Rails.logger.warn "[付费币] 创建充值记录失败: #{e.message}"
      end

      {
        user_id: user.id,
        username: user.username,
        amount: amount,
        reason: reason,
        before_total: before_total,
        after_total: new_total,
        before_available: before_available,
        after_available: after_available
      }
    end

    # 扣除付费币（消费）
    # @param user [User] 目标用户
    # @param amount [Integer] 扣除的付费币数量（必须>0）
    # @param reason [String] 扣除原因（日志记录）
    # @param related_id [Integer] 关联ID（如订单ID）
    # @param related_type [String] 关联类型（如 "ShopOrder"）
    # @return [Hash] 返回操作后的余额信息
    def deduct_coins!(user, amount, reason: "消费", related_id: nil, related_type: nil)
      amount = amount.to_i
      raise StandardError, "扣除数量必须大于0" if amount <= 0

      before_spent = spent_coins(user)
      before_available = available_coins(user)

      # 检查余额是否足够
      raise StandardError, "付费币余额不足（当前: #{before_available}，需要: #{amount}）" unless has_enough_coins?(user, amount)

      # 增加已消费金额
      new_spent = before_spent + amount
      user.custom_fields[PAID_COINS_SPENT_FIELD] = new_spent
      user.save_custom_fields(true)

      after_available = available_coins(user)

      Rails.logger.info "[付费币] 用户 #{user.username} 扣除 #{amount} 付费币，原因: #{reason}，余额: #{before_available} -> #{after_available}"

      # 创建消费记录
      begin
        MyPluginModule::PaidCoinRecord.create_consume!(
          user: user,
          amount: amount,
          reason: reason,
          related_id: related_id,
          related_type: related_type
        )
      rescue => e
        Rails.logger.warn "[付费币] 创建消费记录失败: #{e.message}"
      end

      {
        user_id: user.id,
        username: user.username,
        amount: amount,
        reason: reason,
        before_spent: before_spent,
        after_spent: new_spent,
        before_available: before_available,
        after_available: after_available
      }
    end

    # 管理员调整付费币（可增可减）
    # @param acting_user [User] 操作者（管理员）
    # @param target_user [User] 目标用户
    # @param delta [Integer] 调整值（>0增加，<0减少）
    # @return [Hash] 返回操作后的余额信息
    def adjust_coins!(acting_user, target_user, delta)
      delta = delta.to_i
      raise StandardError, "调整值不能为0" if delta == 0

      before_spent = spent_coins(target_user)
      before_available = available_coins(target_user)

      # 通过调整 spent 来实现增减
      new_spent = before_spent - delta
      
      # 确保 spent 不为负数
      new_spent = 0 if new_spent < 0

      target_user.custom_fields[PAID_COINS_SPENT_FIELD] = new_spent
      target_user.save_custom_fields(true)

      after_available = available_coins(target_user)

      begin
        StaffActionLogger.new(acting_user).log_custom(
          "paid_coin_adjust",
          target_user_id: target_user.id,
          target_username: target_user.username,
          delta: delta,
          before_spent: before_spent,
          after_spent: new_spent,
          before_available: before_available,
          after_available: after_available
        )
      rescue StandardError => e
        Rails.logger.warn "[付费币] 记录管理员操作日志失败: #{e.message}"
      end

      Rails.logger.info "[付费币] 管理员 #{acting_user.username} 调整用户 #{target_user.username} 付费币 #{delta > 0 ? '+' : ''}#{delta}，余额: #{before_available} -> #{after_available}"

      {
        user_id: target_user.id,
        username: target_user.username,
        delta: delta,
        before_available: before_available,
        after_available: after_available,
        operator: acting_user.username
      }
    end

    # 重置用户付费币（清零，管理员功能）
    def reset_coins!(acting_user, target_user)
      before_total = total_coins(target_user)
      before_spent = spent_coins(target_user)
      before_available = available_coins(target_user)

      target_user.custom_fields[PAID_COINS_FIELD] = 0
      target_user.custom_fields[PAID_COINS_SPENT_FIELD] = 0
      target_user.save_custom_fields(true)

      Rails.logger.warn "[付费币] 管理员 #{acting_user.username} 重置用户 #{target_user.username} 的付费币（原余额: #{before_available}）"

      {
        user_id: target_user.id,
        username: target_user.username,
        before_total: before_total,
        before_spent: before_spent,
        before_available: before_available,
        after_available: 0,
        operator: acting_user.username
      }
    end

    # ========== 批量查询方法 ==========

    # 获取用户付费币概览
    def summary_for(user)
      {
        user_id: user.id,
        username: user.username,
        total_coins: total_coins(user),
        spent_coins: spent_coins(user),
        available_coins: available_coins(user)
      }
    end

    # 批量获取多个用户的付费币余额（用于排行榜等）
    def batch_available_coins(user_ids)
      return {} if user_ids.blank?

      # 查询所有用户的自定义字段
      total_fields = UserCustomField.where(
        user_id: user_ids,
        name: PAID_COINS_FIELD
      ).pluck(:user_id, :value).to_h

      spent_fields = UserCustomField.where(
        user_id: user_ids,
        name: PAID_COINS_SPENT_FIELD
      ).pluck(:user_id, :value).to_h

      # 计算可用余额
      user_ids.each_with_object({}) do |user_id, hash|
        total = (total_fields[user_id].presence || 0).to_i
        spent = (spent_fields[user_id].presence || 0).to_i
        hash[user_id] = total - spent
      end
    end
  end
end
