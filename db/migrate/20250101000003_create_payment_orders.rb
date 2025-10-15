# frozen_string_literal: true

class CreatePaymentOrders < ActiveRecord::Migration[6.0]
  def up
    unless table_exists?(:jifen_payment_orders)
      create_table :jifen_payment_orders do |t|
        t.integer  :user_id,         null: false
        t.string   :out_trade_no,    null: false, index: { unique: true }  # 商户订单号
        t.string   :trade_no                                                # 支付宝交易号
        t.decimal  :amount,          precision: 10, scale: 2, null: false   # 支付金额（元）
        t.integer  :points,          null: false                            # 兑换积分数
        t.string   :subject,         null: false                            # 订单标题
        t.string   :status,          null: false, default: "pending"        # pending/paid/cancelled/refunded
        t.string   :qr_code                                                 # 支付宝二维码地址
        t.datetime :paid_at                                                 # 支付完成时间
        t.datetime :expires_at                                              # 订单过期时间
        t.text     :notify_data                                             # 支付宝异步通知原始数据
        t.timestamps null: false
      end
    end

    unless index_exists?(:jifen_payment_orders, :user_id, name: "idx_jifen_payment_orders_uid")
      add_index :jifen_payment_orders, :user_id, name: "idx_jifen_payment_orders_uid"
    end

    unless index_exists?(:jifen_payment_orders, :status, name: "idx_jifen_payment_orders_status")
      add_index :jifen_payment_orders, :status, name: "idx_jifen_payment_orders_status"
    end

    unless index_exists?(:jifen_payment_orders, :created_at, name: "idx_jifen_payment_orders_created")
      add_index :jifen_payment_orders, :created_at, name: "idx_jifen_payment_orders_created"
    end
  end

  def down
    drop_table :jifen_payment_orders if table_exists?(:jifen_payment_orders)
  end
end
