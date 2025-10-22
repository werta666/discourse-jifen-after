# frozen_string_literal: true

module MyPluginModule
  class ShopProduct < ActiveRecord::Base
    self.table_name = 'qd_shop_products'

    validates :name, presence: true, length: { maximum: 100 }
    validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0 }

    scope :active, -> { where(is_active: true) }
    scope :ordered, -> { order(:sort_order, :id) }

    def available?
      is_active? && stock > 0
    end

    def can_purchase?(quantity = 1)
      available? && stock >= quantity
    end

    def reduce_stock!(quantity)
      return false unless can_purchase?(quantity)
      
      update!(
        stock: stock - quantity,
        sales_count: sales_count + quantity
      )
      true
    end

    def formatted_price
      "#{price} 积分"
    end

    def icon_class_or_default
      icon_class.present? ? icon_class : 'fa fa-gift'
    end

    def stock_status
      if stock <= 0
        '缺货'
      elsif stock <= 10
        '库存紧张'
      else
        '库存充足'
      end
    end

    def stock_status_class
      if stock <= 0
        'out-of-stock'
      elsif stock <= 10
        'low-stock'
      else
        'in-stock'
      end
    end
  end
end