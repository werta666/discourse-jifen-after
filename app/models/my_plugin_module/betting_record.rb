# frozen_string_literal: true

module ::MyPluginModule
  class BettingRecord < ActiveRecord::Base
    self.table_name = "jifen_betting_records"

    belongs_to :user
    belongs_to :event, class_name: "MyPluginModule::BettingEvent", foreign_key: :event_id
    belongs_to :option, class_name: "MyPluginModule::BettingOption", foreign_key: :option_id

    # 记录状态
    STATUS_PENDING = "pending"   # 待结算
    STATUS_WON = "won"           # 赢
    STATUS_LOST = "lost"         # 输
    STATUS_REFUNDED = "refunded" # 退款

    validates :user_id, presence: true
    validates :event_id, presence: true
    validates :option_id, presence: true
    validates :bet_amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :status, presence: true, inclusion: { in: [STATUS_PENDING, STATUS_WON, STATUS_LOST, STATUS_REFUNDED] }
    validates :user_id, uniqueness: { scope: :event_id, message: "每个事件只能投注一次" }
    
    # 自定义验证：积分竞猜必须有投注金额
    validate :bet_amount_required_for_betting

    scope :pending, -> { where(status: STATUS_PENDING) }
    scope :won, -> { where(status: STATUS_WON) }
    scope :lost, -> { where(status: STATUS_LOST) }
    scope :refunded, -> { where(status: STATUS_REFUNDED) }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_event, ->(event_id) { where(event_id: event_id) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }

    # 是否赢了
    def won?
      status == STATUS_WON
    end

    # 是否输了
    def lost?
      status == STATUS_LOST
    end

    # 预期收益
    def potential_win
      return 0 unless odds_at_bet
      (bet_amount * odds_at_bet).to_i
    end

    # 实际收益（已结算）
    def actual_win
      won? ? win_amount : 0
    end

    # 净收益
    def net_profit
      actual_win - bet_amount
    end

    # 标记为赢
    def mark_as_won!(amount)
      update!(
        status: STATUS_WON,
        win_amount: amount,
        settled_at: Time.current
      )
    end

    # 标记为输
    def mark_as_lost!
      update!(
        status: STATUS_LOST,
        win_amount: 0,
        settled_at: Time.current
      )
    end

    # 退款
    def refund!
      update!(
        status: STATUS_REFUNDED,
        win_amount: bet_amount,
        settled_at: Time.current
      )
    end

    private

    # 验证积分竞猜必须有投注金额
    def bet_amount_required_for_betting
      return unless event
      
      if event.is_betting? && bet_amount <= 0
        errors.add(:bet_amount, "积分竞猜必须大于0")
      end
    end
  end
end
