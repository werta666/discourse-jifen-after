# frozen_string_literal: true

module ::MyPluginModule
  class Duel < ActiveRecord::Base
    self.table_name = 'jifen_duels'

    # 状态常量
    STATUS_PENDING = 'pending'      # 待接受
    STATUS_ACCEPTED = 'accepted'    # 已接受
    STATUS_REJECTED = 'rejected'    # 已拒绝
    STATUS_SETTLED = 'settled'      # 已结算
    STATUS_CANCELLED = 'cancelled'  # 已取消

    # 关联
    belongs_to :challenger, class_name: 'User', foreign_key: 'challenger_id'
    belongs_to :opponent, class_name: 'User', foreign_key: 'opponent_id'
    belongs_to :winner, class_name: 'User', foreign_key: 'winner_id', optional: true
    belongs_to :admin, class_name: 'User', foreign_key: 'admin_id', optional: true

    # 验证
    validates :challenger_id, presence: true
    validates :opponent_id, presence: true
    validates :title, presence: true, length: { minimum: 5, maximum: 200 }
    validates :stake_amount, presence: true, numericality: { greater_than: 0 }
    validates :status, presence: true, inclusion: { in: [STATUS_PENDING, STATUS_ACCEPTED, STATUS_REJECTED, STATUS_SETTLED, STATUS_CANCELLED] }
    validate :cannot_duel_self

    # 作用域
    scope :pending, -> { where(status: STATUS_PENDING) }
    scope :accepted, -> { where(status: STATUS_ACCEPTED) }
    scope :rejected, -> { where(status: STATUS_REJECTED) }
    scope :settled, -> { where(status: STATUS_SETTLED) }
    scope :cancelled, -> { where(status: STATUS_CANCELLED) }
    scope :recent, -> { order(created_at: :desc) }
    scope :active, -> { where(status: [STATUS_PENDING, STATUS_ACCEPTED]) }

    # 接受决斗
    def accept!
      raise StandardError, "只有待接受的决斗可以接受" unless status == STATUS_PENDING
      update!(status: STATUS_ACCEPTED)
    end

    # 拒绝决斗
    def reject!
      raise StandardError, "只有待接受的决斗可以拒绝" unless status == STATUS_PENDING
      update!(status: STATUS_REJECTED)
    end

    # 取消决斗
    def cancel!
      raise StandardError, "只有待接受的决斗可以取消" unless status == STATUS_PENDING
      update!(status: STATUS_CANCELLED)
    end

    # 结算决斗
    def settle!(winner_id, admin_id, note: nil)
      raise StandardError, "只有已接受的决斗可以结算" unless status == STATUS_ACCEPTED
      raise StandardError, "获胜者必须是决斗双方之一" unless [challenger_id, opponent_id].include?(winner_id)

      update!(
        status: STATUS_SETTLED,
        winner_id: winner_id,
        admin_id: admin_id,
        settled_at: Time.current,
        settlement_note: note
      )
    end

    # 获取失败者
    def loser
      return nil unless winner_id
      winner_id == challenger_id ? opponent : challenger
    end

    # 获取失败者ID
    def loser_id
      return nil unless winner_id
      winner_id == challenger_id ? opponent_id : challenger_id
    end

    # 检查用户是否参与此决斗
    def involves?(user_id)
      [challenger_id, opponent_id].include?(user_id)
    end

    # 检查用户是否为发起者
    def challenger?(user_id)
      challenger_id == user_id
    end

    # 检查用户是否为对手
    def opponent?(user_id)
      opponent_id == user_id
    end

    private

    def cannot_duel_self
      if challenger_id == opponent_id
        errors.add(:opponent_id, "不能向自己发起决斗")
      end
    end
  end
end
