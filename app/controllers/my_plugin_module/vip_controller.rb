# frozen_string_literal: true

module MyPluginModule
  class VipController < ::ApplicationController
    requires_plugin MyPluginModule::PLUGIN_NAME
    
    before_action :ensure_logged_in, only: [:index, :purchase]
    before_action :ensure_admin, only: [:admin, :create_package, :update_package, :delete_package, :admin_users, :update_user_vip, :cancel_user_vip]
    
    # 用户VIP购买页面
    def index
      packages = MyPluginModule::QdVipPackage.active.ordered.map do |pkg|
        # 获取定价方案，确保返回数组
        pricing_plans_list = pkg.pricing_plans_list || []
        
        # 记录日志便于调试
        Rails.logger.info "[VIP] 套餐 #{pkg.name} (ID: #{pkg.id}) pricing_plans: #{pkg.pricing_plans.inspect}"
        Rails.logger.info "[VIP] 套餐 #{pkg.name} pricing_plans_list: #{pricing_plans_list.inspect}"
        
        {
          id: pkg.id,
          name: pkg.name,
          level: pkg.level,
          description: pkg.description,
          pricing_plans: pricing_plans_list,      # 新增：多定价方案（确保是数组）
          duration_days: pkg.duration_days,       # 向后兼容
          duration_type: pkg.duration_type,       # 向后兼容
          duration_label: pkg.duration_label,     # 向后兼容
          price: pkg.price,                       # 向后兼容
          rewards: pkg.rewards || {},
          sort_order: pkg.sort_order
        }
      end

    def cancel_user_vip
      ensure_admin
      user = User.find_by(id: params[:user_id])
      return render json: { error: "用户不存在" }, status: 404 unless user

      revoked_cards = 0
      revoked_items = []
      cancelled_vip_info = []
      
      ActiveRecord::Base.transaction do
        subs = MyPluginModule::QdVipSubscription.where(user_id: user.id).includes(:package)

        if subs.blank?
          return render json: { error: "该用户没有VIP记录" }, status: 404
        end

        subs.each do |sub|
          package = sub.package
          if package
            # 记录被取消的VIP信息
            cancelled_vip_info << "VIP #{package.level} (#{package.name})"
            
            if package.avatar_frame_id.present?
              DecorationGrant.where(
                user_id: user.id,
                decoration_type: "avatar_frame",
                decoration_id: package.avatar_frame_id
              ).update_all(revoked: true, revoked_at: Time.current, revoked_by_user_id: Discourse.system_user.id)

              if user.custom_fields["avatar_frame_id"].to_i == package.avatar_frame_id
                user.custom_fields["avatar_frame_id"] = nil
              end
              revoked_items << "专属头像框"
            end

            if package.badge_id.present?
              DecorationGrant.where(
                user_id: user.id,
                decoration_type: "badge",
                decoration_id: package.badge_id
              ).update_all(revoked: true, revoked_at: Time.current, revoked_by_user_id: Discourse.system_user.id)

              if user.custom_fields["decoration_badge_id"].to_i == package.badge_id
                user.custom_fields["decoration_badge_id"] = nil
              end
              revoked_items << "专属勋章"
            end

            if package.makeup_cards_count > 0
              revoked_cards += package.makeup_cards_count.to_i
              revoked_items << "#{package.makeup_cards_count}张补签卡"
            end
          end
        end

        # 删除所有VIP记录（包括历史）
        MyPluginModule::QdVipSubscription.where(user_id: user.id).delete_all

        if revoked_cards > 0
          current_cards = user.custom_fields["jifen_makeup_cards"].to_i
          user.custom_fields["jifen_makeup_cards"] = current_cards - revoked_cards
        end
        user.save_custom_fields(true)
      end

      # 发送站内通知（精简版）
      begin
        user.notifications.create!(
          notification_type: Notification.types[:custom],
          data: {
            message: "您的VIP已被管理员取消",
            display_username: "系统消息",
            topic_title: "VIP取消通知"
          }.to_json
        )
      rescue => e
        Rails.logger.warn "[VIP Admin] 取消VIP通知发送失败: #{e.message}"
      end
      
      # 发送私信（详细信息）
      begin
        revoked_items_text = revoked_items.any? ? "\n\n**已回收内容：**\n#{revoked_items.map { |item| "• #{item}" }.join("\n")}" : ""
        
        PostCreator.create!(
          Discourse.system_user,
          title: "⚠️ VIP取消通知",
          raw: <<~MSG,
            您好 @#{user.username}，
            
            您的VIP会员已被管理员取消。
            
            **取消详情：**
            • 已取消VIP：#{cancelled_vip_info.join(', ')}
            • 取消时间：#{Time.current.strftime('%Y年%m月%d日 %H:%M')}#{revoked_items_text}
            
            如有疑问，请联系管理员了解详情。
            
            ---
            *此为自动发送的系统消息*
          MSG
          archetype: Archetype.private_message,
          target_usernames: [user.username],
          skip_validations: true
        )
        
        Rails.logger.info "📧 已向用户#{user.username}发送VIP取消私信"
      rescue => e
        Rails.logger.warn "[VIP Admin] 发送取消VIP私信失败: #{e.message}"
      end

      render json: { success: true, message: "已取消该用户VIP", revoked_cards: revoked_cards }
    rescue => e
      Rails.logger.error "[VIP Admin] 取消用户VIP失败: #{e.message}"
      render json: { error: e.message }, status: 500
    end

    # 管理员：分页获取当前VIP用户（每页50）
    def admin_users
      ensure_admin
      page = params[:page].to_i
      page = 1 if page <= 0
      per = 50
      offset = (page - 1) * per

      total = MyPluginModule::QdVipSubscription.active.select(:user_id).distinct.count

      subs = MyPluginModule::QdVipSubscription
        .active
        .select('DISTINCT ON (user_id) *')
        .order('user_id, vip_level DESC, expires_at DESC')
        .offset(offset)
        .limit(per)
        .includes(:user, :package)

      users = subs.map do |sub|
        u = sub.user
        {
          user_id: u.id,
          username: u.username,
          avatar_template: u.avatar_template,
          vip_level: sub.vip_level,
          package_name: sub.package&.name,
          expires_at: sub.expires_at,
          days_remaining: sub.days_remaining
        }
      end

      render json: {
        users: users,
        meta: {
          page: page,
          per: per,
          total: total,
          total_pages: (total.to_f / per).ceil
        }
      }
    rescue => e
      Rails.logger.error "[VIP Admin] 加载VIP用户列表失败: #{e.message}"
      render json: { error: e.message, users: [], meta: { page: 1, per: 50, total: 0, total_pages: 0 } }, status: 500
    end

    # 管理员：更新指定用户的VIP等级与到期时间
    def update_user_vip
      ensure_admin
      user = User.find_by(id: params[:user_id])
      return render json: { error: '用户不存在' }, status: 404 unless user

      vip_level = params[:vip_level].to_i
      expires_at_str = params[:expires_at]
      return render json: { error: '参数不完整' }, status: 400 if vip_level <= 0 || expires_at_str.blank?

      expires_at = Time.zone.parse(expires_at_str) rescue nil
      return render json: { error: '到期时间无效' }, status: 400 unless expires_at
      return render json: { error: '到期时间必须晚于当前时间' }, status: 400 if expires_at <= Time.current

      package = MyPluginModule::QdVipPackage.active.by_level(vip_level).ordered.first
      return render json: { error: "未找到VIP#{vip_level}的有效套餐，请先在套餐管理创建并启用" }, status: 400 unless package

      existing = MyPluginModule::QdVipSubscription.current_vip_for(user)
      if existing && vip_level < existing.vip_level
        return render json: { error: "不支持将用户降级（当前VIP#{existing.vip_level} -> 目标VIP#{vip_level}）" }, status: 400
      end

      started_at = Time.current
      duration_days = ((expires_at - started_at) / 1.day).ceil
      return render json: { error: '到期时间与现在的差值不足1天' }, status: 400 if duration_days <= 0

      ActiveRecord::Base.transaction do
        # 关闭用户当前有效的同等级订阅
        if existing && existing.vip_level == vip_level
          existing.update!(status: 'expired')
        end

        sub = MyPluginModule::QdVipSubscription.create!(
          user_id: user.id,
          package_id: package.id,
          vip_level: vip_level,
          duration_days: duration_days,
          duration_type: package.duration_type,
          price_paid: 0,
          started_at: started_at,
          expires_at: expires_at,
          status: 'active'
        )

        render json: {
          success: true,
          message: '用户VIP已更新',
          user: {
            user_id: user.id,
            username: user.username,
            vip_level: sub.vip_level,
            expires_at: sub.expires_at,
            days_remaining: sub.days_remaining
          }
        }
      end
    rescue => e
      Rails.logger.error "[VIP Admin] 更新用户VIP失败: #{e.message}"
      render json: { error: e.message }, status: 500
    end
      
      # 获取用户当前VIP信息
      current_vip = MyPluginModule::QdVipSubscription.current_vip_for(current_user)
      vip_info = if current_vip
        {
          level: current_vip.vip_level,
          expires_at: current_vip.expires_at,
          days_remaining: current_vip.days_remaining,
          package_name: current_vip.package.name,
          price_paid: current_vip.price_paid,
          duration_days: current_vip.duration_days,
          duration_type: current_vip.duration_type
        }
      else
        nil
      end
      
      render json: {
        packages: packages,
        current_vip: vip_info,
        user_paid_coins: MyPluginModule::PaidCoinService.available_coins(current_user),
        paid_coin_name: SiteSetting.jifen_paid_coin_name
      }
    end
    
    # 购买VIP
    def purchase
      ensure_logged_in
      
      package_id = params[:package_id]
      duration_type = params[:duration_type] # 新增：用户选择的时长类型
      
      package = MyPluginModule::QdVipPackage.find_by(id: package_id, is_active: true)
      
      unless package
        render json: { error: "套餐不存在或已下架" }, status: 404
        return
      end
      
      # 获取用户选择的定价方案
      unless duration_type.present?
        render json: { error: "请选择购买时长" }, status: 400
        return
      end
      
      # 使用经过清洗的定价方案，过滤掉不受支持的类型
      available_plans = package.pricing_plans_list || []
      pricing_plan = available_plans.find { |p| p[:type] == duration_type }
      unless pricing_plan
        render json: { error: "选择的时长不可用" }, status: 400
        return
      end
      
      purchase_price = pricing_plan[:price]
      purchase_days = pricing_plan[:days]
      target_daily_price = (purchase_price.to_f / purchase_days.to_f)
      
      begin
        # 计算升级抵扣
        existing_vip = MyPluginModule::QdVipSubscription.current_vip_for(current_user)

        # 不允许降级购买
        if existing_vip && package.level < existing_vip.vip_level
          render json: { error: "不支持降级购买（当前VIP#{existing_vip.vip_level}，目标VIP#{package.level}）" }, status: 400
          return
        end
        upgrade_applied = false
        upgrade_calc = nil
        charge_amount = purchase_price
        new_duration_days = purchase_days
        started_at = Time.current

        if existing_vip
          if existing_vip.vip_level < package.level
            # 升级：按剩余价值抵扣差价，并转换为新套餐的额外天数（仅当未覆盖全额时）
            current_daily_price = existing_vip.duration_days.to_i > 0 ? (existing_vip.price_paid.to_f / existing_vip.duration_days.to_f) : 0.0
            remaining_days = [existing_vip.days_remaining, 0].max
            remaining_value = (remaining_days.to_f * current_daily_price)

            if remaining_value >= purchase_price
              charge_amount = 0
              new_duration_days = purchase_days # 场景2：剩余价值覆盖全额，仅获得目标套餐天数
              extra_days = 0
            else
              charge_amount = (purchase_price - remaining_value).ceil
              extra_days = (remaining_value / target_daily_price).ceil
              new_duration_days = purchase_days + extra_days
            end

            upgrade_applied = true
            upgrade_calc = {
              current_level: existing_vip.vip_level,
              current_days_remaining: remaining_days,
              current_price_paid: existing_vip.price_paid,
              current_duration_days: existing_vip.duration_days,
              current_daily_price: current_daily_price.round(4),
              target_price: purchase_price,
              target_days: purchase_days,
              target_daily_price: target_daily_price.round(4),
              remaining_value: remaining_value.round(2),
              extra_days: extra_days,
              charged_amount: charge_amount,
              rule: remaining_value >= purchase_price ? "residual_covers_full_price" : "partial_residual_with_extra_days"
            }
          elsif existing_vip.vip_level == package.level
            # 同级续费
            new_duration_days = purchase_days
            started_at = Time.current
          end
        end

        # 检查用户付费币余额（按应扣差价）
        user_coins = MyPluginModule::PaidCoinService.available_coins(current_user)
        if user_coins < charge_amount
          render json: {
            error: "付费币不足",
            required: charge_amount,
            current: user_coins
          }, status: 400
          return
        end

        warnings = []

        ActiveRecord::Base.transaction do
          # 扣除付费币（差价可能为0）
          if charge_amount > 0
            MyPluginModule::PaidCoinService.deduct_coins!(
              current_user,
              charge_amount,
              reason: "购买VIP #{package.name} (#{pricing_plan[:label] || duration_type})",
              related_id: package.id,
              related_type: "VipPackage"
            )
          end

          # 计算到期时间
          expires_at = if existing_vip && existing_vip.vip_level == package.level
            # 同级续费：在当前到期时间基础上延长
            existing_vip.expires_at + new_duration_days.days
          else
            # 新购或升级：从现在开始计算
            started_at + new_duration_days.days
          end

          # 创建订阅记录
          subscription = MyPluginModule::QdVipSubscription.create!(
            user_id: current_user.id,
            package_id: package.id,
            vip_level: package.level,
            duration_days: new_duration_days,
            duration_type: duration_type,
            price_paid: charge_amount,
            started_at: started_at,
            expires_at: expires_at,
            status: "active"
          )

          # 如果有旧的同等级VIP，标记为过期
          if existing_vip && existing_vip.id != subscription.id && existing_vip.vip_level == package.level
            existing_vip.update!(status: "expired")
          end

          # 发放奖励（不影响购买成功，失败写入 warnings）
          begin
            grant_vip_rewards(current_user, package, subscription)
          rescue => e
            Rails.logger.warn "[VIP系统] 发放奖励失败但不影响购买: #{e.message}"
            warnings << "发放奖励失败: #{e.message}"
          end

          # 发送系统通知（失败不影响购买）
          begin
            send_vip_notification(current_user, subscription, package, duration_type)
          rescue => e
            Rails.logger.warn "[VIP系统] 发送通知失败但不影响购买: #{e.message}"
            warnings << "发送通知失败: #{e.message}"
          end

          render json: {
            success: true,
            message: "购买成功！",
            charged_amount: charge_amount,
            upgrade_applied: upgrade_applied,
            upgrade_calc: upgrade_calc,
            warnings: warnings,
            subscription: {
              level: subscription.vip_level,
              duration_type: duration_type,
              duration_label: pricing_plan[:label] || duration_type,
              duration_days: new_duration_days,
              price_paid: charge_amount,
              expires_at: subscription.expires_at.strftime('%Y年%m月%d日'),
              days_remaining: subscription.days_remaining
            },
            new_balance: MyPluginModule::PaidCoinService.available_coins(current_user)
          }
        end
      rescue => e
        Rails.logger.error "[VIP系统] 购买失败: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error: "购买失败: #{e.message}" }, status: 500
      end
    end
    
    # 管理后台页面 - 简化版（不加载装饰数据）
    def admin
      ensure_admin
      
      begin
        # 1. 直接从数据库加载套餐
        packages = MyPluginModule::QdVipPackage.order(sort_order: :asc, created_at: :desc).to_a
        Rails.logger.info "[VIP Admin] 从数据库加载 #{packages.count} 个套餐"
        
        # 2. 转换为简单的 Hash 数组（使用 pricing_plans_list 确保格式一致）
        packages_data = packages.map do |pkg|
          pricing_plans = pkg.pricing_plans_list || []
          
          Rails.logger.info "[VIP Admin] 套餐 #{pkg.name} pricing_plans_list: #{pricing_plans.inspect}"
          
          {
            id: pkg.id,
            name: pkg.name,
            level: pkg.level,
            description: pkg.description,
            pricing_plans: pricing_plans,  # 使用经过处理的 pricing_plans_list
            rewards: pkg.rewards || {},
            daily_signin_bonus: pkg.daily_signin_bonus || 0,
            is_active: pkg.is_active,
            sort_order: pkg.sort_order,
            created_at: pkg.created_at,
            updated_at: pkg.updated_at
          }
        end
        
        # 3. 返回数据（不再加载装饰数据）
        response_data = {
          packages: packages_data,
          paid_coin_name: SiteSetting.jifen_paid_coin_name || "付费币"
        }
        
        Rails.logger.info "[VIP Admin] 返回数据: packages=#{packages_data.count}"
        
        render json: response_data
        
      rescue => e
        Rails.logger.error "[VIP Admin] 严重错误: #{e.message}"
        Rails.logger.error e.backtrace[0..10].join("\n")
        render json: { 
          error: "加载失败: #{e.message}",
          packages: [],
          paid_coin_name: "付费币"
        }, status: 500
      end
    end
    
    # 创建套餐
    def create_package
      Rails.logger.info "[VIP系统] 创建套餐 - 接收到的参数: #{params.inspect}"
      
      pkg_params = package_params
      Rails.logger.info "[VIP系统] 处理后的参数: #{pkg_params.inspect}"
      
      package = MyPluginModule::QdVipPackage.new(pkg_params)
      
      if package.save
        render json: {
          success: true,
          message: "套餐创建成功",
          package: package_json(package)
        }
      else
        Rails.logger.error "[VIP系统] 验证失败: #{package.errors.full_messages.join(', ')}"
        render json: { error: package.errors.full_messages.join(", ") }, status: 400
      end
    rescue => e
      Rails.logger.error "[VIP系统] 创建套餐失败: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "创建失败: #{e.message}" }, status: 500
    end
    
    # 更新套餐
    def update_package
      package = MyPluginModule::QdVipPackage.find(params[:id])
      
      if package.update(package_params)
        render json: {
          success: true,
          message: "套餐更新成功",
          package: package_json(package)
        }
      else
        render json: { error: package.errors.full_messages.join(", ") }, status: 400
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: "套餐不存在" }, status: 404
    rescue => e
      Rails.logger.error "[VIP系统] 更新套餐失败: #{e.message}"
      render json: { error: "更新失败: #{e.message}" }, status: 500
    end
    
    # 删除套餐
    def delete_package
      package = MyPluginModule::QdVipPackage.find(params[:id])
      
      # 检查是否有活跃订阅
      active_subs = MyPluginModule::QdVipSubscription.active.where(package_id: package.id).count
      if active_subs > 0
        return render json: { error: "该套餐仍有#{active_subs}个活跃订阅，无法删除" }, status: 400
      end
      
      package.destroy!
      render json: { success: true, message: "套餐已删除" }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "套餐不存在" }, status: 404
    rescue => e
      Rails.logger.error "[VIP系统] 删除套餐失败: #{e.message}"
      render json: { error: "删除失败: #{e.message}" }, status: 500
    end
    
    # 获取用户VIP历史
    def user_subscriptions
      subscriptions = MyPluginModule::QdVipSubscription
        .where(user_id: current_user.id)
        .includes(:package)
        .order(created_at: :desc)
        .limit(20)
        .map do |sub|
          {
            id: sub.id,
            package_name: sub.package.name,
            vip_level: sub.vip_level,
            price_paid: sub.price_paid,
            started_at: sub.started_at,
            expires_at: sub.expires_at,
            status: sub.status,
            days_remaining: sub.days_remaining
          }
        end
      
      render json: { subscriptions: subscriptions }
    end
    
    private
    
    def package_params
      rewards = {}
      rewards["makeup_cards"] = params[:makeup_cards].to_i if params[:makeup_cards].present?
      
      # 处理头像框ID（0表示不赠送，大于0才添加）
      if params[:avatar_frame_id].present?
        frame_id = params[:avatar_frame_id].to_i
        rewards["avatar_frame_id"] = frame_id if frame_id > 0
      end
      
      # 处理勋章ID（0表示不赠送，大于0才添加）
      if params[:badge_id].present?
        badge_id = params[:badge_id].to_i
        rewards["badge_id"] = badge_id if badge_id > 0
      end
      
      # 处理定价方案
      Rails.logger.info "[VIP系统] 接收到的 pricing_plans 参数: #{params[:pricing_plans].inspect}"
      
      pricing_plans = []
      if params[:pricing_plans].present? && params[:pricing_plans].is_a?(Array)
        pricing_plans = params[:pricing_plans].map do |plan|
          {
            "type" => plan[:type] || plan["type"],
            "days" => (plan[:days] || plan["days"]).to_i,
            "price" => (plan[:price] || plan["price"]).to_i
          }
        end
        Rails.logger.info "[VIP系统] 处理后的 pricing_plans: #{pricing_plans.inspect}"
      else
        Rails.logger.warn "[VIP系统] pricing_plans 参数无效或为空！"
      end
      
      {
        name: params[:name],
        level: params[:level].to_i,
        description: params[:description],
        pricing_plans: pricing_plans,
        duration_days: params[:duration_days].to_i,  # 向后兼容
        duration_type: params[:duration_type],        # 向后兼容
        price: params[:price].to_i,                   # 向后兼容
        rewards: rewards,
        daily_signin_bonus: params[:daily_signin_bonus].to_i,
        is_active: params[:is_active].nil? ? true : params[:is_active],
        sort_order: params[:sort_order].to_i
      }
    end
    
    def package_json(package)
      # 使用 pricing_plans_list 确保返回格式正确的数组
      pricing_plans = package.pricing_plans_list || []
      
      # 记录日志以便调试
      Rails.logger.info "[VIP] package_json - 套餐 #{package.name} pricing_plans_list: #{pricing_plans.inspect}"
      
      {
        id: package.id,
        name: package.name,
        level: package.level,
        description: package.description,
        pricing_plans: pricing_plans,  # 使用经过处理的 pricing_plans_list
        rewards: package.rewards || {},
        daily_signin_bonus: package.daily_signin_bonus || 0,
        is_active: package.is_active,
        sort_order: package.sort_order,
        created_at: package.created_at,
        updated_at: package.updated_at
      }
    end
    
    # 发放VIP奖励
    def grant_vip_rewards(user, package, subscription)
      # 补签卡（永久有效）
      if package.makeup_cards_count > 0
        current_cards = user.custom_fields["jifen_makeup_cards"].to_i
        user.custom_fields["jifen_makeup_cards"] = current_cards + package.makeup_cards_count
        user.save_custom_fields(true)
      end
      
      # 头像框（与VIP时长一致）
      if package.avatar_frame_id.present?
        # 检查是否已有该头像框的授予记录
        existing_grant = DecorationGrant.find_by(
          user_id: user.id,
          decoration_type: "avatar_frame",
          decoration_id: package.avatar_frame_id
        )
        
        if existing_grant
          # 如果已存在，延长到新的过期时间（如果新时间更晚）
          if existing_grant.expires_at.nil? || subscription.expires_at > existing_grant.expires_at
            existing_grant.update!(expires_at: subscription.expires_at)
          end
        else
          # 创建新的授予记录
          DecorationGrant.create!(
            user_id: user.id,
            decoration_type: "avatar_frame",
            decoration_id: package.avatar_frame_id,
            granted_by_user_id: Discourse.system_user.id,
            granted_at: Time.current,
            expires_at: subscription.expires_at # 与VIP到期时间一致
          )
        end
      end
      
      # 勋章（与VIP时长一致）
      if package.badge_id.present?
        # 检查是否已有该勋章的授予记录
        existing_grant = DecorationGrant.find_by(
          user_id: user.id,
          decoration_type: "badge",
          decoration_id: package.badge_id
        )
        
        if existing_grant
          # 如果已存在，延长到新的过期时间（如果新时间更晚）
          if existing_grant.expires_at.nil? || subscription.expires_at > existing_grant.expires_at
            existing_grant.update!(expires_at: subscription.expires_at)
          end
        else
          # 创建新的授予记录
          DecorationGrant.create!(
            user_id: user.id,
            decoration_type: "badge",
            decoration_id: package.badge_id,
            granted_by_user_id: Discourse.system_user.id,
            granted_at: Time.current,
            expires_at: subscription.expires_at # 与VIP到期时间一致
          )
        end
      end
    end
    
    # 加载头像框列表（用于给用户赠送）
    def load_decoration_frames
      frames_data = PluginStore.get(MyPluginModule::PLUGIN_NAME, "avatar_frames") || {}
      frames_data.values.map do |frame|
        {
          id: frame["id"],
          name: frame["name"],
          image: frame["image"]
        }
      end
    end
    
    # 加载勋章列表（用于给用户赠送）
    def load_decoration_badges
      badges_data = PluginStore.get(MyPluginModule::PLUGIN_NAME, "decoration_badges") || {}
      badges_data.values.map do |badge|
        {
          id: badge["id"],
          name: badge["name"],
          type: badge["type"],
          image: badge["image"],
          text: badge["text"]
        }
      end
    end
    
    # 加载所有头像框列表（用于管理后台选择）
    def load_all_decoration_frames
      frames = []
      PluginStoreRow.where(plugin_name: MyPluginModule::PLUGIN_NAME)
        .where("key LIKE ?", "decoration_avatar_frame_%")
        .each do |row|
          begin
            frame_data = JSON.parse(row.value)
            frames << {
              id: frame_data["id"],
              name: frame_data["name"] || "头像框 ##{frame_data['id']}",
              image: frame_data["image"]
            }
          rescue => e
            Rails.logger.error "[VIP系统] 解析头像框数据失败: #{e.message}"
          end
        end
      frames.sort_by { |f| f[:id] }
    end
    
    # 加载所有勋章列表（用于管理后台选择）
    def load_all_decoration_badges
      badges = []
      PluginStoreRow.where(plugin_name: MyPluginModule::PLUGIN_NAME)
        .where("key LIKE ?", "decoration_badge_%")
        .each do |row|
          begin
            badge_data = JSON.parse(row.value)
            result = {
              id: badge_data["id"],
              name: badge_data["name"] || "勋章 ##{badge_data['id']}",
              type: badge_data["type"]
            }
            
            # 根据类型添加对应字段
            if badge_data["type"] == "text"
              result[:text] = badge_data["text"]
              result[:style] = "color: #{badge_data['color']}; font-size: #{badge_data['size']}px; background: #{badge_data['background']}; padding: 4px 12px; border-radius: 12px;"
            else
              result[:image] = badge_data["image"]
            end
            
            badges << result
          rescue => e
            Rails.logger.error "[VIP系统] 解析勋章数据失败: #{e.message}"
          end
        end
      badges.sort_by { |b| b[:id] }
    end
    
    # 发送VIP购买通知
    def send_vip_notification(user, subscription, package, duration_type = nil)
      # 获取时长标签
      duration_label = if duration_type
        MyPluginModule::QdVipPackage::DURATION_TYPES.dig(duration_type, :label) || duration_type
      else
        "#{subscription.duration_days}天"
      end
      
      # 构建奖励内容文本
      rewards_text = []
      rewards_text << "#{package.makeup_cards_count}张补签卡" if package.makeup_cards_count > 0
      rewards_text << "专属头像框" if package.avatar_frame_id.present?
      rewards_text << "专属勋章" if package.badge_id.present?
      
      rewards_description = rewards_text.any? ? "\n\n**赠送内容：**\n#{rewards_text.map { |r| "• #{r}" }.join("\n")}" : ""
      
      # 创建系统通知
      user.notifications.create!(
        notification_type: Notification.types[:custom],
        data: {
          message: "恭喜您成功开通 #{package.name} (#{duration_label})！",
          display_username: "系统消息",
          topic_title: "VIP购买成功"
        }.to_json
      )
      
      # 发送私信（可选）
      begin
        PostCreator.create!(
          Discourse.system_user,
          title: "🎉 VIP购买成功通知",
          raw: <<~MSG,
            您好 @#{user.username}，
            
            恭喜您成功购买 **#{package.name}**！
            
            **VIP详情：**
            • VIP等级：VIP #{subscription.vip_level}
            • 开通时间：#{subscription.started_at.strftime('%Y年%m月%d日 %H:%M')}
            • 到期时间：#{subscription.expires_at.strftime('%Y年%m月%d日 %H:%M')}
            • 有效期：#{subscription.days_remaining} 天#{rewards_description}
            
            感谢您的支持！祝您使用愉快！
            
            ---
            *如有疑问，请联系管理员*
          MSG
          archetype: Archetype.private_message,
          target_usernames: [user.username],
          skip_validations: true
        )
      rescue => e
        Rails.logger.warn "[VIP系统] 发送私信失败: #{e.message}"
      end
    end
  end
end
