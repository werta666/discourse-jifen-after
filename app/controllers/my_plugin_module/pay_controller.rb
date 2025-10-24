# frozen_string_literal: true

module ::MyPluginModule
  class PayController < ::ApplicationController
    requires_plugin MyPluginModule::PLUGIN_NAME

    before_action :ensure_logged_in, except: [:index, :notify, :packages]
    skip_before_action :verify_authenticity_token, only: [:notify]

    # Ember 引导页
    def index
      render "default/empty"
    end

    # 获取用户付费币余额详情
    def balance
      summary = MyPluginModule::PaidCoinService.summary_for(current_user)
      
      render_json_dump({
        success: true,
        balance: summary
      })
    rescue => e
      Rails.logger.error "[付费币] 获取余额失败: #{e.message}"
      render_json_error("获取余额失败: #{e.message}", status: 500)
    end

    # 获取充值套餐配置
    def packages
      packages = parse_recharge_packages

      render_json_dump({
        success: true,
        packages: packages,
        alipay_enabled: alipay_enabled?,
        wechat_enabled: SiteSetting.jifen_wechat_enabled,
        user_paid_coins: current_user ? MyPluginModule::PaidCoinService.available_coins(current_user) : 0,
        qr_code_api: SiteSetting.jifen_qrcode_api
      })
    end

    # 创建充值订单
    def create_order
      amount = params[:amount].to_f
      points = params[:points].to_i
      payment_method = params[:payment_method] || "alipay"  # 默认支付宝

      # 验证参数
      if amount <= 0 || points <= 0
        render_json_error("充值金额和积分必须大于0", status: 400)
        return
      end

      # 验证支付方式
      unless ["alipay", "wechat"].include?(payment_method)
        render_json_error("不支持的支付方式", status: 400)
        return
      end

      # 微信支付功能未开发
      if payment_method == "wechat"
        render_json_error("微信支付功能开发中，敬请期待", status: 400)
        return
      end

      # 验证套餐合法性并获取总积分（包含赠送）
      package = find_package_by_amount_and_points(amount, points)
      unless package
        render_json_error("非法的充值套餐", status: 400)
        return
      end

      # 计算总积分（基础积分 + 赠送积分）
      base_points = package["points"].to_i
      bonus_points = package["bonus"].to_i || 0
      total_points = base_points + bonus_points

      # 检查支付宝配置
      unless alipay_enabled?
        render_json_error("支付宝支付未启用，请联系管理员配置", status: 503)
        return
      end

      begin
        result = MyPluginModule::AlipayService.create_qr_order(
          user_id: current_user.id,
          amount: amount,
          points: total_points  # 使用总积分
        )

        render_json_dump(result)
      rescue => e
        Rails.logger.error "[支付] 创建订单失败: #{e.message}\n#{e.backtrace.join("\n")}"
        render_json_error("创建订单失败: #{e.message}", status: 500)
      end
    end

    # 查询订单状态
    def query_order
      out_trade_no = params[:out_trade_no]

      unless out_trade_no.present?
        render_json_error("订单号不能为空", status: 400)
        return
      end

      order = MyPluginModule::PaymentOrder.find_by(
        out_trade_no: out_trade_no,
        user_id: current_user.id
      )

      unless order
        render_json_error("订单不存在", status: 404)
        return
      end

      # 如果订单已支付，直接返回
      if order.status == MyPluginModule::PaymentOrder::STATUS_PAID
        render_json_dump({
          success: true,
          paid: true,
          order: order_info(order)
        })
        return
      end

      # 如果订单已过期，取消订单
      if order.expired?
        order.cancel!
        render_json_dump({
          success: true,
          paid: false,
          expired: true,
          order: order_info(order)
        })
        return
      end

      # 查询支付宝订单状态
      begin
        alipay_result = MyPluginModule::AlipayService.query_order(out_trade_no: out_trade_no)

        if alipay_result && alipay_result[:trade_status] == "TRADE_SUCCESS"
          # 支付成功，处理订单
          begin
            MyPluginModule::AlipayService.handle_payment_success(
              out_trade_no: out_trade_no,
              trade_no: alipay_result[:trade_no]
            )
            order.reload
          rescue => process_error
            Rails.logger.error "[支付] 处理支付成功回调失败: #{process_error.message}\n#{process_error.backtrace.join("\n")}"
          end

          render_json_dump({
            success: true,
            paid: true,
            order: order_info(order)
          })
        else
          # 未支付或查询失败，返回当前状态
          render_json_dump({
            success: true,
            paid: false,
            expired: false,
            order: order_info(order)
          })
        end
      rescue => e
        Rails.logger.error "[支付] 查询订单异常: #{e.message}\n#{e.backtrace.join("\n")}"
        # 不返回500，返回未支付状态
        render_json_dump({
          success: true,
          paid: false,
          expired: false,
          error: e.message
        })
      end
    end

    # 用户订单列表
    def orders
      orders = MyPluginModule::PaymentOrder
        .where(user_id: current_user.id)
        .recent
        .limit(20)

      render_json_dump({
        success: true,
        orders: orders.map { |o| order_info(o) }
      })
    end

    # 取消订单
    def cancel_order
      out_trade_no = params[:out_trade_no]

      unless out_trade_no.present?
        render_json_error("订单号不能为空", status: 400)
        return
      end

      order = MyPluginModule::PaymentOrder.find_by(
        out_trade_no: out_trade_no,
        user_id: current_user.id
      )

      unless order
        render_json_error("订单不存在", status: 404)
        return
      end

      # 只有待支付状态的订单才能取消
      unless order.status == MyPluginModule::PaymentOrder::STATUS_PENDING
        render_json_error("只有待支付订单才能取消", status: 400)
        return
      end

      # 取消订单
      if order.cancel!
        render_json_dump({
          success: true,
          message: "订单已取消"
        })
      else
        render_json_error("取消订单失败", status: 500)
      end
    rescue => e
      Rails.logger.error "[支付] 取消订单失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render_json_error("取消订单失败: #{e.message}", status: 500)
    end

    # 支付宝异步通知
    def notify
      # 验证签名
      unless MyPluginModule::AlipayService.verify_notify(params.to_unsafe_h)
        Rails.logger.error "[支付宝] 签名验证失败"
        render plain: "fail", status: 200
        return
      end

      out_trade_no = params[:out_trade_no]
      trade_no = params[:trade_no]
      trade_status = params[:trade_status]
      total_amount = params[:total_amount].to_f

      order = MyPluginModule::PaymentOrder.find_by(out_trade_no: out_trade_no)

      unless order
        Rails.logger.error "[支付宝] 订单不存在: #{out_trade_no}"
        render plain: "fail", status: 200
        return
      end

      # 验证金额
      unless (order.amount - total_amount).abs < 0.01
        Rails.logger.error "[支付宝] 金额不匹配: 订单金额#{order.amount}，通知金额#{total_amount}"
        render plain: "fail", status: 200
        return
      end

      # 处理支付成功
      if trade_status == "TRADE_SUCCESS"
        begin
          MyPluginModule::AlipayService.handle_payment_success(
            out_trade_no: out_trade_no,
            trade_no: trade_no,
            notify_data: params.to_json
          )

          Rails.logger.info "[支付宝] 订单 #{out_trade_no} 处理成功"
          render plain: "success", status: 200
        rescue => e
          Rails.logger.error "[支付宝] 处理订单失败: #{e.message}"
          render plain: "fail", status: 200
        end
      else
        Rails.logger.info "[支付宝] 订单 #{out_trade_no} 状态: #{trade_status}"
        render plain: "success", status: 200
      end
    end

    # 管理员订单管理页面
    def admin
      ensure_admin!
      render "default/empty"
    rescue => e
      Rails.logger.error "[支付] 管理页面错误: #{e.message}"
      render plain: "Error: #{e.message}", status: 500
    end

    # 管理员订单统计
    def admin_stats
      ensure_admin!

      # 获取所有订单
      all_orders = MyPluginModule::PaymentOrder.all
      
      # 统计数据
      total_orders = all_orders.count
      paid_orders = all_orders.where(status: "paid").count
      pending_orders = all_orders.where(status: "pending").count
      cancelled_orders = all_orders.where(status: "cancelled").count
      
      total_amount = all_orders.where(status: "paid").sum(:amount).to_f
      total_paid_coins = all_orders.where(status: "paid").sum(:points)
      
      # 最近订单（最多20条）
      recent_orders = all_orders.order(created_at: :desc).limit(20).map do |order|
        user = User.find_by(id: order.user_id)
        {
          id: order.id,
          out_trade_no: order.out_trade_no,
          trade_no: order.trade_no,
          amount: order.amount.to_f,
          points: order.points,
          subject: order.subject,
          status: order.status,
          username: user&.username || "未知用户",
          user_id: order.user_id,
          created_at: order.created_at.strftime("%Y-%m-%d %H:%M:%S"),
          paid_at: order.paid_at&.strftime("%Y-%m-%d %H:%M:%S"),
          expires_at: order.expires_at&.strftime("%Y-%m-%d %H:%M:%S")
        }
      end

      render_json_dump({
        success: true,
        stats: {
          total_orders: total_orders,
          paid_orders: paid_orders,
          pending_orders: pending_orders,
          cancelled_orders: cancelled_orders,
          total_amount: total_amount,
          total_paid_coins: total_paid_coins
        },
        orders: recent_orders
      })
    rescue => e
      Rails.logger.error "[支付] 获取统计数据失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render_json_error("获取统计数据失败: #{e.message}", status: 500)
    end

    # 一键删除未付款订单
    def clear_unpaid_orders
      ensure_admin!

      # 删除所有pending和cancelled状态的订单
      deleted_count = MyPluginModule::PaymentOrder
        .where(status: ["pending", "cancelled"])
        .delete_all

      Rails.logger.info "[支付] 管理员清理未付款订单，删除 #{deleted_count} 条记录"

      render_json_dump({
        success: true,
        deleted_count: deleted_count,
        message: "成功删除 #{deleted_count} 条未付款订单"
      })
    rescue => e
      Rails.logger.error "[支付] 清理未付款订单失败: #{e.message}\n#{e.backtrace.join("\n")}"
      render_json_error("清理失败: #{e.message}", status: 500)
    end

    private

    # 确保是管理员
    def ensure_admin!
      unless current_user&.admin?
        raise Discourse::InvalidAccess.new("需要管理员权限")
      end
    end

    # 支付宝是否已启用
    def alipay_enabled?
      SiteSetting.jifen_alipay_enabled &&
        SiteSetting.jifen_alipay_app_id.present? &&
        SiteSetting.jifen_alipay_private_key.present? &&
        SiteSetting.jifen_alipay_public_key.present?
    end

    # 解析充值套餐
    def parse_recharge_packages
      raw = SiteSetting.jifen_recharge_packages.presence || "[]"
      JSON.parse(raw)
    rescue JSON::ParserError
      []
    end

    # 验证套餐合法性
    def valid_package?(amount, points)
      packages = parse_recharge_packages
      packages.any? { |pkg| pkg["amount"].to_f == amount && pkg["points"].to_i == points }
    end

    # 根据金额和基础积分查找套餐
    def find_package_by_amount_and_points(amount, points)
      packages = parse_recharge_packages
      packages.find { |pkg| pkg["amount"].to_f == amount && pkg["points"].to_i == points }
    end

    # 订单信息
    def order_info(order)
      {
        id: order.id,
        out_trade_no: order.out_trade_no,
        trade_no: order.trade_no,
        amount: order.amount.to_f,
        points: order.points,
        subject: order.subject,
        status: order.status,
        paid_at: order.paid_at&.iso8601,
        created_at: order.created_at.iso8601,
        expires_at: order.expires_at&.iso8601,
        expired: order.expired?
      }
    end
  end
end
