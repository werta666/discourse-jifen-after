# frozen_string_literal: true

class CreateVipPackages < ActiveRecord::Migration[7.0]
  def change
    # VIP套餐表（支持多时长定价）
    create_table :vip_packages do |t|
      t.string :name, null: false               # 套餐名称，如 "VIP 1"
      t.integer :level, null: false             # VIP等级，1-10
      t.text :description                       # 套餐描述
      
      # 多时长定价方案（JSON数组）
      # 格式：[{type: "monthly", days: 30, price: 100}, {type: "quarterly", days: 90, price: 270}, ...]
      t.json :pricing_plans, default: []
      
      # 向后兼容的旧字段（可选）
      t.integer :duration_days                  # 默认时长（天）
      t.integer :price                          # 默认价格（付费币）
      t.string :duration_type                   # 默认时长类型
      
      # 赠送内容（JSON格式）
      t.json :rewards, default: {}              # { makeup_cards: 5, avatar_frame_id: 1, badge_id: 2 }
      
      # VIP特权
      t.integer :daily_signin_bonus, default: 0 # 每日签到额外积分
      
      t.boolean :is_active, default: true       # 是否启用
      t.integer :sort_order, default: 0         # 排序
      
      t.timestamps
    end
    
    add_index :vip_packages, :level
    add_index :vip_packages, :is_active
    
    # VIP订阅记录表
    create_table :vip_subscriptions do |t|
      t.integer :user_id, null: false           # 用户ID
      t.integer :package_id, null: false        # 套餐ID
      t.integer :vip_level, null: false         # VIP等级
      t.integer :duration_days, null: false     # 购买的时长（天）
      t.string :duration_type, null: false      # 购买的时长类型
      t.integer :price_paid, null: false        # 实付价格
      t.datetime :started_at, null: false       # 开通时间
      t.datetime :expires_at, null: false       # 到期时间
      t.string :status, default: "active"       # 状态: active, expired, cancelled
      
      t.timestamps
    end
    
    add_index :vip_subscriptions, :user_id
    add_index :vip_subscriptions, :status
    add_index :vip_subscriptions, :expires_at
    add_index :vip_subscriptions, [:user_id, :status]
  end
end
