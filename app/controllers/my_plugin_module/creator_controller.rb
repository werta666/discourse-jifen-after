# frozen_string_literal: true

module MyPluginModule
  class CreatorController < ApplicationController
    requires_plugin 'discourse-jifen-after'
    
    before_action :ensure_logged_in, except: [:index]
    before_action :ensure_creator_whitelist, only: [:make, :create_work, :my_donations]
    before_action :ensure_admin, only: [:admin, :approve_work, :reject_work, :update_shop_standards, :update_commission_rate, :update_max_donations, :approve_shop, :reject_shop, :update_work_status, :delete_work, :update_whitelist, :update_heat_config, :update_heat_rules, :approve_application, :reject_application]
    
    # GET /qd/apply - 创作者申请页面
    def apply_page
      # 检查用户是否已是创作者
      is_creator = current_user&.custom_fields&.[]("is_creator") == "true"
      
      # 检查是否已有待审核的申请
      pending_application = current_user ? MyPluginModule::CreatorApplication.find_by(
        user_id: current_user.id,
        status: MyPluginModule::CreatorApplication::STATUS_PENDING
      ) : nil
      
      # 获取申请费用
      application_fee = SiteSetting.jifen_creator_application_fee
      
      # 获取用户积分余额
      user_points = current_user ? MyPluginModule::JifenService.available_total_points(current_user) : 0
      
      render json: {
        is_creator: is_creator,
        has_pending_application: pending_application.present?,
        pending_application: pending_application ? {
          id: pending_application.id,
          creative_field: pending_application.creative_field,
          creative_experience: pending_application.creative_experience,
          portfolio_images: pending_application.portfolio_images,
          submitted_at: pending_application.submitted_at
        } : nil,
        application_fee: application_fee,
        user_points: user_points,
        can_afford: user_points >= application_fee
      }
    rescue => e
      Rails.logger.error "[创作者申请] 加载申请页面失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: e.message }, status: 500
    end
    
    # POST /qd/apply/submit - 提交创作者申请
    def submit_application
      # 检查是否已是创作者
      if current_user.custom_fields["is_creator"] == "true"
        render json: { error: "您已经是创作者了" }, status: 422
        return
      end
      
      # 检查是否已有待审核的申请
      existing_pending = MyPluginModule::CreatorApplication.find_by(
        user_id: current_user.id,
        status: MyPluginModule::CreatorApplication::STATUS_PENDING
      )
      
      if existing_pending
        render json: { error: "您已有待审核的申请，请等待管理员处理" }, status: 422
        return
      end
      
      # 获取申请费用
      application_fee = SiteSetting.jifen_creator_application_fee
      
      # 检查积分余额
      user_points = MyPluginModule::JifenService.available_total_points(current_user)
      if user_points < application_fee
        render json: { error: "积分不足，需要 #{application_fee} 积分" }, status: 422
        return
      end
      
      # 验证必填字段
      creative_field = params[:creative_field].to_s.strip
      creative_experience = params[:creative_experience].to_s.strip
      portfolio_images = params[:portfolio_images] || []
      
      # 创作领域验证
      if creative_field.length < 10
        render json: { error: "创作领域至少需要10个字符" }, status: 422
        return
      end
      
      if creative_field.length > 500
        render json: { error: "创作领域不能超过500个字符" }, status: 422
        return
      end
      
      # 创作经历验证
      if creative_experience.length < 20
        render json: { error: "创作经历至少需要20个字符" }, status: 422
        return
      end
      
      if creative_experience.length > 2000
        render json: { error: "创作经历不能超过2000个字符" }, status: 422
        return
      end
      
      # 作品集图片验证
      if portfolio_images.length < 2
        render json: { error: "请至少上传2张代表作或证明图片" }, status: 422
        return
      end
      
      if portfolio_images.length > 5
        render json: { error: "最多只能上传5张图片" }, status: 422
        return
      end
      
      ActiveRecord::Base.transaction do
        # 扣除申请费用
        if application_fee > 0
          MyPluginModule::JifenService.adjust_points!(
            current_user,
            current_user,
            -application_fee
          )
        end
        
        # 创建申请
        application = MyPluginModule::CreatorApplication.create!(
          user_id: current_user.id,
          creative_field: creative_field,
          creative_experience: creative_experience,
          portfolio_images: portfolio_images,
          application_fee: application_fee,
          submitted_at: Time.current
        )
        
        Rails.logger.info "[创作者申请] 用户 #{current_user.username} 提交了申请 ##{application.id}"
        
        render json: {
          success: true,
          message: "申请已提交，请等待管理员审核",
          application: {
            id: application.id,
            submitted_at: application.submitted_at
          }
        }
      end
    rescue => e
      Rails.logger.error "[创作者申请] 提交申请失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: "提交失败: #{e.message}" }, status: 500
    end
    
    # GET /qd/apply/status - 查询申请状态
    def application_status
      application = MyPluginModule::CreatorApplication.find_by(user_id: current_user.id)
      
      unless application
        render json: { has_application: false }
        return
      end
      
      render json: {
        has_application: true,
        status: application.status,
        submitted_at: application.submitted_at,
        reviewed_at: application.reviewed_at,
        rejection_reason: application.rejection_reason,
        fee_refunded: application.fee_refunded
      }
    end
    
    # GET /qd/center/zp/:id - 作品详情页面（Ember引导）
    def work_page
      render "default/empty"
    end
    
    # GET /qd/center - 作品墙（所有人可访问）
    def index
      # 按热度排序获取作品（不每次都重新计算，避免性能问题）
      works = MyPluginModule::QdCreatorWork.approved.by_heat.limit(100)
      
      Rails.logger.info "[创作者中心] 查询到 #{works.count} 个已通过作品"
      
      works_data = works.map do |work|
        user = User.find_by(id: work.user_id)
        
        # 计算打赏统计（显示原始打赏金额，不扣除手续费）
        donations = MyPluginModule::QdCreatorDonation.where(work_id: work.id)
        jifen_received = donations.where(currency_type: 'jifen').sum(:amount)
        paid_coin_received = donations.where(currency_type: 'paid_coin').sum(:amount)
        
        {
          id: work.id,
          user_id: work.user_id,
          username: user&.username || "未知用户",
          title: work.title,
          image_url: work.image_url,
          post_url: work.post_url,
          likes_count: work.likes_count || 0,
          clicks_count: work.clicks_count || 0,
          heat_score: work.heat_score || 0,
          jifen_received: jifen_received,
          paid_coin_received: paid_coin_received,
          liked_by_current_user: current_user ? work.liked_by?(current_user) : false,
          created_at: work.created_at
        }
      end
      
      # 获取热度配置（只包含阈值）
      heat_config = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'heat_config') || {
        'thresholds' => [100, 200, 300, 500]
      }
      
      Rails.logger.info "[创作者中心] 读取热度配置: #{heat_config.inspect}"
      
      # 获取热度规则
      heat_rules = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'heat_rules') || {
        'like_weight' => 1,
        'click_weight' => 1,
        'paid_coin_threshold' => 100,
        'paid_coin_base_multiplier' => 2,
        'jifen_weight' => 1
      }
      
      Rails.logger.info "[创作者中心] 读取热度规则: #{heat_rules.inspect}"
      
      # 获取白名单
      whitelist = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_whitelist') || []
      
      render json: {
        works: works_data,
        jifen_name: "积分",
        paid_coin_name: SiteSetting.jifen_paid_coin_name || "付费币",
        heat_config: heat_config,
        heat_rules: heat_rules,
        whitelist: whitelist
      }
    rescue => e
      Rails.logger.error "[创作者中心] 作品墙加载失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: {
        works: [],
        jifen_name: "积分",
        paid_coin_name: SiteSetting.jifen_paid_coin_name || "付费币",
        error: e.message
      }, status: 200
    end
    
    # GET /qd/center/make - 创作者操作页面
    def make
      # 获取当前用户的作品
      my_works = MyPluginModule::QdCreatorWork.by_user(current_user.id).recent
      
      Rails.logger.info "[创作者中心] 用户 #{current_user.username} 的作品数: #{my_works.count}"
      
      # 获取打赏记录
      donations = MyPluginModule::QdCreatorDonation.by_creator(current_user.id).recent.limit(100)
      
      works_data = my_works.map do |work|
        # 计算该作品的分别收益
        work_donations = MyPluginModule::QdCreatorDonation.where(work_id: work.id)
        jifen_received = work_donations.where(currency_type: 'jifen').sum(:creator_received)
        paid_coin_received = work_donations.where(currency_type: 'paid_coin').sum(:creator_received)
        
        {
          id: work.id,
          title: work.title,
          image_url: work.image_url,
          post_url: work.post_url,
          status: work.status,
          likes_count: work.likes_count,
          clicks_count: work.clicks_count,
          total_donations: work.total_donations,
          total_received: work.total_creator_received,
          jifen_received: jifen_received,
          paid_coin_received: paid_coin_received,
          shop_status: work.shop_status,
          created_at: work.created_at,
          approved_at: work.approved_at,
          rejection_reason: work.rejection_reason
        }
      end
      
      donations_data = donations.map do |donation|
        {
          id: donation.id,
          work_id: donation.work_id,
          work_title: donation.work.title,
          donor_username: donation.donor.username,
          amount: donation.amount,
          currency_type: donation.currency_type,
          commission_rate: donation.commission_rate,
          commission_amount: donation.commission_amount,
          creator_received: donation.creator_received,
          created_at: donation.created_at
        }
      end
      
      # 获取上架标准
      shop_standards = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_shop_standards') || {
        'min_likes' => 10,
        'min_clicks' => 50
      }
      
      # 计算总收益（分积分和付费币）
      all_donations = MyPluginModule::QdCreatorDonation.by_creator(current_user.id)
      total_jifen_received = all_donations.where(currency_type: 'jifen').sum(:creator_received)
      total_paid_coin_received = all_donations.where(currency_type: 'paid_coin').sum(:creator_received)
      
      # 获取合作销售记录
      partnership_sales = []
      if ActiveRecord::Base.connection.table_exists?('qd_shop_products') && 
         ActiveRecord::Base.connection.table_exists?('qd_shop_orders')
        # 查找当前用户作为合作伙伴的商品
        partner_products = MyPluginModule::ShopProduct.where(
          is_partnership: true,
          partner_username: current_user.username
        )
        
        if partner_products.any?
          product_ids = partner_products.pluck(:id)
          
          # 查找这些商品的已完成订单
          orders = MyPluginModule::ShopOrder.where(
            product_id: product_ids,
            status: ['pending', 'completed']
          ).order(created_at: :desc).limit(100)
          
          partnership_sales = orders.map do |order|
            product = partner_products.find { |p| p.id == order.product_id }
            next unless product
            
            # 计算实收利润
            total_sale = order.total_price
            partner_income = product.calculate_partner_income(order.unit_price, order.quantity)
            
            {
              id: order.id,
              product_id: product.id,
              product_name: product.name,
              buyer_username: User.find_by(id: order.user_id)&.username || "未知用户",
              quantity: order.quantity,
              unit_price: order.unit_price,
              total_price: total_sale,
              commission_rate: product.commission_rate || 0,
              partner_income: partner_income.to_i,
              currency_type: order.currency_type || "points",
              order_status: order.status,
              created_at: order.created_at
            }
          end.compact
        end
      end
      
      render json: {
        my_works: works_data,
        donations: donations_data,
        partnership_sales: partnership_sales,
        shop_standards: shop_standards,
        jifen_name: "积分",
        paid_coin_name: SiteSetting.jifen_paid_coin_name || "付费币",
        total_jifen_received: total_jifen_received,
        total_paid_coin_received: total_paid_coin_received
      }
    rescue => e
      Rails.logger.error "[创作者中心] 加载失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: {
        my_works: [],
        donations: [],
        shop_standards: { 'min_likes' => 10, 'min_clicks' => 50 },
        jifen_name: "积分",
        paid_coin_name: "付费币"
      }, status: 200
    end
    
    # POST /qd/center/create_work - 创建作品
    def create_work
      work = MyPluginModule::QdCreatorWork.new(
        user_id: current_user.id,
        title: params[:title],
        image_url: params[:image_url],
        post_url: params[:post_url]
      )
      
      if work.save
        render json: { success: true, work: serialize_work(work) }
      else
        render json: { error: work.errors.full_messages.join(", ") }, status: 422
      end
    end
    
    # POST /qd/center/like - 点赞/取消点赞作品
    def like_work
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      
      # 检查是否已点赞
      existing_like = MyPluginModule::QdCreatorWorkLike.find_by(work_id: work.id, user_id: current_user.id)
      
      if existing_like
        # 已点赞，执行取消操作
        existing_like.destroy!
        work.decrement!(:likes_count)
        work.update_heat!  # 更新热度
        
        render json: { 
          success: true, 
          liked: false, 
          likes_count: work.likes_count,
          heat_score: work.heat_score,
          message: "已取消点赞"
        }
      else
        # 未点赞，执行点赞操作
        like = MyPluginModule::QdCreatorWorkLike.new(work_id: work.id, user_id: current_user.id)
        
        if like.save
          work.increment_likes!
          work.update_heat!  # 更新热度
          render json: { 
            success: true, 
            liked: true, 
            likes_count: work.likes_count,
            heat_score: work.heat_score,
            message: "点赞成功"
          }
        else
          render json: { error: like.errors.full_messages.join(", ") }, status: 422
        end
      end
    end
    
    # POST /qd/center/click - 记录点击
    def record_click
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      
      # 作者自己的浏览不计入浏览量
      if current_user && work.user_id == current_user.id
        render json: { 
          success: true, 
          clicks_count: work.clicks_count, 
          heat_score: work.heat_score,
          message: "作者自己的浏览不计入统计"
        }
        return
      end
      
      work.increment_clicks!
      work.update_heat!  # 更新热度
      render json: { success: true, clicks_count: work.clicks_count, heat_score: work.heat_score }
    end
    
    # DELETE /qd/center/delete_rejected_work - 创作者删除自己被驳回的作品
    def delete_rejected_work
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      
      # 验证是作品所有者
      unless work.user_id == current_user.id
        render json: { error: "无权删除此作品" }, status: 403
        return
      end
      
      # 只能删除被驳回的作品
      unless work.status == 'rejected'
        render json: { error: "只能删除被驳回的作品" }, status: 422
        return
      end
      
      work.destroy!
      
      render json: { 
        success: true, 
        message: "作品已删除" 
      }
    rescue => e
      Rails.logger.error "[创作者中心] 删除作品失败: #{e.message}"
      render json: { error: "删除失败: #{e.message}" }, status: 500
    end
    
    # POST /qd/center/donate - 打赏作品
    def donate
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      amount = params[:amount].to_i
      currency_type = params[:currency_type] # 'jifen' or 'paid_coin'
      
      # 禁止作者打赏自己的作品
      if work.user_id == current_user.id
        render json: { error: "不能打赏自己的作品" }, status: 422
        return
      end
      
      if amount <= 0
        render json: { error: "打赏金额必须大于0" }, status: 422
        return
      end
      
      # 检查打赏次数限制
      max_donations_per_work = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_max_donations_per_work')&.to_i || 0
      
      if max_donations_per_work > 0
        # 统计该用户对该作品的打赏次数
        donation_count = MyPluginModule::QdCreatorDonation.where(
          work_id: work.id,
          donor_id: current_user.id
        ).count
        
        if donation_count >= max_donations_per_work
          render json: { error: "您已达到对该作品的最大打赏次数限制（#{max_donations_per_work}次）" }, status: 422
          return
        end
      end
      
      # 获取抽成比例
      commission_rate = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_donation_commission_rate')&.to_f || 0.0
      
      # 计算抽成
      calculation = MyPluginModule::QdCreatorDonation.calculate_creator_amount(amount, commission_rate)
      
      # 检查余额
      case currency_type
      when 'jifen'
        # 使用 JifenService 获取可用积分（与 shop 相同的方式）
        current_balance = MyPluginModule::JifenService.available_total_points(current_user)
        if current_balance < amount
          render json: { error: "积分不足" }, status: 422
          return
        end
      when 'paid_coin'
        current_balance = MyPluginModule::PaidCoinService.available_coins(current_user)
        if current_balance < amount
          render json: { error: "#{SiteSetting.jifen_paid_coin_name}不足" }, status: 422
          return
        end
      else
        render json: { error: "无效的货币类型" }, status: 422
        return
      end
      
      ActiveRecord::Base.transaction do
        # 扣除打赏人的币
        case currency_type
        when 'jifen'
          # 使用 JifenService 扣减积分（与 shop 相同的方式）
          MyPluginModule::JifenService.adjust_points!(
            current_user,
            current_user,
            -amount
          )
        when 'paid_coin'
          MyPluginModule::PaidCoinService.deduct_coins!(current_user, amount, reason: "打赏作品 ##{work.id}", related_id: work.id, related_type: "CreatorWork")
        end
        
        # 给创作者加币（扣除抽成后）
        creator = User.find(work.user_id)
        case currency_type
        when 'jifen'
          # 使用 JifenService 增加积分
          MyPluginModule::JifenService.adjust_points!(
            current_user,
            creator,
            calculation[:creator_received]
          )
        when 'paid_coin'
          MyPluginModule::PaidCoinService.add_coins!(creator, calculation[:creator_received], reason: "收到作品打赏 ##{work.id}", related_id: work.id, related_type: "CreatorWork")
        end
        
        # 记录打赏
        donation = MyPluginModule::QdCreatorDonation.create!(
          work_id: work.id,
          donor_id: current_user.id,
          creator_id: creator.id,
          amount: amount,
          currency_type: currency_type,
          commission_rate: commission_rate,
          commission_amount: calculation[:commission_amount],
          creator_received: calculation[:creator_received]
        )
        
        # 更新热度
        work.update_heat!
        
        # 获取货币名称
        currency_name = case currency_type
        when 'jifen'
          "积分"
        when 'paid_coin'
          SiteSetting.jifen_paid_coin_name || "付费币"
        else
          "币"
        end
        
        render json: {
          success: true,
          show_celebration: true,
          message: "感谢您的打赏！",
          donation: {
            amount: donation.amount,
            currency_name: currency_name,
            work_title: work.title,
            creator_username: creator.username
          },
          heat_score: work.heat_score
        }
      end
    rescue => e
      Rails.logger.error "[创作者中心] 打赏失败: #{e.message}"
      render json: { error: "打赏失败: #{e.message}" }, status: 500
    end
    
    # POST /qd/center/apply_shop - 申请上架商品
    def apply_shop
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      
      # 检查是否是作品所有者
      if work.user_id != current_user.id
        render json: { error: "无权操作" }, status: 403
        return
      end
      
      # 检查是否已是商品或已申请
      if work.is_shop_product
        render json: { error: "此作品已上架" }, status: 422
        return
      end
      
      if work.shop_status == 'pending'
        render json: { error: "已提交申请，请等待审核" }, status: 422
        return
      end
      
      # 检查是否符合标准
      standards = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_shop_standards') || {}
      min_likes = standards['min_likes']&.to_i || 0
      min_clicks = standards['min_clicks']&.to_i || 0
      
      if work.likes_count < min_likes
        render json: { error: "点赞数不足#{min_likes}，无法申请" }, status: 422
        return
      end
      
      if work.clicks_count < min_clicks
        render json: { error: "点击数不足#{min_clicks}，无法申请" }, status: 422
        return
      end
      
      work.apply_for_shop!
      render json: { success: true, work: serialize_work(work) }
    end
    
    # GET /qd/center/admin - 管理员后台
    def admin
      # 待审核的作品
      pending_works = MyPluginModule::QdCreatorWork.pending.recent
      
      # 已通过的作品
      approved_works = MyPluginModule::QdCreatorWork.approved.recent.limit(100)
      
      # 待审核的上架申请
      pending_shop_applications = MyPluginModule::QdCreatorWork.where(shop_status: 'pending').recent
      
      # 已审核上架的作品
      approved_shop_works = MyPluginModule::QdCreatorWork.where(is_shop_product: true).recent
      
      # 白名单（需要在stats之前定义）
      whitelist = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_whitelist') || []
      
      # 统计数据
      stats = {
        total_works: MyPluginModule::QdCreatorWork.count,
        approved_works: MyPluginModule::QdCreatorWork.approved.count,
        pending_works: MyPluginModule::QdCreatorWork.pending.count,
        creator_count: whitelist.length,
        shop_product_count: MyPluginModule::QdCreatorWork.where(is_shop_product: true).count
      }
      
      # 上架标准
      shop_standards = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_shop_standards') || {
        'min_likes' => 10,
        'min_clicks' => 50
      }
      
      # 抽成比例
      commission_rate = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_donation_commission_rate') || 0.0
      
      # 热度配置（阈值）
      heat_config = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'heat_config') || {
        'thresholds' => [100, 200, 300, 500]
      }
      
      # 热度规则（计算）
      heat_rules = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'heat_rules') || {
        'like_weight' => 1,
        'click_weight' => 1,
        'paid_coin_threshold' => 100,
        'paid_coin_base_multiplier' => 2,
        'jifen_weight' => 1
      }
      
      # 打赏次数限制
      max_donations_per_work = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_max_donations_per_work') || 0
      
      # 待审核的创作者申请
      pending_applications = MyPluginModule::CreatorApplication.pending.recent.limit(50)
      applications_data = pending_applications.map do |app|
        user = User.find_by(id: app.user_id)
        {
          id: app.id,
          user_id: app.user_id,
          username: user&.username || "未知用户",
          creative_field: app.creative_field,
          creative_experience: app.creative_experience,
          portfolio_images: app.portfolio_images,
          submitted_at: app.submitted_at,
          application_fee: app.application_fee
        }
      end
      
      # 所有创作者列表（白名单用户）
      creators_list = whitelist.map do |username|
        user = User.find_by(username: username)
        if user
          approved_app = MyPluginModule::CreatorApplication.where(user_id: user.id, status: 'approved').order(created_at: :desc).first
          works_count = MyPluginModule::QdCreatorWork.where(user_id: user.id, status: 'approved').count
          {
            user_id: user.id,
            username: user.username,
            approved_at: approved_app&.reviewed_at,
            works_count: works_count
          }
        end
      end.compact
      
      pending_works_data = pending_works.map { |w| serialize_work(w) }
      approved_works_data = approved_works.map { |w| serialize_work(w) }
      pending_shop_data = pending_shop_applications.map { |w| serialize_work(w) }
      approved_shop_data = approved_shop_works.map { |w| serialize_work(w) }
      
      render json: {
        pending_works: pending_works_data,
        approved_works: approved_works_data,
        pending_shop_applications: pending_shop_data,
        approved_shop_works: approved_shop_data,
        pending_applications: applications_data,
        creators_list: creators_list,
        stats: stats,
        shop_standards: shop_standards,
        commission_rate: commission_rate,
        whitelist: whitelist,
        heat_config: heat_config,
        heat_rules: heat_rules,
        max_donations_per_work: max_donations_per_work,
        application_fee: SiteSetting.jifen_creator_application_fee
      }
    end
    
    # POST /qd/center/admin/approve_work - 审核通过作品
    def approve_work
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      work.approve!(current_user)
      render json: { success: true, work: serialize_work(work) }
    end
    
    # POST /qd/center/admin/reject_work - 驳回作品
    def reject_work
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      work.reject!(params[:reason])
      render json: { success: true, work: serialize_work(work) }
    end
    
    # POST /qd/center/admin/update_shop_standards - 更新上架标准
    def update_shop_standards
      standards = {
        'min_likes' => params[:min_likes].to_i,
        'min_clicks' => params[:min_clicks].to_i
      }
      
      PluginStore.set(MyPluginModule::PLUGIN_NAME, 'creator_shop_standards', standards)
      render json: { success: true, standards: standards }
    end
    
    # POST /qd/center/admin/update_commission_rate - 更新抽成比例
    def update_commission_rate
      rate = params[:rate].to_f
      
      if rate < 0 || rate > 100
        render json: { error: "抽成比例必须在0-100之间" }, status: 422
        return
      end
      
      PluginStore.set(MyPluginModule::PLUGIN_NAME, 'creator_donation_commission_rate', rate)
      render json: { success: true, rate: rate }
    end
    
    # POST /qd/center/admin/update_max_donations - 更新打赏次数限制
    def update_max_donations
      max_count = params[:max_count].to_i
      
      if max_count < 0
        render json: { error: "打赏次数限制不能为负数" }, status: 422
        return
      end
      
      PluginStore.set(MyPluginModule::PLUGIN_NAME, 'creator_max_donations_per_work', max_count)
      
      Rails.logger.info "[Creator Admin] 更新打赏次数限制: #{max_count}"
      
      render json: { 
        success: true, 
        max_count: max_count,
        message: max_count > 0 ? "已设置每个用户对单个作品最多打赏 #{max_count} 次" : "已取消打赏次数限制"
      }
    end
    
    # POST /qd/center/admin/approve_shop - 审核通过上架申请
    def approve_shop
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      work.approve_shop!
      render json: { success: true, work: serialize_work(work) }
    end
    
    # POST /qd/center/admin/reject_shop - 驳回上架申请
    def reject_shop
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      work.reject_shop!(params[:reason])
      render json: { success: true, work: serialize_work(work) }
    end
    
    # POST /qd/center/admin/update_work_status - 更新作品状态（已通过的作品）
    def update_work_status
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      new_status = params[:status]
      
      unless ['pending', 'approved', 'rejected'].include?(new_status)
        render json: { error: "无效的状态" }, status: 422
        return
      end
      
      if new_status == 'rejected' && params[:reason].blank?
        render json: { error: "驳回需要填写原因" }, status: 422
        return
      end
      
      case new_status
      when 'pending'
        work.update!(status: 'pending', approved_at: nil, approved_by: nil, rejection_reason: nil)
      when 'approved'
        work.approve!(current_user)
      when 'rejected'
        work.reject!(params[:reason])
      end
      
      render json: { success: true, work: serialize_work(work) }
    end
    
    # DELETE /qd/center/admin/delete_work - 删除作品
    def delete_work
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      work.destroy!
      render json: { success: true, message: "作品已删除" }
    end
    
    # POST /qd/center/admin/update_whitelist - 更新白名单
    def update_whitelist
      usernames = params[:usernames] || []
      
      # 验证用户名是否存在
      valid_usernames = []
      invalid_usernames = []
      
      usernames.each do |username|
        if User.exists?(username: username)
          valid_usernames << username
        else
          invalid_usernames << username
        end
      end
      
      PluginStore.set(MyPluginModule::PLUGIN_NAME, 'creator_whitelist', valid_usernames)
      
      render json: {
        success: true,
        whitelist: valid_usernames,
        invalid_usernames: invalid_usernames
      }
    end
    
    # POST /qd/center/admin/update_heat_config - 更新热度阈值配置
    def update_heat_config
      heat_config = params[:heat_config]
      
      # 验证配置
      unless heat_config['thresholds'] && heat_config['thresholds'].is_a?(Array)
        render json: { error: "配置格式错误" }, status: 422
        return
      end
      
      # 将字符串数组转换为整数数组
      thresholds = heat_config['thresholds'].map { |t| t.to_i }
      
      # 验证阈值递增
      (0...thresholds.length - 1).each do |i|
        if thresholds[i] >= thresholds[i + 1]
          render json: { error: "阈值必须递增" }, status: 422
          return
        end
      end
      
      # 保存时使用整数数组
      saved_config = { 'thresholds' => thresholds }
      PluginStore.set(MyPluginModule::PLUGIN_NAME, 'heat_config', saved_config)
      
      Rails.logger.info "[Creator Admin] 保存热度阈值配置: #{saved_config.inspect}"
      
      # 立即读取验证是否保存成功
      verify_config = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'heat_config')
      Rails.logger.info "[Creator Admin] 验证读取: #{verify_config.inspect}"
      
      if verify_config != saved_config
        Rails.logger.error "[Creator Admin] ⚠️ 保存后验证失败！保存: #{saved_config.inspect}, 读取: #{verify_config.inspect}"
      end
      
      render json: {
        success: true,
        heat_config: saved_config
      }
    end
    
    # POST /qd/center/admin/update_heat_rules - 更新热度规则
    def update_heat_rules
      heat_rules = params[:heat_rules]
      
      # 验证规则
      required_fields = ['like_weight', 'click_weight', 'paid_coin_threshold', 'paid_coin_base_multiplier', 'jifen_weight']
      required_fields.each do |field|
        unless heat_rules[field]
          render json: { error: "缺少必填字段: #{field}" }, status: 422
          return
        end
      end
      
      # 将字符串转换为整数
      saved_rules = {
        'like_weight' => heat_rules['like_weight'].to_i,
        'click_weight' => heat_rules['click_weight'].to_i,
        'paid_coin_threshold' => heat_rules['paid_coin_threshold'].to_i,
        'paid_coin_base_multiplier' => heat_rules['paid_coin_base_multiplier'].to_i,
        'jifen_weight' => heat_rules['jifen_weight'].to_i
      }
      
      # 确保数值合法
      if saved_rules['like_weight'] < 0 || 
         saved_rules['click_weight'] < 0 || 
         saved_rules['paid_coin_threshold'] < 0 || 
         saved_rules['paid_coin_base_multiplier'] < 1 || 
         saved_rules['jifen_weight'] < 0
        render json: { error: "数值不合法" }, status: 422
        return
      end
      
      PluginStore.set(MyPluginModule::PLUGIN_NAME, 'heat_rules', saved_rules)
      
      Rails.logger.info "[Creator Admin] 保存热度规则: #{saved_rules.inspect}"
      
      # 立即读取验证是否保存成功
      verify_rules = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'heat_rules')
      Rails.logger.info "[Creator Admin] 验证读取: #{verify_rules.inspect}"
      
      if verify_rules != saved_rules
        Rails.logger.error "[Creator Admin] ⚠️ 保存后验证失败！保存: #{saved_rules.inspect}, 读取: #{verify_rules.inspect}"
      end
      
      # 重新计算所有作品的热度
      count = 0
      MyPluginModule::QdCreatorWork.approved.find_each do |work|
        work.update_heat!(saved_rules)
        count += 1
      end
      
      Rails.logger.info "[Creator Admin] 已重新计算 #{count} 个作品的热度"
      
      render json: {
        success: true,
        heat_rules: saved_rules,
        message: "热度规则已更新，已重新计算 #{count} 个作品的热度"
      }
    end
    
    # POST /qd/center/admin/recalculate_heat - 重新计算所有作品热度
    def recalculate_heat
      heat_rules = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'heat_rules')
      
      count = 0
      MyPluginModule::QdCreatorWork.find_each do |work|
        work.update_heat!(heat_rules)
        count += 1
      end
      
      render json: {
        success: true,
        message: "已重新计算 #{count} 个作品的热度",
        count: count
      }
    end
    
    # POST /qd/center/admin/approve_application - 审核通过创作者申请
    def approve_application
      application = MyPluginModule::CreatorApplication.find(params[:application_id])
      
      if application.approved?
        render json: { error: "该申请已通过" }, status: 422
        return
      end
      
      if application.rejected?
        render json: { error: "该申请已被拒绝" }, status: 422
        return
      end
      
      begin
        application.approve!(current_user)
        
        Rails.logger.info "[创作者申请] 管理员 #{current_user.username} 通过了用户 #{application.user.username} 的申请"
        
        render json: {
          success: true,
          message: "申请已通过，用户已成为创作者",
          application: {
            id: application.id,
            user_id: application.user_id,
            username: application.user.username,
            status: application.status,
            reviewed_at: application.reviewed_at
          }
        }
      rescue => e
        Rails.logger.error "[创作者申请] 审核通过失败: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { error: "审核失败: #{e.message}" }, status: 500
      end
    end
    
    # POST /qd/center/admin/reject_application - 拒绝创作者申请
    def reject_application
      application = MyPluginModule::CreatorApplication.find(params[:application_id])
      
      if application.approved?
        render json: { error: "该申请已通过，无法拒绝" }, status: 422
        return
      end
      
      if application.rejected?
        render json: { error: "该申请已被拒绝" }, status: 422
        return
      end
      
      reason = params[:reason].to_s.strip
      refund = params[:refund] == true || params[:refund] == "true"
      
      if reason.blank?
        render json: { error: "请填写拒绝理由" }, status: 422
        return
      end
      
      begin
        application.reject!(current_user, reason: reason, refund: refund)
        
        Rails.logger.info "[创作者申请] 管理员 #{current_user.username} 拒绝了用户 #{application.user.username} 的申请，退款: #{refund}"
        
        render json: {
          success: true,
          message: refund ? "申请已拒绝，费用已退还" : "申请已拒绝",
          application: {
            id: application.id,
            user_id: application.user_id,
            username: application.user.username,
            status: application.status,
            reviewed_at: application.reviewed_at,
            rejection_reason: application.rejection_reason,
            fee_refunded: application.fee_refunded
          }
        }
      rescue => e
        Rails.logger.error "[创作者申请] 拒绝申请失败: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { error: "拒绝失败: #{e.message}" }, status: 500
      end
    end
    
    # POST /qd/center/admin/revoke_creator - 撤销创作者资格
    def revoke_creator
      username = params[:username].to_s.strip
      reason = params[:reason].to_s.strip
      
      if username.blank?
        render json: { error: "用户名不能为空" }, status: 422
        return
      end
      
      if reason.blank?
        render json: { error: "请填写撤销理由" }, status: 422
        return
      end
      
      user = User.find_by(username: username)
      unless user
        render json: { error: "用户不存在" }, status: 404
        return
      end
      
      begin
        ActiveRecord::Base.transaction do
          # 1. 从白名单中移除
          whitelist = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_whitelist') || []
          whitelist.delete(username)
          PluginStore.set(MyPluginModule::PLUGIN_NAME, 'creator_whitelist', whitelist)
          
          # 2. 移除创作者权限
          user.custom_fields["is_creator"] = nil
          user.save_custom_fields(true)
          
          # 3. 删除该用户的所有申请记录
          MyPluginModule::CreatorApplication.where(user_id: user.id).destroy_all
          
          # 4. 发送系统通知
          PostCreator.create!(
            Discourse.system_user,
            title: "创作者资格已被撤销",
            raw: "您的创作者资格已被管理员撤销。\n\n撤销理由：#{reason}\n\n操作人员：@#{current_user.username}\n操作时间：#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}\n\n如有疑问，请联系管理员。",
            archetype: Archetype.private_message,
            target_usernames: [username],
            skip_validations: true
          )
          
          Rails.logger.info "[创作者管理] 管理员 #{current_user.username} 撤销了用户 #{username} 的创作者资格，理由: #{reason}"
        end
        
        render json: {
          success: true,
          message: "已撤销 #{username} 的创作者资格"
        }
      rescue => e
        Rails.logger.error "[创作者管理] 撤销资格失败: #{e.message}\n#{e.backtrace.join("\n")}"
        render json: { error: "撤销失败: #{e.message}" }, status: 500
      end
    end
    
    # GET /qd/center/work/:id - 作品详情页（简化版）
    def work_detail
      Rails.logger.info "[作品详情] 开始加载作品ID: #{params[:id]}"
      
      # 直接从数据库查询作品
      work = MyPluginModule::QdCreatorWork.find_by(id: params[:id])
      
      unless work
        Rails.logger.warn "[作品详情] 作品不存在: #{params[:id]}"
        render json: { error: "作品不存在" }, status: 404
        return
      end
      
      Rails.logger.info "[作品详情] 找到作品: ID=#{work.id}, status=#{work.status}"
      
      # 只显示已通过的作品
      unless work.status == 'approved'
        Rails.logger.warn "[作品详情] 作品未审核通过: #{params[:id]}"
        render json: { error: "作品未通过审核" }, status: 404
        return
      end
      
        # 不在这里记录点击，只在用户点击"查看原帖"时记录
      
      # 获取创作者信息
      creator = User.find_by(id: work.user_id)
      unless creator
        Rails.logger.error "[作品详情] 找不到创作者: user_id=#{work.user_id}"
        render json: { error: "创作者信息异常" }, status: 500
        return
      end
      
      # 检查当前用户是否已点赞
      is_liked = false
      user_donation_count = 0
      
      if current_user
        is_liked = MyPluginModule::QdCreatorWorkLike.exists?(
          work_id: work.id,
          user_id: current_user.id
        )
        
        user_donation_count = MyPluginModule::QdCreatorDonation.where(
          work_id: work.id,
          donor_id: current_user.id
        ).count
      end
      
      # 获取用户余额（带异常处理）
      user_jifen = 0
      user_paid_coin = 0
      
      if current_user
        begin
          user_jifen = MyPluginModule::JifenService.available_total_points(current_user)
          user_paid_coin = MyPluginModule::PaidCoinService.available_coins(current_user)
        rescue => e
          Rails.logger.warn "[作品详情] 获取用户余额失败: #{e.message}"
        end
      end
      
      # 获取配置
      max_donations_per_work = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_max_donations_per_work')&.to_i || 0
      commission_rate = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_donation_commission_rate')&.to_f || 0.0
      
      Rails.logger.info "[作品详情] 成功加载作品 #{work.id}"
      
      render json: {
        work: {
          id: work.id,
          user_id: work.user_id,
          title: work.title || "作品 ##{work.id}",
          image_url: work.image_url,
          post_url: work.post_url,
          likes_count: work.likes_count || 0,
          clicks_count: work.clicks_count || 0,
          is_liked: is_liked,
          user_donation_count: user_donation_count
        },
        creator: {
          id: creator.id,
          username: creator.username,
          avatar_url: creator.avatar_template.gsub('{size}', '120')
        },
        user_jifen: user_jifen,
        user_paid_coin: user_paid_coin,
        jifen_name: "积分",
        paid_coin_name: SiteSetting.jifen_paid_coin_name || "付费币",
        max_donations_per_work: max_donations_per_work,
        commission_rate: commission_rate
      }
    rescue => e
      Rails.logger.error "[作品详情] 严重错误: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { 
        error: "加载失败", 
        message: e.message,
        work_id: params[:id]
      }, status: 500
    end
    
    # POST /qd/center/toggle_like - 切换点赞状态
    def toggle_like
      work = MyPluginModule::QdCreatorWork.find(params[:work_id])
      
      # 检查是否已点赞
      like = MyPluginModule::QdCreatorWorkLike.find_by(
        work_id: work.id,
        user_id: current_user.id
      )
      
      if like
        # 取消点赞
        like.destroy!
        work.decrement!(:likes_count)
        is_liked = false
      else
        # 点赞
        MyPluginModule::QdCreatorWorkLike.create!(
          work_id: work.id,
          user_id: current_user.id
        )
        work.increment!(:likes_count)
        is_liked = true
      end
      
      # 重新计算热度
      work.calculate_and_update_heat!
      
      render json: {
        success: true,
        is_liked: is_liked,
        likes_count: work.likes_count,
        heat_value: work.heat_value
      }
    rescue => e
      Rails.logger.error "[创作者中心] 切换点赞失败: #{e.message}"
      render json: { error: "操作失败: #{e.message}" }, status: 500
    end
    
    private
    
    def ensure_creator_whitelist
      whitelist_usernames = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_whitelist') || []
      
      Rails.logger.info "[创作者白名单检查] 当前用户: #{current_user.username}, 白名单: #{whitelist_usernames.inspect}"
      
      unless current_user.admin? || whitelist_usernames.include?(current_user.username)
        Rails.logger.warn "[创作者白名单检查] 用户 #{current_user.username} 不在白名单中，拒绝访问"
        render json: { error: "您没有权限访问创作者中心，需要加入白名单" }, status: 403
      end
    end
    
    def serialize_work(work)
      # 计算打赏统计（按货币类型）
      donations = MyPluginModule::QdCreatorDonation.where(work_id: work.id)
      jifen_received = donations.where(currency_type: 'jifen').sum(:creator_received)
      paid_coin_received = donations.where(currency_type: 'paid_coin').sum(:creator_received)
      
      {
        id: work.id,
        user_id: work.user_id,
        username: work.user.username,
        title: work.title,
        image_url: work.image_url,
        post_url: work.post_url,
        likes_count: work.likes_count,
        clicks_count: work.clicks_count,
        heat_score: work.heat_score || 0,
        heat_value: work.heat_value || 0,
        heat_color: work.heat_color || '#95DE64',
        status: work.status,
        shop_status: work.shop_status,
        is_shop_product: work.is_shop_product,
        total_donations: work.total_donations,
        total_received: work.total_creator_received,
        jifen_received: jifen_received,
        paid_coin_received: paid_coin_received,
        created_at: work.created_at,
        approved_at: work.approved_at,
        rejection_reason: work.rejection_reason
      }
    end
  end
end
