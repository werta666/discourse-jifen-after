# frozen_string_literal: true

require "openssl"
require "base64"
require "uri"
require "net/http"
require "json"

module ::MyPluginModule
  module AlipayService
    GATEWAY_URL = "https://openapi.alipay.com/gateway.do"
    CHARSET = "UTF-8"
    SIGN_TYPE = "RSA2"
    VERSION = "1.0"
    FORMAT = "JSON"

    module_function

    # 创建支付订单（二维码支付）
    def create_qr_order(user_id:, amount:, points:)
      raise StandardError, "金额必须大于0" if amount.to_f <= 0
      raise StandardError, "积分必须大于0" if points.to_i <= 0

      # 生成订单号
      out_trade_no = MyPluginModule::PaymentOrder.generate_out_trade_no
      subject = "积分充值 #{points}积分"

      # 创建订单记录
      order = MyPluginModule::PaymentOrder.create!(
        user_id: user_id,
        out_trade_no: out_trade_no,
        amount: amount.to_f,
        points: points.to_i,
        subject: subject,
        status: MyPluginModule::PaymentOrder::STATUS_PENDING,
        expires_at: 5.minutes.from_now
      )

      # 调用支付宝API生成二维码
      begin
        qr_code = request_qr_code(
          out_trade_no: out_trade_no,
          subject: subject,
          total_amount: amount.to_f
        )

        order.update!(qr_code: qr_code)

        {
          success: true,
          order_id: order.id,
          out_trade_no: out_trade_no,
          qr_code: qr_code,
          amount: amount.to_f,
          points: points.to_i,
          expires_at: order.expires_at.iso8601
        }
      rescue => e
        order.cancel!
        Rails.logger.error "[支付宝] 创建订单失败: #{e.message}"
        raise StandardError, "创建支付订单失败: #{e.message}"
      end
    end

    # 请求支付宝生成二维码
    def request_qr_code(out_trade_no:, subject:, total_amount:)
      return generate_mock_qr_code(out_trade_no) unless alipay_configured?

      biz_content = {
        out_trade_no: out_trade_no,
        total_amount: format("%.2f", total_amount),
        subject: subject,
        timeout_express: "5m"
      }.to_json

      params = build_common_params("alipay.trade.precreate")
      params["biz_content"] = biz_content
      params["notify_url"] = notify_url

      # 生成签名
      params["sign"] = generate_sign(params)

      # 发送请求
      response = send_request(params)
      parse_qr_response(response)
    end

    # 查询订单状态
    def query_order(out_trade_no:)
      return mock_query_result(out_trade_no) unless alipay_configured?

      biz_content = {
        out_trade_no: out_trade_no
      }.to_json

      params = build_common_params("alipay.trade.query")
      params["biz_content"] = biz_content
      params["sign"] = generate_sign(params)

      response = send_request(params)
      parse_query_response(response)
    end

    # 验证异步通知签名
    def verify_notify(params)
      return false unless alipay_configured?

      sign = params["sign"]
      sign_type = params["sign_type"]

      # 移除sign和sign_type
      params_to_verify = params.except("sign", "sign_type")

      # 按key排序并拼接
      sign_content = params_to_verify.sort.map { |k, v| "#{k}=#{v}" }.join("&")

      # 验证签名
      verify_sign(sign_content, sign, sign_type)
    end

    # 处理支付成功回调
    def handle_payment_success(out_trade_no:, trade_no:, notify_data: nil)
      order = MyPluginModule::PaymentOrder.find_by(out_trade_no: out_trade_no)
      raise StandardError, "订单不存在" unless order
      raise StandardError, "订单已处理" if order.status == MyPluginModule::PaymentOrder::STATUS_PAID

      ActiveRecord::Base.transaction do
        # 标记订单为已支付
        order.mark_as_paid!(trade_no, notify_data)

        # 增加用户积分
        user = User.find(order.user_id)
        MyPluginModule::JifenAPI.adjust_points!(
          target_user_id: user.id,
          delta: order.points,
          actor_id: user.id,
          reason: "alipay_recharge",
          plugin: "alipay_payment"
        )

        Rails.logger.info "[支付宝] 订单 #{out_trade_no} 支付成功，用户 #{user.username} 获得 #{order.points} 积分"
      end

      true
    end

    private

    # 检查支付宝是否已配置
    def alipay_configured?
      SiteSetting.jifen_alipay_app_id.present? &&
        SiteSetting.jifen_alipay_private_key.present? &&
        SiteSetting.jifen_alipay_public_key.present?
    end

    # 构建公共参数
    def build_common_params(method)
      {
        "app_id" => SiteSetting.jifen_alipay_app_id,
        "method" => method,
        "charset" => CHARSET,
        "sign_type" => SIGN_TYPE,
        "timestamp" => Time.current.strftime("%Y-%m-%d %H:%M:%S"),
        "version" => VERSION,
        "format" => FORMAT
      }
    end

    # 生成签名
    def generate_sign(params)
      # 移除空值和sign字段
      params_to_sign = params.reject { |_, v| v.nil? || v.to_s.empty? || _ == "sign" }

      # 按key排序并拼接
      sign_content = params_to_sign.sort.map { |k, v| "#{k}=#{v}" }.join("&")

      # RSA2签名
      private_key = OpenSSL::PKey::RSA.new(format_private_key(SiteSetting.jifen_alipay_private_key))
      signature = private_key.sign(OpenSSL::Digest::SHA256.new, sign_content)
      Base64.strict_encode64(signature)
    end

    # 验证签名
    def verify_sign(content, sign, sign_type)
      return false if sign_type != SIGN_TYPE

      public_key = OpenSSL::PKey::RSA.new(format_public_key(SiteSetting.jifen_alipay_public_key))
      signature = Base64.decode64(sign)
      public_key.verify(OpenSSL::Digest::SHA256.new, signature, content)
    rescue => e
      Rails.logger.error "[支付宝] 签名验证失败: #{e.message}"
      false
    end

    # 发送HTTP请求
    def send_request(params)
      uri = URI(GATEWAY_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri.path)
      request.set_form_data(params)

      response = http.request(request)
      JSON.parse(response.body)
    rescue => e
      Rails.logger.error "[支付宝] 请求失败: #{e.message}"
      raise StandardError, "支付宝接口调用失败"
    end

    # 解析二维码响应
    def parse_qr_response(response)
      alipay_response = response["alipay_trade_precreate_response"]
      raise StandardError, "支付宝返回格式错误" unless alipay_response

      if alipay_response["code"] == "10000"
        alipay_response["qr_code"]
      else
        error_msg = alipay_response["sub_msg"] || alipay_response["msg"] || "未知错误"
        raise StandardError, "支付宝错误: #{error_msg}"
      end
    end

    # 解析查询响应
    def parse_query_response(response)
      alipay_response = response["alipay_trade_query_response"]
      raise StandardError, "支付宝返回格式错误" unless alipay_response

      if alipay_response["code"] == "10000"
        {
          trade_status: alipay_response["trade_status"],
          trade_no: alipay_response["trade_no"],
          out_trade_no: alipay_response["out_trade_no"],
          total_amount: alipay_response["total_amount"]
        }
      else
        { trade_status: "UNKNOWN" }
      end
    end

    # 格式化私钥
    def format_private_key(key)
      key = key.strip.gsub(/\\n/, "\n")
      return key if key.start_with?("-----BEGIN")

      "-----BEGIN RSA PRIVATE KEY-----\n#{key}\n-----END RSA PRIVATE KEY-----"
    end

    # 格式化公钥
    def format_public_key(key)
      key = key.strip.gsub(/\\n/, "\n")
      return key if key.start_with?("-----BEGIN")

      "-----BEGIN PUBLIC KEY-----\n#{key}\n-----END PUBLIC KEY-----"
    end

    # 异步通知URL
    def notify_url
      "#{Discourse.base_url}/qd/pay/notify"
    end

    # ========== 测试模式（未配置支付宝时使用） ==========

    # 生成模拟二维码
    def generate_mock_qr_code(out_trade_no)
      "MOCK_QR_#{out_trade_no}"
    end

    # 模拟查询结果
    def mock_query_result(out_trade_no)
      order = MyPluginModule::PaymentOrder.find_by(out_trade_no: out_trade_no)
      return { trade_status: "UNKNOWN" } unless order

      {
        trade_status: order.status == "paid" ? "TRADE_SUCCESS" : "WAIT_BUYER_PAY",
        trade_no: order.trade_no || "MOCK_TRADE_NO",
        out_trade_no: out_trade_no,
        total_amount: order.amount.to_s
      }
    end
  end
end
