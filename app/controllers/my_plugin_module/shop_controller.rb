class MyPluginModule::ShopController < ApplicationController
  requires_login
  
  def index
    render json: { status: "success" }
  end
  
  def products
    begin
      if ActiveRecord::Base.connection.table_exists?('qd_shop_products')
        products = MyPluginModule::ShopProduct.order(:sort_order, :id).map do |product|
          product_data = {
            id: product.id,
            name: product.name,
            description: product.description,
            icon_class: product.icon_class,
            price: product.price,
            stock: product.stock,
            stock_status: product.stock > 0 ? "库存充足" : "暂时缺货",
            available: product.stock > 0,
            currency_type: product.currency_type || "points",
            tag: product.tag,
            sales_count: 0,
            sort_order: product.sort_order,
            created_at: product.created_at,
            # 合作商品字段
            is_partnership: product.is_partnership || false
          }
          
          # 如果是合作商品，添加完整的合作配置字段
          if product.is_partnership
            product_data.merge!(
              partner_username: product.partner_username,
              partnership_category: product.partnership_category,
              related_post_url: product.related_post_url,
              commission_rate: product.commission_rate || 0,
              decoration_frame_id: product.decoration_frame_id,
              decoration_badge_id: product.decoration_badge_id,
              virtual_email_template: product.virtual_email_template,
              virtual_address_template: product.virtual_address_template
            )
          end
          
          product_data
        end
        
        render json: {
          status: "success",
          products: products,
          user_points: MyPluginModule::JifenService.available_total_points(current_user),
          user_paid_coins: MyPluginModule::PaidCoinService.available_coins(current_user),
          paid_coin_name: SiteSetting.jifen_paid_coin_name,
          exchange_ratio: SiteSetting.jifen_paid_coin_to_points_ratio,
          is_admin: current_user&.admin? || false
        }
      else
        # 使用模拟数据
        mock_products = [
          {
            id: 1,
            name: "VIP会员",
            description: "享受30天VIP特权，无广告浏览",
            icon_class: "fa-solid fa-bolt",
            price: 500,
            stock: 999,
            stock_status: "库存充足",
            available: true,
            sales_count: 0,
            sort_order: 1
          },
          {
            id: 2,
            name: "专属头像框",
            description: "炫酷的金色头像框，彰显身份",
            icon_class: "fa-solid fa-broom",
            price: 200,
            stock: 50,
            stock_status: "库存充足",
            available: true,
            sales_count: 0,
            sort_order: 2
          },
          {
            id: 3,
            name: "积分宝箱",
            description: "随机获得50-200积分奖励",
            icon_class: "fa-solid fa-gem",
            price: 80,
            stock: 100,
            stock_status: "库存充足",
            available: true,
            sales_count: 0,
            sort_order: 3
          }
        ]
        
        render json: {
          status: "success",
          products: mock_products,
          user_points: current_user.custom_fields["jifen_points"]&.to_i || 0,
          is_admin: current_user&.admin? || false
        }
      end
    rescue => e
      Rails.logger.error "获取商品列表失败: #{e.message}"
      render json: {
        status: "error",
        message: "获取商品列表失败: #{e.message}"
      }, status: 500
    end
  end
  
  def purchase
    ensure_logged_in
    
    begin
      product_id = params[:product_id]&.to_i
      quantity = params[:quantity]&.to_i || 1
      notes = params[:notes] || ""
      user_email = params[:user_email].to_s.strip
      user_address = params[:user_address].to_s.strip
      
      if product_id.blank? || quantity <= 0
        render json: {
          status: "error",
          message: "参数错误"
        }, status: 422
        return
      end
      
      # 使用积分服务获取可用积分
      current_points = MyPluginModule::JifenService.available_total_points(current_user)
      
      if ActiveRecord::Base.connection.table_exists?('qd_shop_products')
        # 使用数据库事务和行锁防止并发问题
        ActiveRecord::Base.transaction do
          product = MyPluginModule::ShopProduct.lock.find_by(id: product_id)
          
          unless product
            render json: {
              status: "error",
              message: "商品不存在"
            }, status: 404
            return
          end
          
          total_price = product.price * quantity
          currency_type = product.currency_type || "points"
          
          # 根据货币类型检查余额
          if currency_type == "paid_coins"
            current_balance = MyPluginModule::PaidCoinService.available_coins(current_user)
            currency_name = SiteSetting.jifen_paid_coin_name
            
            if current_balance < total_price
              render json: {
                status: "error",
                message: "#{currency_name}不足！当前余额：#{current_balance}，需要：#{total_price}"
              }, status: 422
              return
            end
          else
            current_balance = MyPluginModule::JifenService.available_total_points(current_user)
            currency_name = "积分"
            
            if current_balance < total_price
              render json: {
                status: "error",
                message: "积分不足！当前积分：#{current_balance}，需要：#{total_price}"
              }, status: 422
              return
            end
          end
          
          if product.stock < quantity
            render json: {
              status: "error",
              message: "库存不足！剩余库存：#{product.stock}"
            }, status: 422
            return
          end
          
          # 根据货币类型扣除余额
          if currency_type == "paid_coins"
            MyPluginModule::PaidCoinService.deduct_coins!(
              current_user,
              total_price,
              reason: "购买商品：#{product.name}"
            )
            new_balance = MyPluginModule::PaidCoinService.available_coins(current_user)
          else
            MyPluginModule::JifenService.adjust_points!(
              current_user, 
              current_user, 
              -total_price
            )
            new_balance = MyPluginModule::JifenService.available_total_points(current_user)
          end
          
          # 更新库存
          product.update!(stock: product.stock - quantity)
        
          # 处理用户备注
          user_note = params[:user_note].to_s.strip
          final_product_name = user_note.present? ? "#{product.name} >> #{user_note}" : product.name
          
          # 创建订单记录
          order = nil
          if ActiveRecord::Base.connection.table_exists?('qd_shop_orders')
            order = MyPluginModule::ShopOrder.create!(
              user_id: current_user.id,
              product_id: product.id,
              product_name: final_product_name,
              quantity: quantity,
              unit_price: product.price,
              total_price: total_price,
              currency_type: currency_type,
              status: "pending",
              notes: "",
              user_email: user_email.presence,
              user_address: user_address.presence
            )
          end
          
          # 处理合作商品特殊逻辑
          if product.partnership?
            handle_partnership_purchase(product, current_user, quantity, total_price, order)
          end
          
          Rails.logger.info "🛒 用户#{current_user.username} 购买商品: #{product.name} x#{quantity}, 花费#{total_price}#{currency_name}, 订单号: #{order&.id}"
          
          render json: {
            status: "success",
            message: "购买成功！订单已提交，等待处理。",
            data: {
              order_id: order&.id,
              product_name: product.name,
              quantity: quantity,
              total_price: total_price,
              currency_type: currency_type,
              remaining_balance: new_balance,
              order_status: "pending"
            }
          }
        end
      else
        # 模拟购买（仅扣除积分）
        mock_products = {
          1 => { name: "VIP会员", price: 500 },
          2 => { name: "专属头像框", price: 200 },
          3 => { name: "积分宝箱", price: 80 }
        }
        
        product = mock_products[product_id]
        unless product
          render json: {
            status: "error",
            message: "商品不存在"
          }, status: 404
          return
        end
        
        total_price = product[:price] * quantity
        
        if current_points < total_price
          render json: {
            status: "error",
            message: "积分不足！当前积分：#{current_points}，需要：#{total_price}"
          }, status: 422
          return
        end
        
        # 使用积分服务扣除积分（模拟购买）
        MyPluginModule::JifenService.adjust_points!(
          current_user, 
          current_user, 
          -total_price
        )
        new_points = MyPluginModule::JifenService.available_total_points(current_user)
        

        
        render json: {
          status: "success",
          message: "购买成功！",
          data: {
            product_name: product[:name],
            quantity: quantity,
            total_price: total_price,
            remaining_points: new_points
          }
        }
      end
      
    rescue => e
      Rails.logger.error "购买失败: #{e.message}"
      render json: {
        status: "error",
        message: "购买失败: #{e.message}"
      }, status: 500
    end
  end
  
  def orders
    ensure_logged_in
    
    begin
      if ActiveRecord::Base.connection.table_exists?('qd_shop_orders')
        orders = MyPluginModule::ShopOrder.where(user_id: current_user.id)
                                         .order(created_at: :desc)
                                         .limit(50)
                                         .map do |order|
          {
            id: order.id,
            product_name: order.product_name,
            product_description: order.product_description,
            product_icon: order.product_icon,
            quantity: order.quantity,
            unit_price: order.unit_price,
            total_price: order.total_price,
            currency_type: order.currency_type || "points",
            status: order.status,
            created_at: order.created_at,
            notes: order.notes
          }
        end
        
        render json: {
          status: "success",
          data: orders,
          paid_coin_name: SiteSetting.jifen_paid_coin_name
        }
      else
        # 使用模拟订单数据
        mock_orders = [
          {
            id: 1,
            product_name: "VIP会员",
            product_description: "享受30天VIP特权，无广告浏览",
            product_icon: "fa-crown",
            quantity: 1,
            unit_price: 500,
            total_price: 500,
            status: "completed",
            created_at: "2024-12-01T10:30:00Z",
            notes: "感谢购买！"
          },
          {
            id: 2,
            product_name: "专属头像框",
            product_description: "炫酷的金色头像框，彰显身份",
            product_icon: "fa-user-circle",
            quantity: 1,
            unit_price: 200,
            total_price: 200,
            status: "completed",
            created_at: "2024-11-30T14:20:00Z",
            notes: ""
          }
        ]
        
        render json: {
          status: "success",
          data: mock_orders
        }
      end
    rescue => e
      Rails.logger.error "获取订单失败: #{e.message}"
      render json: {
        status: "error",
        message: "获取订单失败: #{e.message}"
      }, status: 500
    end
  end
  
  def add_product
    ensure_logged_in
    ensure_admin
    
    begin
      product_params = params.require(:product).permit(
        :name, :description, :icon_class, :price, :stock, :sort_order, :currency_type, :tag,
        :is_partnership, :partner_username, :partnership_category, :related_post_url,
        :decoration_frame_id, :decoration_badge_id, :virtual_email_template, 
        :virtual_address_template, :commission_rate
      )
      
      if ActiveRecord::Base.connection.table_exists?('qd_shop_products')
        product = MyPluginModule::ShopProduct.create!(product_params)
        
        Rails.logger.info "🛒 管理员#{current_user.username} 添加商品: #{product.name}"
        
        render json: {
          status: "success",
          message: "商品添加成功！",
          data: {
            id: product.id,
            name: product.name,
            price: product.price,
            stock: product.stock,
            tag: product.tag
          }
        }
      else
        render json: {
          status: "error",
          message: "数据库表尚未创建，请先运行数据库迁移"
        }, status: 500
      end
      
    rescue ActiveRecord::RecordInvalid => e
      render json: {
        status: "error",
        message: "添加失败：#{e.record.errors.full_messages.join(', ')}"
      }, status: 422
    rescue => e
      Rails.logger.error "添加商品失败: #{e.message}"
      render json: {
        status: "error",
        message: "添加商品失败: #{e.message}"
      }, status: 500
    end
  end
  
  def create_sample
    ensure_logged_in
    ensure_admin
    
    begin
      if ActiveRecord::Base.connection.table_exists?('qd_shop_products')
        sample_products = [
          {
            name: "VIP会员",
            description: "享受30天VIP特权，无广告浏览",
            icon_class: "fa-solid fa-dragon",
            price: 500,
            stock: 999,
            sort_order: 1
          },
          {
            name: "专属头像框",
            description: "炫酷的金色头像框，彰显身份",
            icon_class: "fa-regular fa-gem",
            price: 200,
            stock: 50,
            sort_order: 2
          },
          {
            name: "积分宝箱",
            description: "随机获得50-200积分奖励",
            icon_class: "fa-solid fa-gifts",
            price: 80,
            stock: 100,
            sort_order: 3
          }
        ]
        
        created_count = 0
        sample_products.each do |product_data|
          unless MyPluginModule::ShopProduct.exists?(name: product_data[:name])
            MyPluginModule::ShopProduct.create!(product_data)
            created_count += 1
          end
        end
        
        Rails.logger.info "🛒 管理员#{current_user.username} 创建了#{created_count}个示例商品"
        
        render json: {
          status: "success",
          message: "成功创建#{created_count}个示例商品！"
        }
      else
        render json: {
          status: "error",
          message: "数据库表尚未创建，请先运行数据库迁移"
        }, status: 500
      end
      
    rescue => e
      Rails.logger.error "创建示例数据失败: #{e.message}"
      render json: {
        status: "error",
        message: "创建示例数据失败: #{e.message}"
      }, status: 500
    end
  end
  
  # 管理员功能 - 删除商品
  def delete_product
    ensure_logged_in
    ensure_admin
    
    begin
      product_id = params[:id]&.to_i
      
      if product_id.blank?
        render json: {
          status: "error",
          message: "商品ID不能为空"
        }, status: 422
        return
      end
      
      if ActiveRecord::Base.connection.table_exists?('qd_shop_products')
        product = MyPluginModule::ShopProduct.find_by(id: product_id)
        
        unless product
          render json: {
            status: "error",
            message: "商品不存在"
          }, status: 404
          return
        end
        
        product_name = product.name
        product.destroy!
        
        Rails.logger.info "🛒 管理员#{current_user.username} 删除商品: #{product_name}"
        
        render json: {
          status: "success",
          message: "商品 \"#{product_name}\" 删除成功！"
        }
      else
        render json: {
          status: "error",
          message: "数据库表尚未创建，请先运行数据库迁移"
        }, status: 500
      end
      
    rescue => e
      Rails.logger.error "删除商品失败: #{e.message}"
      render json: {
        status: "error",
        message: "删除商品失败: #{e.message}"
      }, status: 500
    end
  end
  
  # 管理员功能 - 订单管理
  def admin_orders
    ensure_logged_in
    ensure_admin
    
    begin
      page = params[:page]&.to_i || 1
      per_page = 20
      offset = (page - 1) * per_page
      
      if ActiveRecord::Base.connection.table_exists?('qd_shop_orders')
        total_count = MyPluginModule::ShopOrder.count
        orders = MyPluginModule::ShopOrder.includes(:user)
                                         .order(created_at: :desc)
                                         .limit(per_page)
                                         .offset(offset)
                                         .map do |order|
          user = User.find_by(id: order.user_id)
          {
            id: order.id,
            user_id: order.user_id,
            username: user&.username || "未知用户",
            user_avatar: user&.avatar_template || "",
            product_id: order.product_id,
            product_name: order.product_name,
            product_description: order.product_description,
            product_icon: order.product_icon,
            item_name: order.product_name,  # 兼容模板中的字段名
            item_description: order.product_description,  # 兼容模板中的字段名
            item_icon: order.product_icon,  # 兼容模板中的字段名
            item_price: order.unit_price,  # 兼容模板中的字段名
            quantity: order.quantity,
            unit_price: order.unit_price,
            total_price: order.total_price,
            currency_type: order.currency_type || "points",
            status: order.status,
            created_at: order.created_at,
            updated_at: order.updated_at,
            notes: order.notes
          }
        end
        
        render json: {
          status: "success",
          data: {
            orders: orders,
            total_count: total_count,
            current_page: page,
            per_page: per_page,
            total_pages: (total_count.to_f / per_page).ceil,
            paid_coin_name: SiteSetting.jifen_paid_coin_name
          }
        }
      else
        render json: {
          status: "error",
          message: "订单表不存在"
        }, status: 500
      end
    rescue => e
      Rails.logger.error "获取管理员订单失败: #{e.message}"
      render json: {
        status: "error",
        message: "获取订单失败: #{e.message}"
      }, status: 500
    end
  end
  
  # 管理员功能 - 删除订单
  def delete_order
    ensure_logged_in
    ensure_admin
    
    begin
      order_id = params[:id]&.to_i
      
      if order_id.nil? || order_id <= 0
        render json: {
          status: "error",
          message: "无效的订单ID"
        }, status: 400
        return
      end
      
      if ActiveRecord::Base.connection.table_exists?('qd_shop_orders')
        order = MyPluginModule::ShopOrder.find_by(id: order_id)
        
        if order.nil?
          render json: {
            status: "error", 
            message: "订单不存在"
          }, status: 404
          return
        end
        
        # 记录订单信息用于日志
        order_info = "订单##{order.id} - 用户#{order.user_id} - #{order.product_name} - #{order.total_price}积分"
        
        # 删除订单（不管状态如何都可以删除）
        order.destroy!
        
        Rails.logger.info "🗑️ 管理员#{current_user.username} 删除了#{order_info}"
        
        render json: {
          status: "success",
          message: "订单删除成功"
        }
      else
        render json: {
          status: "error",
          message: "订单表不存在"
        }, status: 500
      end
      
    rescue => e
      Rails.logger.error "删除订单失败: #{e.message}"
      render json: {
        status: "error",
        message: "删除订单失败: #{e.message}"
      }, status: 500
    end
  end

  # 管理员功能 - 更新订单状态
  def update_order_status
    ensure_logged_in
    ensure_admin
    
    begin
      order_id = params[:id]&.to_i
      new_status = params[:status]&.to_s&.strip
      admin_notes = params[:admin_notes]&.to_s&.strip || ""
      
      Rails.logger.info "🔄 更新订单状态请求: order_id=#{order_id}, new_status='#{new_status}', admin_notes='#{admin_notes}'"
      
      unless ['pending', 'completed', 'cancelled'].include?(new_status)
        render json: {
          status: "error",
          message: "无效的订单状态: #{new_status}"
        }, status: 422
        return
      end
      
      if ActiveRecord::Base.connection.table_exists?('qd_shop_orders')
        order = MyPluginModule::ShopOrder.find_by(id: order_id)
        
        unless order
          render json: {
            status: "error",
            message: "订单不存在"
          }, status: 404
          return
        end
        
        old_status = order.status
        user = User.find_by(id: order.user_id)
        
        # 更新订单状态和备注
        updated_notes = order.notes || ""
        if admin_notes.present?
          updated_notes += "
