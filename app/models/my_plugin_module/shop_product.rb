# frozen_string_literal: true

module MyPluginModule
  class ShopProduct < ActiveRecord::Base
    self.table_name = 'qd_shop_products'

    validates :name, presence: true, length: { maximum: 100 }
    validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :stock, presence: true, numericality: { greater_than_or_equal_to: 0 }
    validates :tag, inclusion: { in: %w[new hot preorder] }, allow_nil: true
    
    # 合作商品校验
    validates :partnership_category, inclusion: { in: %w[decoration virtual] }, allow_nil: true, allow_blank: true, if: :is_partnership?
    validates :partner_username, presence: true, if: :is_partnership?
    validates :related_post_url, presence: true, if: :is_partnership?
    validates :commission_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
    
    # 装饰品类型必须填写框架或勋章ID
    validate :decoration_ids_required, if: -> { is_partnership? && partnership_category == 'decoration' }
    
    # 虚拟物品的邮箱和地址模板都是可选的，不需要验证
    
    # 清理空字符串字段
    before_validation :normalize_partnership_fields

    scope :active, -> { where(is_active: true) }
    scope :ordered, -> { order(:sort_order, :id) }
    scope :partnership, -> { where(is_partnership: true) }
    scope :regular, -> { where(is_partnership: false) }

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

    def tag_label
      case tag
      when 'new' then '新品'
      when 'hot' then '热销'
      when 'preorder' then '预购'
      else nil
      end
    end

    # 合作商品相关方法
    def partnership?
      is_partnership == true
    end

    def is_decoration?
      partnership? && partnership_category == 'decoration'
    end

    def is_virtual?
      partnership? && partnership_category == 'virtual'
    end

    def partner_user
      @partner_user ||= User.find_by(username: partner_username) if partner_username.present?
    end

    def calculate_partner_income(sale_price, quantity = 1)
      return 0 unless partnership?
      total = sale_price * quantity
      commission = total * (commission_rate / 100.0)
      total - commission
    end

    private

    def normalize_partnership_fields
      # 将空字符串转换为 nil，避免验证问题
      self.partner_username = nil if partner_username.blank?
      self.partnership_category = nil if partnership_category.blank?
      self.related_post_url = nil if related_post_url.blank?
      self.virtual_email_template = nil if virtual_email_template.blank?
      self.virtual_address_template = nil if virtual_address_template.blank?
    end

    def decoration_ids_required
      if decoration_frame_id.blank? && decoration_badge_id.blank?
        errors.add(:base, '装饰品类型商品必须至少填写头像框ID或勋章ID')
      end
    end
  end
end