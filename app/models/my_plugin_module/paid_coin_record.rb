# frozen_string_literal: true

module ::MyPluginModule
  class PaidCoinRecord < ActiveRecord::Base
    self.table_name = "jifen_paid_coin_records"

    belongs_to :user

    # 操作类型常量
    TYPE_RECHARGE = "recharge"   # 充值
    TYPE_CONSUME = "consume"     # 消费
    TYPE_ADJUST = "adjust"       # 管理员调整
    TYPE_REFUND = "refund"       # 退款

    validates :user_id, presence: true
    validates :amount, presence: true, numericality: { other_than: 0 }
    validates :action_type, presence: true, inclusion: { in: [TYPE_RECHARGE, TYPE_CONSUME, TYPE_ADJUST, TYPE_REFUND] }
    validates :reason, presence: true
    validates :balance_after, presence: true, numericality: { greater_than_or_equal_to: 0 }

    scope :recent, -> { order(created_at: :desc) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :recharges, -> { where(action_type: TYPE_RECHARGE) }
    scope :consumes, -> { where(action_type: TYPE_CONSUME) }

    # 创建充值记录
    def self.create_recharge!(user:, amount:, reason:, related_id: nil, related_type: nil)
      balance_after = MyPluginModule::PaidCoinService.available_coins(user)
      
      create!(
        user_id: user.id,
        amount: amount,
        action_type: TYPE_RECHARGE,
        reason: reason,
        related_id: related_id,
        related_type: related_type,
        balance_after: balance_after
      )
    end

    # 创建消费记录
    def self.create_consume!(user:, amount:, reason:, related_id: nil, related_type: nil)
      balance_after = MyPluginModule::PaidCoinService.available_coins(user)
      
      create!(
        user_id: user.id,
        amount: -amount.abs,  # 消费记录为负数
        action_type: TYPE_CONSUME,
        reason: reason,
        related_id: related_id,
        related_type: related_type,
        balance_after: balance_after
      )
    end

    # 创建调整记录
    def self.create_adjust!(user:, amount:, reason:)
      balance_after = MyPluginModule::PaidCoinService.available_coins(user)
      
      create!(
        user_id: user.id,
        amount: amount,
        action_type: TYPE_ADJUST,
        reason: reason,
        balance_after: balance_after
      )
    end

    # 创建退款记录
    def self.create_refund!(user:, amount:, reason:, related_id: nil, related_type: nil)
      balance_after = MyPluginModule::PaidCoinService.available_coins(user)
      
      create!(
        user_id: user.id,
        amount: amount,
        action_type: TYPE_REFUND,
        reason: reason,
        related_id: related_id,
        related_type: related_type,
        balance_after: balance_after
      )
    end
  end
end
