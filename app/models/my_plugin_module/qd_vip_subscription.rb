# frozen_string_literal: true

module MyPluginModule
  class QdVipSubscription < ActiveRecord::Base
    self.table_name = "vip_subscriptions"
    
    # 关联
    belongs_to :user
    belongs_to :package, class_name: "MyPluginModule::QdVipPackage", foreign_key: :package_id
    
    # 验证
    validates :user_id, presence: true
    validates :package_id, presence: true
    validates :vip_level, presence: true
    validates :duration_days, presence: true
    validates :duration_type, presence: true
    validates :price_paid, presence: true
    validates :started_at, presence: true
    validates :expires_at, presence: true
    validates :status, inclusion: { in: %w[active expired cancelled] }
    
    # 作用域
    scope :active, -> { where(status: "active").where("expires_at > ?", Time.current) }
    scope :expired, -> { where(status: "expired").or(where("expires_at <= ?", Time.current)) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    
    # 回调
    before_save :update_status
    
    # 检查是否有效
    def valid_subscription?
      status == "active" && expires_at > Time.current
    end
    
    # 剩余天数
    def days_remaining
      return 0 if expired?
      ((expires_at - Time.current) / 1.day).ceil
    end
    
    # 是否已过期
    def expired?
      expires_at <= Time.current || status != "active"
    end
    
    # 更新状态
    def update_status
      if expires_at <= Time.current && status == "active"
        self.status = "expired"
      end
    end
    
    # 类方法：获取用户当前VIP
    def self.current_vip_for(user)
      active.for_user(user.id).order(vip_level: :desc, expires_at: :desc).first
    end
    
    # 类方法：用户是否是VIP
    def self.is_vip?(user)
      current_vip_for(user).present?
    end
    
    # 类方法：获取用户VIP等级
    def self.vip_level_for(user)
      current_vip = current_vip_for(user)
      current_vip&.vip_level || 0
    end
  end
end
