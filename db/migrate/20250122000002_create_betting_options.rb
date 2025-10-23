# frozen_string_literal: true

class CreateBettingOptions < ActiveRecord::Migration[6.0]
  def up
    unless table_exists?(:jifen_betting_options)
      create_table :jifen_betting_options do |t|
        t.integer  :event_id,          null: false
        t.string   :name,              null: false, limit: 255
        t.string   :logo,              limit: 100
        t.text     :description
        t.integer  :sort_order,        default: 0
        
        # 投注统计
        t.integer  :total_amount,      default: 0
        t.integer  :total_votes,       default: 0
        t.decimal  :current_odds,      precision: 10, scale: 2, default: 1.0
        
        # 结果
        t.boolean  :is_winner,         default: false
        
        t.timestamps null: false
      end
    end

    # 索引
    unless index_exists?(:jifen_betting_options, :event_id, name: "idx_betting_options_event")
      add_index :jifen_betting_options, :event_id, name: "idx_betting_options_event"
    end

    unless index_exists?(:jifen_betting_options, [:event_id, :sort_order], name: "idx_betting_options_event_sort")
      add_index :jifen_betting_options, [:event_id, :sort_order], name: "idx_betting_options_event_sort"
    end
  end

  def down
    drop_table :jifen_betting_options if table_exists?(:jifen_betting_options)
  end
end
