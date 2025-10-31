# frozen_string_literal: true

class AddTagToQdShopProducts < ActiveRecord::Migration[7.0]
  def up
    unless column_exists?(:qd_shop_products, :tag)
      add_column :qd_shop_products, :tag, :string, limit: 16
    end

    unless index_exists?(:qd_shop_products, :tag, name: "idx_shop_products_tag")
      add_index :qd_shop_products, :tag, name: "idx_shop_products_tag"
    end
  end

  def down
    if column_exists?(:qd_shop_products, :tag)
      remove_column :qd_shop_products, :tag
    end
  end
end
