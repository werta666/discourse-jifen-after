# frozen_string_literal: true

class AddPaymentMethodToPaymentOrders < ActiveRecord::Migration[6.0]
  def up
    unless column_exists?(:jifen_payment_orders, :payment_method)
      add_column :jifen_payment_orders, :payment_method, :string, default: "alipay"
    end

    unless index_exists?(:jifen_payment_orders, :payment_method, name: "idx_jifen_payment_orders_method")
      add_index :jifen_payment_orders, :payment_method, name: "idx_jifen_payment_orders_method"
    end
  end

  def down
    if column_exists?(:jifen_payment_orders, :payment_method)
      remove_column :jifen_payment_orders, :payment_method
    end
  end
end
