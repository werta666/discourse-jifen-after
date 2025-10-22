# frozen_string_literal: true

module ::MyPluginModule
  class PaymentOrder < ActiveRecord::Base
    self.table_name = "jifen_payment_orders"

    belongs_to :user

    # 订单状态
    STATUS_PENDING = "pending"     # 待支付
    STATUS_PAID = "paid"           # 已支付
    STATUS_CANCELLED = "cancelled" # 已取消
    STATUS_REFUNDED = "refunded"   # 已退款

    validates :user_id, presence: true
    validates :out_trade_no, presence: true, uniqueness: true
    validates :amount, presence: true, numericality: { greater_than: 0 }
    validates :points, presence: true, numericality: { greater_than: 0 }
    validates :subject, presence: true
    validates :status, presence: true, inclusion: { in: [STATUS_PENDING, STATUS_PAID, STATUS_CANCELLED, STATUS_REFUNDED] }

    scope :pending, -> { where(status: STATUS_PENDING) }
    scope :paid, -> { where(status: STATUS_PAID) }
    scope :recent, -> { order(created_at: :desc) }
    scope :unexpired, -> { where("expires_at > ?", Time.current) }

    # 生成唯一订单号
    def self.generate_out_trade_no
      "JIFEN#{Time.current.strftime('%Y%m%d%H%M%S')}#{SecureRandom.hex(4).upcase}"
    end

    # 订单是否已过期
    def expired?
      expires_at.present? && expires_at < Time.current
    end

    # 订单是否可以支付
    def payable?
      status == STATUS_PENDING && !expired?
    end

    # 标记订单为已支付
    def mark_as_paid!(trade_no, notify_data = nil)
      update!(
        status: STATUS_PAID,
        trade_no: trade_no,
        paid_at: Time.current,
        notify_data: notify_data
      )
    end

    # 取消订单
    def cancel!
      return false unless status == STATUS_PENDING
      update!(status: STATUS_CANCELLED)
      true
    end
  end
end
