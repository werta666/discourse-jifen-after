# frozen_string_literal: true

class CreateBettingEvents < ActiveRecord::Migration[6.0]
  def up
    unless table_exists?(:jifen_betting_events)
      create_table :jifen_betting_events do |t|
        t.integer  :creator_id,        null: false
        t.string   :title,             null: false, limit: 255
        t.text     :description
        t.string   :event_type,        null: false, default: "vote"  # "bet" | "vote"
        t.string   :category,          limit: 50
        t.string   :status,            null: false, default: "pending"  # pending/active/finished/cancelled
        
        # 时间管理
        t.datetime :start_time,        null: false
        t.datetime :end_time,          null: false
        t.datetime :settled_at
        
        # 积分竞猜专属
        t.integer  :min_bet_amount,    default: 0
        t.integer  :total_pool,        default: 0
        t.integer  :total_bets,        default: 0
        t.integer  :winner_option_id
        
        # 统计字段
        t.integer  :total_participants, default: 0
        t.integer  :views_count,       default: 0
        
        t.timestamps null: false
      end
    end

    # 索引
    unless index_exists?(:jifen_betting_events, :creator_id, name: "idx_betting_events_creator")
      add_index :jifen_betting_events, :creator_id, name: "idx_betting_events_creator"
    end

    unless index_exists?(:jifen_betting_events, :status, name: "idx_betting_events_status")
      add_index :jifen_betting_events, :status, name: "idx_betting_events_status"
    end

    unless index_exists?(:jifen_betting_events, :event_type, name: "idx_betting_events_type")
      add_index :jifen_betting_events, :event_type, name: "idx_betting_events_type"
    end

    unless index_exists?(:jifen_betting_events, [:status, :start_time], name: "idx_betting_events_status_start")
      add_index :jifen_betting_events, [:status, :start_time], name: "idx_betting_events_status_start"
    end

    unless index_exists?(:jifen_betting_events, [:status, :end_time], name: "idx_betting_events_status_end")
      add_index :jifen_betting_events, [:status, :end_time], name: "idx_betting_events_status_end"
    end
  end

  def down
    drop_table :jifen_betting_events if table_exists?(:jifen_betting_events)
  end
end
