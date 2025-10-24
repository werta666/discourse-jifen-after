# frozen_string_literal: true

require "openssl"
require "securerandom"
require "uri"
require "net/http"
require "json"

module ::MyPluginModule
  module WechatService
    # 微信支付API地址
    UNIFIEDORDER_URL = "https://api.mch.weixin.qq.com/pay/unifiedorder"
    ORDERQUERY_URL = "https://api.mch.weixin.qq.com/pay/orderquery"
    
    module_function

    # 创建支付订单（Native扫码支付）
    def create_qr_order(user_id:, amount:, points:)
      raise StandardError, "金额必须大于0" if amount.to_f <= 0
      raise StandardError, "积分必须大于0" if points.to_i <= 0

      user = User.find(user_id)
      Rails.logger.info "[微信支付] 创建订单 - 用户: #{user.username}, 金额: #{amount}, 付费币: #{points}"

      # 生成订单号
      out_trade_no = MyPluginModule::PaymentOrder.generate_out_trade_no
      coin_name = SiteSetting.jifen_paid_coin_name
      subject = "#{coin_name}充值 #{points}个"

      # 创建订单记录
      order = MyPluginModule::PaymentOrder.create!(
        user_id: user_id,
        out_trade_no: out_trade_no,
        amount: amount.to_f,
        points: points.to_i,
        subject: subject,
        status: MyPluginModule::PaymentOrder::STATUS_PENDING,
        payment_method: "wechat",
        expires_at: 2.minutes.from_now
      )

      Rails.logger.info "[微信支付] 订单创建成功 - 订单号: #{out_trade_no}"

      # 调用微信支付API生成二维码
      begin
        code_url = request_native_pay(
          out_trade_no: out_trade_no,
          body: subject,
          total_fee: (amount.to_f * 100).to_i  # 微信支付金额单位为分
        )

        order.update!(qr_code: code_url)

        {
          success: true,
          order_id: order.id,
          out_trade_no: out_trade_no,
          qr_code: code_url,
          amount: amount.to_f,
          points: points.to_i,
          expires_at: order.expires_at.iso8601
        }
      rescue => e
        order.cancel!
        Rails.logger.error "[微信支付] 创建订单失败: #{e.message}"
        raise StandardError, "创建支付订单失败: #{e.message}"
      end
    end

    # 请求微信Native支付（生成二维码）
    def request_native_pay(out_trade_no:, body:, total_fee:)
      raise StandardError, "微信支付未配置" unless wechat_configured?

      # 构建请求参数
      params = {
        appid: SiteSetting.jifen_wechat_app_id,
        mch_id: SiteSetting.jifen_wechat_mch_id,
        nonce_str: generate_nonce_str,
        body: body,
        out_trade_no: out_trade_no,
        total_fee: total_fee,
        spbill_create_ip: get_server_ip,
        notify_url: notify_url,
        trade_type: "NATIVE"
      }

      # 生成签名
      params[:sign] = generate_sign(params)

      # 构建XML请求
      xml_request = build_xml(params)
      
      Rails.logger.info "[微信支付] 统一下单请求: #{out_trade_no}"
      Rails.logger.debug "[微信支付] 请求参数: #{params.inspect}"

      # 发送请求
      response_xml = send_request(UNIFIEDORDER_URL, xml_request)
      
      # 解析响应
      result = parse_xml(response_xml)
      
      Rails.logger.info "[微信支付] 统一下单响应: #{result.inspect}"

      if result["return_code"] == "SUCCESS" && result["result_code"] == "SUCCESS"
        code_url = result["code_url"]
        Rails.logger.info "[微信支付] 二维码生成成功: #{code_url}"
        code_url
      else
        error_msg = result["return_msg"] || result["err_code_des"] || "未知错误"
        Rails.logger.error "[微信支付] 统一下单失败: #{error_msg}"
        raise StandardError, "微信支付错误: #{error_msg}"
      end
    end

    # 查询订单状态
    def query_order(out_trade_no:)
      raise StandardError, "微信支付未配置" unless wechat_configured?

      params = {
        appid: SiteSetting.jifen_wechat_app_id,
        mch_id: SiteSetting.jifen_wechat_mch_id,
        out_trade_no: out_trade_no,
        nonce_str: generate_nonce_str
      }

      params[:sign] = generate_sign(params)
      xml_request = build_xml(params)

      response_xml = send_request(ORDERQUERY_URL, xml_request)
      result = parse_xml(response_xml)

      Rails.logger.info "[微信支付] 订单查询结果: #{result.inspect}"

      if result["return_code"] == "SUCCESS" && result["result_code"] == "SUCCESS"
        trade_state = result["trade_state"]
        {
          trade_state: trade_state,
          transaction_id: result["transaction_id"],
          out_trade_no: result["out_trade_no"],
          total_fee: result["total_fee"]
        }
      else
        { trade_state: "UNKNOWN" }
      end
    end

    # 验证异步通知签名
    def verify_notify(params)
      return false unless wechat_configured?

      sign = params["sign"]
      params_without_sign = params.except("sign")

      expected_sign = generate_sign(params_without_sign)
      sign == expected_sign
    end

    # 处理支付成功回调
    def handle_payment_success(out_trade_no:, transaction_id:, notify_data: nil)
      Rails.logger.info "[微信支付] 开始处理支付成功回调 - 订单号: #{out_trade_no}"
      
      order = MyPluginModule::PaymentOrder.find_by(out_trade_no: out_trade_no)
      raise StandardError, "订单不存在" unless order

      # 防止重复处理
      if order.status == MyPluginModule::PaymentOrder::STATUS_PAID
        Rails.logger.warn "[微信支付] 订单 #{out_trade_no} 已处理，跳过"
        return true
      end

      ActiveRecord::Base.transaction do
        # 1. 标记订单为已支付
        order.mark_as_paid!(transaction_id, notify_data)
        
        # 2. 给用户增加付费币
        user = User.find(order.user_id)
        
        MyPluginModule::PaidCoinService.add_coins!(
          user,
          order.points,
          reason: "微信充值订单 #{out_trade_no}",
          related_id: order.id,
          related_type: "PaymentOrder"
        )
        
        Rails.logger.info "[微信支付] 订单 #{out_trade_no} 支付成功处理完成 - 用户 #{user.username} 获得 #{order.points} 付费币"
      end

      true
    rescue => e
      Rails.logger.error "[微信支付] 处理支付成功回调失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      raise
    end

    # ========== 内部辅助方法 ==========

    # 检查微信支付是否已配置（Native扫码支付）
    def wechat_configured?
      SiteSetting.jifen_wechat_app_id.present? &&
        SiteSetting.jifen_wechat_mch_id.present? &&
        SiteSetting.jifen_wechat_api_key.present?
    end

    # 检查JSAPI支付是否已配置（需要额外的AppSecret）
    def jsapi_configured?
      wechat_configured? && SiteSetting.jifen_wechat_app_secret.present?
    end

    # 生成随机字符串
    def generate_nonce_str
      SecureRandom.hex(16)
    end

    # 生成签名（参考wx_pay实现）
    def generate_sign(params)
      # 1. 移除sign字段和空值（null或空字符串）
      params_for_sign = params.reject do |k, v|
        k.to_s == "sign" || 
        v.nil? || 
        (v.is_a?(String) && v.empty?) ||
        v.is_a?(Array)  # 跳过数组类型
      end
      
      # 2. 转换所有key为字符串并按key排序
      sorted_params = params_for_sign.transform_keys(&:to_s).sort
      
      # 3. 拼接成字符串 key1=value1&key2=value2
      sign_string = sorted_params.map { |k, v| "#{k}=#{v}" }.join("&")
      
      # 4. 拼接API密钥
      sign_string += "&key=#{SiteSetting.jifen_wechat_api_key}"
      
      Rails.logger.debug "[微信支付] 待签名字符串: #{sign_string}"
      
      # 5. MD5加密并转大写
      Digest::MD5.hexdigest(sign_string).upcase
    end

    # 构建XML请求
    def build_xml(params)
      xml = "<xml>"
      params.each do |key, value|
        xml += "<#{key}><![CDATA[#{value}]]></#{key}>"
      end
      xml += "</xml>"
      xml
    end

    # 解析XML响应
    def parse_xml(xml)
      require "rexml/document"
      doc = REXML::Document.new(xml)
      result = {}
      
      doc.root.elements.each do |element|
        result[element.name] = element.text
      end
      
      result
    rescue => e
      Rails.logger.error "[微信支付] XML解析失败: #{e.message}\n#{xml}"
      {}
    end

    # 发送HTTP请求
    def send_request(url, xml_data)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 15

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "text/xml; charset=UTF-8"
      request.body = xml_data

      Rails.logger.info "[微信支付] 发送请求到: #{url}"

      response = http.request(request)
      response_body = response.body.force_encoding("UTF-8")

      Rails.logger.info "[微信支付] 响应状态: #{response.code}"
      Rails.logger.debug "[微信支付] 响应内容: #{response_body}"

      response_body
    rescue => e
      Rails.logger.error "[微信支付] 请求失败: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      raise StandardError, "微信支付接口调用失败: #{e.message}"
    end

    # 获取服务器IP
    def get_server_ip
      # 优先从请求中获取，否则使用默认值
      "127.0.0.1"
    end

    # 异步通知URL
    def notify_url
      "#{Discourse.base_url}/qd/pay/wechat_notify"
    end

    # 生成返回给微信的XML响应
    def build_response_xml(return_code:, return_msg: "")
      "<xml><return_code><![CDATA[#{return_code}]]></return_code><return_msg><![CDATA[#{return_msg}]]></return_msg></xml>"
    end
  end
end
