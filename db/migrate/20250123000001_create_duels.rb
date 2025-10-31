# frozen_string_literal: true

class CreateDuels < ActiveRecord::Migration[6.0]
  def up
    unless table_exists?(:jifen_duels)
      create_table :jifen_duels do |t|
        # 决斗双方
        t.integer  :challenger_id,     null: false  # 发起者
        t.integer  :opponent_id,       null: false  # 对手
        
        # 决斗信息
        t.string   :title,             null: false, limit: 200
        t.text     :description                     # 达成条件
        t.integer  :stake_amount,      null: false  # 赌注积分
        
        # 状态：pending(待接受), accepted(已接受), rejected(已拒绝), settled(已结算), cancelled(已取消)
        t.string   :status,            null: false, default: 'pending', limit: 20
        
        # 结算信息
        t.integer  :winner_id                       # 获胜者ID
        t.integer  :admin_id                        # 结算管理员ID
        t.datetime :settled_at                      # 结算时间
        t.text     :settlement_note                 # 结算备注
        
        t.timestamps null: false
      end
    end

    # 索引
    unless index_exists?(:jifen_duels, :challenger_id, name: "idx_duels_challenger")
      add_index :jifen_duels, :challenger_id, name: "idx_duels_challenger"
    end

    unless index_exists?(:jifen_duels, :opponent_id, name: "idx_duels_opponent")
      add_index :jifen_duels, :opponent_id, name: "idx_duels_opponent"
    end

    unless index_exists?(:jifen_duels, :status, name: "idx_duels_status")
      add_index :jifen_duels, :status, name: "idx_duels_status"
    end

    unless index_exists?(:jifen_duels, :created_at, name: "idx_duels_created_at")
      add_index :jifen_duels, :created_at, name: "idx_duels_created_at"
    end
  end

  def down
    drop_table :jifen_duels if table_exists?(:jifen_duels)
  end
end
