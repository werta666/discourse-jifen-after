# frozen_string_literal: true

class AddUserContactToShopOrders < ActiveRecord::Migration[7.0]
  def change
    add_column :qd_shop_orders, :user_email, :string
    add_column :qd_shop_orders, :user_address, :text
  end
end
