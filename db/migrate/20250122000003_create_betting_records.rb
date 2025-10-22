# frozen_string_literal: true

class CreateBettingRecords < ActiveRecord::Migration[6.0]
  def up
    unless table_exists?(:jifen_betting_records)
      create_table :jifen_betting_records do |t|
        t.integer  :user_id,           null: false
        t.integer  :event_id,          null: false
        t.integer  :option_id,         null: false
        
        # 投注信息
        t.integer  :bet_amount,        null: false
        t.decimal  :odds_at_bet,       precision: 10, scale: 2
        
        # 结算信息
        t.string   :status,            null: false, default: "pending"  # pending/won/lost/refunded
        t.integer  :win_amount,        default: 0
        t.datetime :settled_at
        
        t.timestamps null: false
      end
    end

    # 索引
    unless index_exists?(:jifen_betting_records, :user_id, name: "idx_betting_records_user")
      add_index :jifen_betting_records, :user_id, name: "idx_betting_records_user"
    end

    unless index_exists?(:jifen_betting_records, :event_id, name: "idx_betting_records_event")
      add_index :jifen_betting_records, :event_id, name: "idx_betting_records_event"
    end

    unless index_exists?(:jifen_betting_records, :option_id, name: "idx_betting_records_option")
      add_index :jifen_betting_records, :option_id, name: "idx_betting_records_option"
    end

    unless index_exists?(:jifen_betting_records, [:user_id, :event_id], name: "idx_betting_records_user_event", unique: true)
      add_index :jifen_betting_records, [:user_id, :event_id], name: "idx_betting_records_user_event", unique: true
    end

    unless index_exists?(:jifen_betting_records, [:event_id, :status], name: "idx_betting_records_event_status")
      add_index :jifen_betting_records, [:event_id, :status], name: "idx_betting_records_event_status"
    end
  end

  def down
    drop_table :jifen_betting_records if table_exists?(:jifen_betting_records)
  end
end
