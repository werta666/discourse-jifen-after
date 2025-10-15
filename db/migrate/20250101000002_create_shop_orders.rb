class CreateShopOrders < ActiveRecord::Migration[7.0]
  def change
    create_table :qd_shop_orders do |t|
      t.integer :user_id, null: false
      t.integer :product_id, null: false
      t.string :product_name, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price, null: false
      t.integer :total_price, null: false
      t.string :status, default: 'completed'
      t.text :notes
      t.timestamps
    end

    add_index :qd_shop_orders, :user_id
    add_index :qd_shop_orders, :product_id
    add_index :qd_shop_orders, :created_at
  end
end