class CreateShopProducts < ActiveRecord::Migration[7.0]
  def change
    create_table :qd_shop_products do |t|
      t.string :name, null: false
      t.text :description
      t.integer :price, null: false, default: 0
      t.integer :stock, null: false, default: 0
      t.string :icon_class, default: 'fas fa-gift'
      t.boolean :is_active, default: true
      t.integer :sales_count, default: 0
      t.integer :sort_order, default: 0
      t.timestamps
    end

    add_index :qd_shop_products, :is_active
    add_index :qd_shop_products, :sort_order
  end
end