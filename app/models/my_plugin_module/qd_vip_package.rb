# frozen_string_literal: true

module MyPluginModule
  class QdVipPackage < ActiveRecord::Base
    self.table_name = "vip_packages"
    
    # 关联
    has_many :subscriptions, class_name: "MyPluginModule::QdVipSubscription", foreign_key: :package_id
    
    # 验证
    validates :name, presence: true
    validates :level, presence: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10 }
    validate :validate_pricing_plans
    
    # 范围
    scope :active, -> { where(is_active: true) }
    scope :by_level, ->(level) { where(level: level) }
    scope :ordered, -> { order(sort_order: :asc, level: :asc, created_at: :desc)}
    
    # 时长类型映射
    DURATION_TYPES = {
      "monthly" => { days: 30, label: "月付" },
      "quarterly" => { days: 90, label: "季付" },
      "annual" => { days: 365, label: "年付" }
    }.freeze
    
    # 获取时长标签
    def duration_label
      DURATION_TYPES.dig(duration_type, :label) || duration_type
    end
    
    # 获取定价计划列表
    def pricing_plans_list
      begin
        plans = pricing_plans
        
        # 确保 pricing_plans 不是 nil 且是数组
        if plans.nil? || !plans.is_a?(Array)
          Rails.logger.warn "[VIP Package] 套餐 #{name} (ID: #{id}) pricing_plans 无效: #{plans.inspect}"
          return []
        end
        
        if plans.empty?
          Rails.logger.warn "[VIP Package] 套餐 #{name} (ID: #{id}) pricing_plans 为空数组"
          return []
        end
        
        result = plans.map do |plan|
          # 严格验证每个计划
          unless plan.is_a?(Hash)
            Rails.logger.warn "[VIP Package] 套餐 #{name} 的计划不是Hash: #{plan.class}"
            next
          end
          
          unless plan["type"].present? && plan["days"].present? && plan["price"].present?
            Rails.logger.warn "[VIP Package] 套餐 #{name} 的计划缺少必需字段: #{plan.inspect}"
            next
          end

          # 过滤掉不受支持的时长类型（如 legacy 的 "semiannual"）
          type_key = plan["type"].to_s
          unless DURATION_TYPES.key?(type_key)
            Rails.logger.warn "[VIP Package] 套餐 #{name} 的计划类型不受支持: #{type_key}, 已忽略"
            next
          end
          
          {
            type: type_key,
            days: plan["days"].to_i,
            price: plan["price"].to_i,
            label: DURATION_TYPES.dig(type_key, :label) || type_key
          }
        end.compact  # 移除 nil 值
        
        # 确保至少返回空数组
        result.presence || []
      rescue => e
        Rails.logger.error "[VIP Package] 套餐 #{name} pricing_plans_list 出错: #{e.message}"
        []
      end
    end
    
    # 获取指定类型的价格
    def price_for(duration_type)
      plan = (pricing_plans || []).find { |p| p["type"] == duration_type }
      plan ? plan["price"] : nil
    end
    
    # 获取指定类型的天数
    def days_for(duration_type)
      plan = (pricing_plans || []).find { |p| p["type"] == duration_type }
      plan ? plan["days"] : nil
    end
    
    # 向后兼容：如果没有pricing_plans，从旧字段获取
    def duration_days
      if pricing_plans.present? && pricing_plans.any?
        pricing_plans.first["days"]
      else
        read_attribute(:duration_days)
      end
    end
    
    def price
      if pricing_plans.present? && pricing_plans.any?
        pricing_plans.first["price"]
      else
        read_attribute(:price)
      end
    end
    
    def duration_type
      if pricing_plans.present? && pricing_plans.any?
        pricing_plans.first["type"]
      else
        read_attribute(:duration_type)
      end
    end
    
    # 获取奖励内容
    def makeup_cards_count
      rewards.dig("makeup_cards") || 0
    end
    
    def avatar_frame_id
      rewards.dig("avatar_frame_id")
    end
    
    def badge_id
      rewards.dig("badge_id")
    end
    
    # 设置奖励
    def set_rewards(makeup_cards: nil, avatar_frame_id: nil, badge_id: nil)
      self.rewards ||= {}
      self.rewards["makeup_cards"] = makeup_cards.to_i if makeup_cards
      self.rewards["avatar_frame_id"] = avatar_frame_id.to_i if avatar_frame_id
      self.rewards["badge_id"] = badge_id.to_i if badge_id
    end
    
    private
    
    def validate_pricing_plans
      if pricing_plans.blank? || !pricing_plans.is_a?(Array) || pricing_plans.empty?
        errors.add(:pricing_plans, "must have at least one pricing plan")
        return
      end
      
      pricing_plans.each_with_index do |plan, index|
        unless plan.is_a?(Hash) && plan["type"].present? && plan["days"].present? && plan["price"].present?
          errors.add(:pricing_plans, "plan #{index + 1} is invalid")
        end
        
        unless DURATION_TYPES.keys.include?(plan["type"])
          errors.add(:pricing_plans, "plan #{index + 1} has invalid type: #{plan['type']}")
        end
        
        unless plan["days"].to_i > 0
          errors.add(:pricing_plans, "plan #{index + 1} must have positive days")
        end
        
        unless plan["price"].to_i >= 0
          errors.add(:pricing_plans, "plan #{index + 1} must have non-negative price")
        end
      end
    end
  end
end
