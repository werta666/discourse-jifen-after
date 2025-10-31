# frozen_string_literal: true

module MyPluginModule
  class QdCreatorWork < ActiveRecord::Base
    self.table_name = 'qd_creator_works'
    
    belongs_to :user
    has_many :donations, class_name: 'MyPluginModule::QdCreatorDonation', foreign_key: :work_id, dependent: :destroy
    has_many :likes, class_name: 'MyPluginModule::QdCreatorWorkLike', foreign_key: :work_id, dependent: :destroy
    
    validates :user_id, presence: true
    validates :image_url, presence: true
    validates :post_url, presence: true
    validates :status, inclusion: { in: %w[pending approved rejected] }
    validates :shop_status, inclusion: { in: %w[none pending approved rejected] }
    
    scope :approved, -> { where(status: 'approved') }
    scope :pending, -> { where(status: 'pending') }
    scope :by_user, ->(user_id) { where(user_id: user_id) }
    scope :shop_products, -> { where(is_shop_product: true) }
    scope :by_likes, -> { order(likes_count: :desc) }
    scope :by_clicks, -> { order(clicks_count: :desc) }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_heat, -> { order(heat_score: :desc) }
    
    # 增加点赞数
    def increment_likes!
      increment!(:likes_count)
    end
    
    # 增加点击数
    def increment_clicks!
      increment!(:clicks_count)
    end
    
    # 检查用户是否已点赞
    def liked_by?(user)
      return false unless user
      likes.exists?(user_id: user.id)
    end
    
    # 审核通过
    def approve!(admin_user)
      update!(
        status: 'approved',
        approved_at: Time.zone.now,
        approved_by: admin_user.id
      )
    end
    
    # 驳回
    def reject!(reason)
      update!(
        status: 'rejected',
        rejection_reason: reason
      )
    end
    
    # 申请上架商品
    def apply_for_shop!
      update!(
        shop_applied_at: Time.zone.now,
        shop_status: 'pending'
      )
    end
    
    # 上架商品审核通过
    def approve_shop!
      update!(
        is_shop_product: true,
        shop_status: 'approved'
      )
    end
    
    # 上架商品审核驳回
    def reject_shop!(reason)
      update!(
        shop_status: 'rejected',
        rejection_reason: reason
      )
    end
    
    # 总打赏金额
    def total_donations
      donations.sum(:amount)
    end
    
    # 总创作者收入
    def total_creator_received
      donations.sum(:creator_received)
    end
    
    # 计算热度
    # 规则：
    # 1. 点赞权重（默认 +1）
    # 2. 浏览权重（默认 +1）
    # 3. 积分打赏权重（默认 1积分 = +1热度）
    # 4. 付费币打赏：每满threshold倍率增加，应用于所有基础热度（默认100，*2）
    def calculate_heat(heat_rules = nil)
      # 默认规则
      heat_rules ||= {
        'like_weight' => 1,
        'click_weight' => 1,
        'paid_coin_threshold' => 100,
        'paid_coin_base_multiplier' => 2,
        'jifen_weight' => 1
      }
      
      # 基础热度 = 点赞 * 权重 + 浏览 * 权重 + 积分 * 权重
      likes_heat = (likes_count || 0) * heat_rules['like_weight'].to_i
      clicks_heat = (clicks_count || 0) * heat_rules['click_weight'].to_i
      
      # 计算积分打赏热度
      jifen_total = donations.where(currency_type: 'jifen').sum(:amount)
      jifen_heat = jifen_total * heat_rules['jifen_weight'].to_i
      
      # 基础热度（包括点赞、浏览、积分）
      base_heat = likes_heat + clicks_heat + jifen_heat
      
      # 计算付费币打赏总额
      paid_coin_total = donations.where(currency_type: 'paid_coin').sum(:amount)
      
      # 计算付费币倍率（每满threshold，倍率增加）
      threshold = heat_rules['paid_coin_threshold'].to_i
      base_multiplier = heat_rules['paid_coin_base_multiplier'].to_i
      
      multiplier = if threshold > 0 && paid_coin_total >= threshold
        # 满了几个threshold就加几倍
        level = (paid_coin_total / threshold).floor
        base_multiplier + level - 1
      else
        1
      end
      
      # 最终热度 = (点赞 + 浏览 + 积分) * 付费币倍率
      base_heat * multiplier
    end
    
    # 更新热度值
    def update_heat!(heat_rules = nil)
      # 如果没有传入规则，从PluginStore获取
      heat_rules ||= PluginStore.get(::MyPluginModule::PLUGIN_NAME, 'heat_rules') || {
        'like_weight' => 1,
        'click_weight' => 1,
        'paid_coin_threshold' => 100,
        'paid_coin_base_multiplier' => 2,
        'jifen_weight' => 1
      }
      
      new_heat = calculate_heat(heat_rules)
      
      Rails.logger.info "[热度计算] 作品 #{id} (#{title}): likes=#{likes_count}, clicks=#{clicks_count}, 热度=#{new_heat}"
      
      update_column(:heat_score, new_heat)
    end
    
    # 获取热度值（用于显示）
    def heat_value
      heat_score || 0
    end
    
    # 获取热度颜色（根据阈值）
    def heat_color
      score = heat_score || 0
      heat_config = PluginStore.get(::MyPluginModule::PLUGIN_NAME, 'heat_config') || {
        'thresholds' => [100, 200, 300, 500],
        'colors' => ['#95DE64', '#FFC53D', '#FF7A45', '#F5222D', '#722ED1']
      }
      
      thresholds = heat_config['thresholds'] || [100, 200, 300, 500]
      colors = heat_config['colors'] || ['#95DE64', '#FFC53D', '#FF7A45', '#F5222D', '#722ED1']
      
      # 根据分数找到对应的颜色
      thresholds.each_with_index do |threshold, index|
        return colors[index] if score < threshold
      end
      
      # 超过所有阈值，返回最高级别颜色
      colors.last
    end
    
    # 计算并更新热度（同时支持显示）
    def calculate_and_update_heat!
      update_heat!
    end
  end
end
