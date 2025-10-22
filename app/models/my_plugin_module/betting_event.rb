# frozen_string_literal: true

module ::MyPluginModule
  class BettingEvent < ActiveRecord::Base
    self.table_name = "jifen_betting_events"

    belongs_to :creator, class_name: "User", foreign_key: :creator_id
    has_many :options, class_name: "MyPluginModule::BettingOption", foreign_key: :event_id, dependent: :destroy
    has_many :records, class_name: "MyPluginModule::BettingRecord", foreign_key: :event_id, dependent: :destroy

    # 事件类型
    TYPE_BET = "bet"    # 积分竞猜
    TYPE_VOTE = "vote"  # 普通投票

    # 事件状态
    STATUS_PENDING = "pending"     # 待开始
    STATUS_ACTIVE = "active"       # 进行中
    STATUS_FINISHED = "finished"   # 已结束
    STATUS_CANCELLED = "cancelled" # 已取消

    # 游戏分类
    CATEGORIES = ["lol", "dota2", "csgo", "valorant", "other"]

    validates :creator_id, presence: true
    validates :title, presence: true, length: { maximum: 255 }
    validates :event_type, presence: true, inclusion: { in: [TYPE_BET, TYPE_VOTE] }
    validates :status, presence: true, inclusion: { in: [STATUS_PENDING, STATUS_ACTIVE, STATUS_FINISHED, STATUS_CANCELLED] }
    validates :start_time, presence: true
    validates :end_time, presence: true
    validates :category, inclusion: { in: CATEGORIES }, allow_nil: true
    validate :end_time_after_start_time
    validate :min_bet_amount_valid

    scope :active, -> { where(status: STATUS_ACTIVE) }
    scope :finished, -> { where(status: STATUS_FINISHED) }
    scope :pending, -> { where(status: STATUS_PENDING) }
    scope :betting_type, -> { where(event_type: TYPE_BET) }
    scope :vote_type, -> { where(event_type: TYPE_VOTE) }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_start_time, -> { order(start_time: :desc) }

    # 是否是积分竞猜
    def is_betting?
      event_type == TYPE_BET
    end

    # 是否是普通投票
    def is_vote?
      event_type == TYPE_VOTE
    end

    # 是否已开始
    def started?
      Time.current >= start_time
    end

    # 是否已结束
    def ended?
      Time.current >= end_time
    end

    # 是否可以投注
    def bettable?
      status == STATUS_ACTIVE && started? && !ended?
    end

    # 是否可以结算
    def settleable?
      status == STATUS_FINISHED && winner_option_id.present? && settled_at.nil?
    end

    # 剩余时间（秒）
    def time_remaining
      return 0 if ended?
      (end_time - Time.current).to_i
    end

    # 获胜选项
    def winner_option
      return nil unless winner_option_id
      options.find_by(id: winner_option_id)
    end

    # 开始事件
    def activate!
      raise StandardError, "事件未到开始时间" unless started?
      raise StandardError, "事件已结束" if ended?
      
      update!(status: STATUS_ACTIVE)
    end

    # 结束事件
    def finish!
      update!(status: STATUS_FINISHED)
    end

    # 取消事件
    def cancel!
      update!(status: STATUS_CANCELLED)
    end

    # 设置获胜选项
    def set_winner!(option_id)
      raise StandardError, "事件未结束" unless status == STATUS_FINISHED
      raise StandardError, "选项不存在" unless options.exists?(id: option_id)
      
      update!(winner_option_id: option_id)
      
      # 更新选项的获胜状态
      options.update_all(is_winner: false)
      options.find(option_id).update!(is_winner: true)
    end

    private

    def end_time_after_start_time
      return if end_time.blank? || start_time.blank?
      
      if end_time <= start_time
        errors.add(:end_time, "结束时间必须晚于开始时间")
      end
    end

    def min_bet_amount_valid
      if is_betting? && min_bet_amount <= 0
        errors.add(:min_bet_amount, "积分竞猜必须设置最低投注额")
      end
    end
  end
end
