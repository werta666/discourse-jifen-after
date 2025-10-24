# frozen_string_literal: true

# 付费币交易记录表（简化版，仅记录基础信息）
class CreatePaidCoinRecords < ActiveRecord::Migration[6.0]
  def up
    unless table_exists?(:jifen_paid_coin_records)
      create_table :jifen_paid_coin_records do |t|
        t.integer  :user_id,        null: false    # 用户ID
        t.integer  :amount,         null: false    # 变动数量（正数=增加，负数=减少）
        t.string   :action_type,    null: false    # 操作类型: recharge/consume/adjust/refund
        t.string   :reason,         null: false    # 原因说明
        t.integer  :related_id                     # 关联ID（如订单ID、商品ID等）
        t.string   :related_type                   # 关联类型（如 PaymentOrder, ShopOrder 等）
        t.integer  :balance_after,  null: false    # 操作后余额
        t.timestamps null: false
      end
    end

    # 添加索引以加快查询
    unless index_exists?(:jifen_paid_coin_records, :user_id, name: "idx_paid_coin_records_user")
      add_index :jifen_paid_coin_records, :user_id, name: "idx_paid_coin_records_user"
    end

    unless index_exists?(:jifen_paid_coin_records, :created_at, name: "idx_paid_coin_records_created")
      add_index :jifen_paid_coin_records, :created_at, name: "idx_paid_coin_records_created"
    end

    unless index_exists?(:jifen_paid_coin_records, [:user_id, :created_at], name: "idx_paid_coin_records_user_created")
      add_index :jifen_paid_coin_records, [:user_id, :created_at], name: "idx_paid_coin_records_user_created"
    end
  end

  def down
    drop_table :jifen_paid_coin_records if table_exists?(:jifen_paid_coin_records)
  end
end
