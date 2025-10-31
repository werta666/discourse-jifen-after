# frozen_string_literal: true

class AddCurrencyTypeToShopProducts < ActiveRecord::Migration[7.0]
  def up
    unless column_exists?(:qd_shop_products, :currency_type)
      add_column :qd_shop_products, :currency_type, :string, default: "points"
    end

    unless index_exists?(:qd_shop_products, :currency_type, name: "idx_shop_products_currency_type")
      add_index :qd_shop_products, :currency_type, name: "idx_shop_products_currency_type"
    end
  end

  def down
    if column_exists?(:qd_shop_products, :currency_type)
      remove_column :qd_shop_products, :currency_type
    end
  end
end
