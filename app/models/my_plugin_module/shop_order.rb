# frozen_string_literal: true

module MyPluginModule
  class ShopOrder < ActiveRecord::Base
    self.table_name = 'qd_shop_orders'

    belongs_to :user, class_name: 'User'
    belongs_to :product, class_name: 'MyPluginModule::ShopProduct', optional: true

    validates :user_id, presence: true
    validates :product_name, presence: true
    validates :quantity, presence: true, numericality: { greater_than: 0 }
    validates :unit_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :total_price, presence: true, numericality: { greater_than_or_equal_to: 0 }

    scope :recent, -> { order(created_at: :desc) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :by_user, ->(user) { where(user: user) }
    scope :completed, -> { where(status: 'completed') }

    def formatted_total_price
      "#{total_price} 积分"
    end

    def formatted_created_at
      created_at.strftime('%Y-%m-%d %H:%M')
    end

    def status_text
      case status
      when 'completed'
        '已完成'
      when 'pending'
        '处理中'
      when 'cancelled'
        '已取消'
      when 'refunded'
        '已退款'
      else
        status
      end
    end

    def product_description
      product&.description || "商品描述"
    end

    def product_icon
      product&.icon_class || "fa fa-gift"
    end
  end
end