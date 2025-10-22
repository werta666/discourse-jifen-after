class MyPluginModule::ShopController < ApplicationController
  requires_login
  
  def index
    render json: { status: "success" }
  end
  
  def products
    begin
      if ActiveRecord::Base.connection.table_exists?('qd_shop_products')
        products = MyPluginModule::ShopProduct.order(:sort_order, :id).map do |product|
          {
            id: product.id,
            name: product.name,
            description: product.description,
            icon_class: product.icon_class,
            price: product.price,
            stock: product.stock,
            stock_status: product.stock > 0 ? "库存充足" : "暂时缺货",
            available: product.stock > 0,
            sales_count: 0,
            sort_order: product.sort_order,
            created_at: product.created_at
          }
        end
        
        render json: {
          status: "success",
          products: products,
          user_points: MyPluginModule::JifenService.available_total_points(current_user),
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
          
          # 重新获取最新积分（防止并发修改）
          current_points = MyPluginModule::JifenService.available_total_points(current_user)
          
          if current_points < total_price
            render json: {
              status: "error",
              message: "积分不足！当前积分：#{current_points}，需要：#{total_price}"
            }, status: 422
            return
          end
          
          if product.stock < quantity
            render json: {
              status: "error",
              message: "库存不足！剩余库存：#{product.stock}"
            }, status: 422
            return
          end
          
          # 使用积分服务扣除积分（会自动记录审计日志）
          MyPluginModule::JifenService.adjust_points!(
            current_user, 
            current_user, 
            -total_price
          )
          new_points = MyPluginModule::JifenService.available_total_points(current_user)
          
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
              status: "pending",
              notes: ""
            )
          end
          
          Rails.logger.info "🛒 用户#{current_user.username} 购买商品: #{product.name} x#{quantity}, 花费#{total_price}积分, 订单号: #{order&.id}"
          
          render json: {
            status: "success",
            message: "购买成功！订单已提交，等待处理。",
            data: {
              order_id: order&.id,
              product_name: product.name,
              quantity: quantity,
              total_price: total_price,
              remaining_points: new_points,
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
        
        Rails.logger.info "🛒 用户#{current_user.username} 模拟购买商品: #{product[:name]} x#{quantity}, 花费#{total_price}积分"
        
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
            status: order.status,
            created_at: order.created_at,
            notes: order.notes
          }
        end
        
        render json: {
          status: "success",
          data: orders
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
      product_params = params.require(:product).permit(:name, :description, :icon_class, :price, :stock, :sort_order)
      
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
            stock: product.stock
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
            total_pages: (total_count.to_f / per_page).ceil
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
      product_params = params.require(:product).permit(:name, :description, :icon_class, :price, :stock, :sort_order)
      
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
        
        render json: {
          status: "success",
          message: "商品更新成功！",
          data: {
            id: product.id,
            name: product.name,
            description: product.description,
            icon_class: product.icon_class,
            price: product.price,
            stock: product.stock,
            sort_order: product.sort_order
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

  private
  
  def ensure_admin
    unless current_user&.admin?
      render json: { 
        status: "error", 
        message: "需要管理员权限" 
      }, status: 403
    end
  end
end