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

    # 获取充值套餐配置
    def packages
      packages = parse_recharge_packages

      render_json_dump({
        success: true,
        packages: packages,
        alipay_enabled: alipay_enabled?,
        user_points: current_user ? MyPluginModule::JifenService.available_total_points(current_user) : 0
      })
    end

    # 创建充值订单
    def create_order
      amount = params[:amount].to_f
      points = params[:points].to_i

      # 验证参数
      if amount <= 0 || points <= 0
        render_json_error("充值金额和积分必须大于0", status: 400)
        return
      end

      # 验证套餐合法性
      unless valid_package?(amount, points)
        render_json_error("非法的充值套餐", status: 400)
        return
      end

      # 检查支付宝配置
      unless alipay_enabled?
        render_json_error("支付宝支付未启用，请联系管理员配置", status: 503)
        return
      end

      begin
        result = MyPluginModule::AlipayService.create_qr_order(
          user_id: current_user.id,
          amount: amount,
          points: points
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

        if alipay_result[:trade_status] == "TRADE_SUCCESS"
          # 支付成功，处理订单
          MyPluginModule::AlipayService.handle_payment_success(
            out_trade_no: out_trade_no,
            trade_no: alipay_result[:trade_no]
          )

          order.reload

          render_json_dump({
            success: true,
            paid: true,
            order: order_info(order)
          })
        else
          render_json_dump({
            success: true,
            paid: false,
            order: order_info(order)
          })
        end
      rescue => e
        Rails.logger.error "[支付] 查询订单失败: #{e.message}"
        render_json_error("查询订单失败: #{e.message}", status: 500)
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

    # 支付宝异步通知
    def notify
      Rails.logger.info "[支付宝] 收到异步通知: #{params.inspect}"

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

    private

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