[管理员留言] #{admin_notes}"
        end
        
        order.update!(
          status: new_status,
          notes: updated_notes,
          updated_at: Time.current
        )
        
        Rails.logger.info "🛒 管理员#{current_user.username} 将订单##{order.id} 状态从 #{old_status} 更新为 #{new_status}"
        
        render json: {
          status: "success",
          message: "订单状态更新成功",
          data: {
            id: order.id,
            old_status: old_status,
            new_status: new_status,
            username: user&.username
          }
        }
      else
        render json: {
          status: "error",
          message: "订单表不存在"
        }, status: 500
      end
    rescue => e
      Rails.logger.error "更新订单状态失败: #{e.message}"
      Rails.logger.error e.backtrace.join("
")
      render json: {
        status: "error",
        message: "更新订单状态失败: #{e.message}"
      }, status: 500
    end
  end

  # 管理员功能 - 更新商品
  def update_product
    ensure_logged_in
    ensure_admin
    
    begin
      product_id = params[:id]&.to_i
      product_params = params.require(:product).permit(
        :name, :description, :icon_class, :price, :stock, :sort_order, :currency_type, :tag,
        :is_partnership, :partner_username, :partnership_category, :related_post_url,
        :decoration_frame_id, :decoration_badge_id, :virtual_email_template, 
        :virtual_address_template, :commission_rate
      )
      
      if product_id.blank?
        render json: {
          status: "error",
          message: "商品ID不能为空"
        }, status: 422
        return
      end
      
      if ActiveRecord::Base.connection.table_exists?('qd_shop_products')
        product = MyPluginModule::ShopProduct.find_by(id: product_id)
        
        unless product
          render json: {
            status: "error",
            message: "商品不存在"
          }, status: 404
          return
        end
        
        product.update!(product_params)
        
        Rails.logger.info "🛒 管理员#{current_user.username} 更新商品: #{product.name}"
        
        # 构建完整的商品数据返回
        product_data = {
          id: product.id,
          name: product.name,
          description: product.description,
          icon_class: product.icon_class,
          price: product.price,
          stock: product.stock,
          sort_order: product.sort_order,
          currency_type: product.currency_type,
          tag: product.tag,
          is_partnership: product.is_partnership || false
        }
        
        # 如果是合作商品，添加合作商品字段
        if product.is_partnership
          product_data.merge!(
            partner_username: product.partner_username,
            partnership_category: product.partnership_category,
            related_post_url: product.related_post_url,
            commission_rate: product.commission_rate,
            decoration_frame_id: product.decoration_frame_id,
            decoration_badge_id: product.decoration_badge_id,
            virtual_email_template: product.virtual_email_template,
            virtual_address_template: product.virtual_address_template
          )
        end
        
        render json: {
          status: "success",
          message: "商品更新成功！",
          data: product_data
        }
      else
        render json: {
          status: "error",
          message: "数据库表尚未创建，请先运行数据库迁移"
        }, status: 500
      end
      
    rescue ActiveRecord::RecordInvalid => e
      render json: {
        status: "error",
        message: "更新失败：#{e.record.errors.full_messages.join(', ')}"
      }, status: 422
    rescue => e
      Rails.logger.error "更新商品失败: #{e.message}"
      render json: {
        status: "error",
        message: "更新商品失败: #{e.message}"
      }, status: 500
    end
  end

  # 付费币兑换积分
  def exchange_coins
    ensure_logged_in
    
    amount = params[:amount].to_i
    
    if amount <= 0
      render json: { status: "error", message: "兑换数量必须大于0" }, status: 400
      return
    end
    
    # 检查付费币余额
    available = MyPluginModule::PaidCoinService.available_coins(current_user)
    if available < amount
      render json: { status: "error", message: "#{SiteSetting.jifen_paid_coin_name}不足" }, status: 400
      return
    end
    
    # 计算获得的积分
    ratio = SiteSetting.jifen_paid_coin_to_points_ratio
    points_to_add = amount * ratio
    
    begin
      ActiveRecord::Base.transaction do
        # 扣除付费币
        MyPluginModule::PaidCoinService.deduct_coins!(
          current_user,
          amount,
          reason: "兑换积分"
        )
        
        # 增加积分
        MyPluginModule::JifenService.adjust_points!(
          current_user,
          current_user,
          points_to_add
        )
      end
      
      Rails.logger.info "💱 用户#{current_user.username} 兑换: #{amount}#{SiteSetting.jifen_paid_coin_name} -> #{points_to_add}积分"
      
      render json: {
        status: "success",
        message: "兑换成功！",
        paid_coins_used: amount,
        points_gained: points_to_add,
        new_paid_coins: MyPluginModule::PaidCoinService.available_coins(current_user),
        new_points: MyPluginModule::JifenService.available_total_points(current_user)
      }
    rescue => e
      Rails.logger.error "[Shop] 兑换失败: #{e.message}"
      render json: { status: "error", message: "兑换失败: #{e.message}" }, status: 500
    end
  end

  # 管理员功能 - 退款
  def refund_order
    ensure_logged_in
    ensure_admin
    
    begin
      order_id = params[:id]&.to_i
      
      if order_id.nil? || order_id <= 0
        render json: {
          status: "error",
          message: "无效的订单ID"
        }, status: 400
        return
      end
      
      if ActiveRecord::Base.connection.table_exists?('qd_shop_orders')
        order = MyPluginModule::ShopOrder.find_by(id: order_id)
        
        unless order
          render json: {
            status: "error",
            message: "订单不存在"
          }, status: 404
          return
        end
        
        # 检查订单状态
        if order.status == "refunded"
          render json: {
            status: "error",
            message: "该订单已经退款过了"
          }, status: 400
          return
        end
        
        # 执行退款
        ActiveRecord::Base.transaction do
          # 根据货币类型返还
          if order.currency_type == "paid_coins"
            # 返还付费币
            MyPluginModule::PaidCoinService.add_coins!(
              User.find(order.user_id),
              order.total_price,
              reason: "订单退款 ##{order.id}"
            )
          else
            # 返还积分
            MyPluginModule::JifenService.adjust_points!(
              current_user,
              User.find(order.user_id),
              order.total_price
            )
          end
          
          # 更新订单状态
          order.update!(status: "refunded")
        end
        
        Rails.logger.info "🔙 管理员#{current_user.username} 退款订单##{order.id}"
        
        render json: {
          status: "success",
          message: "退款成功",
          order_id: order.id
        }
      else
        render json: {
          status: "error",
          message: "订单表不存在"
        }, status: 500
      end
    rescue => e
      Rails.logger.error "退款订单失败: #{e.message}"
      render json: {
        status: "error",
        message: "退款失败: #{e.message}"
      }, status: 500
    end
  end

  private
  
  def ensure_admin
    unless current_user&.admin?
      render json: { 
        status: "error", 
        message: "需要管理员权限" 
      }, status: 403
    end
  end

  # 处理合作商品购买的特殊逻辑
  def handle_partnership_purchase(product, buyer, quantity, total_price, order)
    return unless product.partnership?

    # 1. 计算合作伙伴收益并发放
    partner_user = product.partner_user
    if partner_user
      partner_income = product.calculate_partner_income(product.price, quantity)
      if partner_income > 0
        # 根据商品货币类型发放对应的收益
        currency_type = product.currency_type || "points"
        case currency_type
        when "points"
          # 发放积分
          MyPluginModule::JifenService.adjust_points!(
            current_user, # 操作者
            partner_user, # 收益用户
            partner_income.to_i
          )
        when "paid_coins"
          # 发放付费币
          MyPluginModule::PaidCoinService.add_coins!(
            partner_user,
            partner_income.to_i,
            reason: "合作商品销售分成 - #{product.name} x#{quantity}",
            related_id: order&.id,
            related_type: "ShopOrder"
          )
          coin_name = SiteSetting.jifen_paid_coin_name
        end
      end
    end

    # 2. 装饰品类型：自动发放
    if product.is_decoration?
      handle_decoration_delivery(product, buyer, quantity)
      
      # 自动标记订单为已完成
      order&.update(status: "completed") if order
    end

    # 3. 虚拟物品类型：发送通知
    if product.is_virtual?
      handle_virtual_item_notification(product, buyer, quantity, order)
    end
  end

  # 处理装饰品发放（参考VIP系统）
  def handle_decoration_delivery(product, user, quantity)
    # 发放头像框
    if product.decoration_frame_id.present?
      # 检查是否已有该头像框的授予记录
      existing_grant = MyPluginModule::DecorationGrant.find_by(
        user_id: user.id,
        decoration_type: "avatar_frame",
        decoration_id: product.decoration_frame_id,
        revoked: false
      )
      
      if existing_grant
        # 如果已存在且没有过期时间（永久），无需重复发放
        Rails.logger.info "🎨 用户#{user.username} 已拥有头像框 ##{product.decoration_frame_id}，无需重复发放"
      else
        # 创建新的授予记录（永久有效）
        MyPluginModule::DecorationGrant.create!(
          user_id: user.id,
          decoration_type: "avatar_frame",
          decoration_id: product.decoration_frame_id,
          granted_by_user_id: Discourse.system_user.id,
          granted_at: Time.current,
          expires_at: nil  # 永久有效
        )
        Rails.logger.info "🎨 用户#{user.username} 获得头像框 ##{product.decoration_frame_id}"
      end
    end

    # 发放勋章
    if product.decoration_badge_id.present?
      # 检查是否已有该勋章的授予记录
      existing_grant = MyPluginModule::DecorationGrant.find_by(
        user_id: user.id,
        decoration_type: "badge",
        decoration_id: product.decoration_badge_id,
        revoked: false
      )
      
      if existing_grant
        # 如果已存在且没有过期时间（永久），无需重复发放
        Rails.logger.info "🏅 用户#{user.username} 已拥有勋章 ##{product.decoration_badge_id}，无需重复发放"
      else
        # 创建新的授予记录（永久有效）
        MyPluginModule::DecorationGrant.create!(
          user_id: user.id,
          decoration_type: "badge",
          decoration_id: product.decoration_badge_id,
          granted_by_user_id: Discourse.system_user.id,
          granted_at: Time.current,
          expires_at: nil  # 永久有效
        )
        Rails.logger.info "🏅 用户#{user.username} 获得勋章 ##{product.decoration_badge_id}"
      end
    end
  end

  # 处理虚拟物品通知 - 发送给购买用户
  def handle_virtual_item_notification(product, user, quantity, order)
    # 构建购买信息内容
    contact_info_lines = []
    
    # 使用动态变量替换邮箱和地址信息
    if product.virtual_email_template.present?
      email_info = product.virtual_email_template
      if order&.user_email.present?
        email_info = email_info.gsub('%email%', order.user_email)
      else
        email_info = email_info.gsub('%email%', '未提供')
      end
      contact_info_lines << "• #{email_info}"
    end
    
    if product.virtual_address_template.present?
      address_info = product.virtual_address_template
      if order&.user_address.present?
        address_info = address_info.gsub('%address%', order.user_address)
      else
        address_info = address_info.gsub('%address%', '未提供')
      end
      contact_info_lines << "• #{address_info}"
    end
    
    contact_info_text = contact_info_lines.any? ? "\n\n**作者留言：**\n#{contact_info_lines.join("\n")}" : ""

    # 发送站内通知（精简版）
    begin
      user.notifications.create!(
        notification_type: Notification.types[:custom],
        data: {
          message: "您已成功购买虚拟商品「#{product.name}」x#{quantity}",
          display_username: "系统消息",
          topic_title: "虚拟商品购买成功"
        }.to_json
      )
    rescue => e
      Rails.logger.warn "[商店] 创建通知失败: #{e.message}"
    end
    
    # 发送私信（详细信息）
    begin
      PostCreator.create!(
        Discourse.system_user,
        title: "🎉 虚拟商品购买成功",
        raw: <<~MSG,
          您好 @#{user.username}，
          
          恭喜您成功购买虚拟商品 **#{product.name}**！
          
          **订单详情：**
          • 商品名称：#{product.name}
          • 购买数量：#{quantity}
          • 订单号：##{order&.id || 'N/A'}#{contact_info_text}
          
          如有疑问，请联系商家 @#{product.partner_username}
          
          感谢您的购买！
          
          ---
          *此为自动发送的系统消息*
        MSG
        archetype: Archetype.private_message,
        target_usernames: [user.username],
        skip_validations: true
      )
      
      Rails.logger.info "📧 已向用户#{user.username}发送虚拟商品购买私信"
    rescue => e
      Rails.logger.warn "[商店] 发送私信失败: #{e.message}"
    end
    
    # 自动标记订单为已完成
    order&.update(status: "completed") if order
    Rails.logger.info "✅ 虚拟商品订单 ##{order&.id} 已自动标记为已完成"
  end
end