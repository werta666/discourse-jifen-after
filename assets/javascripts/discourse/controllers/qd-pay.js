import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdPayController extends Controller {
  @tracked selectedPackage = null;
  @tracked qrCode = null;
  @tracked orderInfo = null;
  @tracked isCreatingOrder = false;
  @tracked isPolling = false;
  @tracked pollingTimer = null;
  @tracked orderExpired = false;
  @tracked paymentSuccess = false;
  @tracked showPaymentMethodModal = false;
  @tracked selectedPaymentMethod = null;
  @tracked currentPaymentMethod = null;

  get hasPackages() {
    return this.model?.packages?.length > 0;
  }

  get alipayEnabled() {
    return this.model?.alipayEnabled || false;
  }

  get wechatEnabled() {
    return this.model?.wechatEnabled || false;
  }

  get bothPaymentEnabled() {
    return this.alipayEnabled && this.wechatEnabled;
  }

  @action
  selectPackage(pkg) {
    this.selectedPackage = pkg;
    this.qrCode = null;
    this.orderInfo = null;
    this.orderExpired = false;
    this.paymentSuccess = false;
  }

  @action
  async createOrder() {
    if (!this.selectedPackage) {
      alert("请先选择充值套餐");
      return;
    }

    // 如果两个支付方式都开启，显示选择框
    if (this.bothPaymentEnabled) {
      this.showPaymentMethodModal = true;
      return;
    }

    // 只有一个支付方式，直接使用
    const paymentMethod = this.alipayEnabled ? "alipay" : "wechat";
    this.currentPaymentMethod = paymentMethod;
    await this.doCreateOrder(paymentMethod);
  }

  @action
  selectPaymentMethod(method) {
    this.selectedPaymentMethod = method;
    this.currentPaymentMethod = method;
    this.showPaymentMethodModal = false;
    this.doCreateOrder(method);
  }

  @action
  closePaymentMethodModal() {
    this.showPaymentMethodModal = false;
    this.selectedPaymentMethod = null;
  }

  async doCreateOrder(paymentMethod) {
    this.isCreatingOrder = true;
    this.currentPaymentMethod = paymentMethod;

    try {
      const result = await ajax("/qd/pay/create_order.json", {
        type: "POST",
        data: {
          amount: this.selectedPackage.amount,
          points: this.selectedPackage.points,
          payment_method: paymentMethod
        }
      });

      console.log("创建订单响应:", result);

      if (result.success) {
        console.log("二维码:", result.qr_code);
        console.log("订单信息:", result);

        this.qrCode = result.qr_code;
        this.orderInfo = result;
        this.orderExpired = false;
        this.paymentSuccess = false;

        // 延迟设置二维码图片
        setTimeout(() => {
          this.setQRCodeImage(this.qrCode, paymentMethod);
        }, 300);

        // 开始轮询订单状态
        this.startPolling(result.out_trade_no);
      } else {
        alert("创建订单失败");
      }
    } catch (error) {
      console.error("创建订单失败:", error);
      popupAjaxError(error);
    } finally {
      this.isCreatingOrder = false;
    }
  }

  @action
  startPolling(outTradeNo) {
    if (this.pollingTimer) {
      clearInterval(this.pollingTimer);
    }

    this.isPolling = true;

    // 每2秒查询一次订单状态
    this.pollingTimer = setInterval(() => {
      this.queryOrderStatus(outTradeNo);
    }, 2000);
  }

  @action
  stopPolling() {
    if (this.pollingTimer) {
      clearInterval(this.pollingTimer);
      this.pollingTimer = null;
    }
    this.isPolling = false;
  }

  @action
  async queryOrderStatus(outTradeNo) {
    try {
      const result = await ajax("/qd/pay/query_order.json", {
        type: "GET",
        data: { out_trade_no: outTradeNo }
      });

      if (result.paid) {
        // 支付成功
        this.paymentSuccess = true;
        this.stopPolling();
        
        // 3秒后刷新充值页面
        setTimeout(() => {
          window.location.href = "/qd/pay";
        }, 3000);
      } else if (result.expired) {
        // 订单过期
        this.orderExpired = true;
        this.stopPolling();
      }
    } catch (error) {
      console.error("查询订单状态失败:", error);
      // 继续轮询，不中断
    }
  }

  @action
  async cancelOrder() {
    if (!this.orderInfo?.out_trade_no) {
      // 如果没有订单号，直接清空界面
      this.stopPolling();
      this.qrCode = null;
      this.orderInfo = null;
      this.selectedPackage = null;
      this.orderExpired = false;
      this.paymentSuccess = false;
      return;
    }

    try {
      // 调用后端API取消订单
      await ajax("/qd/pay/cancel_order.json", {
        type: "POST",
        data: {
          out_trade_no: this.orderInfo.out_trade_no
        }
      });

      console.log("订单已取消");
      
      // 停止轮询并清空界面
      this.stopPolling();
      this.qrCode = null;
      this.orderInfo = null;
      this.selectedPackage = null;
      this.orderExpired = false;
      this.paymentSuccess = false;
    } catch (error) {
      console.error("取消订单失败:", error);
      // 即使取消失败，也清空界面
      this.stopPolling();
      this.qrCode = null;
      this.orderInfo = null;
      this.selectedPackage = null;
      this.orderExpired = false;
      this.paymentSuccess = false;
    }
  }

  @action
  goBack() {
    window.location.href = "/qd";
  }

  // 设置二维码图片
  setQRCodeImage(paymentUrl, paymentMethod) {
    const qrImgId = paymentMethod === "wechat" ? "wechat-qrcode" : "alipay-qrcode";
    const qrImg = document.getElementById(qrImgId);
    if (!qrImg) return;

    // 从配置获取二维码API（如果有的话），否则使用默认值
    const qrApiBase = this.model.qrCodeApi || "https://api.pwmqr.com/qrcode/create/?url=";
    const qrImageUrl = `${qrApiBase}${encodeURIComponent(paymentUrl)}&size=250`;
    
    qrImg.src = qrImageUrl;
  }

  willDestroy() {
    super.willDestroy();
    this.stopPolling();
  }
}
