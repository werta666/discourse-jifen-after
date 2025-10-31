class CreateCreatorDonations < ActiveRecord::Migration[7.0]
  def change
    create_table :qd_creator_donations do |t|
      t.integer :work_id, null: false           # 作品ID
      t.integer :donor_id, null: false          # 打赏人ID
      t.integer :creator_id, null: false        # 创作者ID
      t.integer :amount, null: false            # 打赏金额
      t.string :currency_type, null: false      # 货币类型: jifen/paid_coin
      t.decimal :commission_rate, precision: 5, scale: 2, default: 0.0  # 抽成比例(%)
      t.integer :commission_amount, default: 0  # 抽成金额
      t.integer :creator_received, null: false  # 创作者实收金额
      t.timestamps
    end

    add_index :qd_creator_donations, :work_id
    add_index :qd_creator_donations, :donor_id
    add_index :qd_creator_donations, :creator_id
    add_index :qd_creator_donations, :created_at
  end
end
