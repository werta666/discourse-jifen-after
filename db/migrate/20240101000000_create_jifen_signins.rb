# frozen_string_literal: true

class CreateJifenSignins < ActiveRecord::Migration[6.0]
  def up
    unless table_exists?(:jifen_signins)
      create_table :jifen_signins do |t|
        t.integer :user_id, null: false
        t.date :date, null: false
        t.datetime :signed_at, null: false
        t.boolean :makeup, null: false, default: false
        t.integer :points, null: false, default: 0
        t.integer :streak_count, null: false, default: 1
        t.timestamps null: false
      end
    end

    unless index_exists?(:jifen_signins, [:user_id, :date], name: "idx_jifen_signins_uid_date")
      add_index :jifen_signins, [:user_id, :date], unique: true, name: "idx_jifen_signins_uid_date"
    end

    unless index_exists?(:jifen_signins, [:user_id, :created_at], name: "idx_jifen_signins_uid_created")
      add_index :jifen_signins, [:user_id, :created_at], name: "idx_jifen_signins_uid_created"
    end
  end

  def down
    drop_table :jifen_signins if table_exists?(:jifen_signins)
  end
end