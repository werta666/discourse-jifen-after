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

  get hasPackages() {
    return this.model?.packages?.length > 0;
  }

  get alipayEnabled() {
    return this.model?.alipayEnabled || false;
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

    if (!this.alipayEnabled) {
      alert("支付宝支付未启用，请联系管理员");
      return;
    }

    this.isCreatingOrder = true;

    try {
      const result = await ajax("/qd/pay/create_order.json", {
        type: "POST",
        data: {
          amount: this.selectedPackage.amount,
          points: this.selectedPackage.points
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

        console.log("qrCode已设置:", this.qrCode);
        console.log("orderInfo已设置:", this.orderInfo);
        console.log("✅ 二维码将使用img标签自动显示");

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
        
        // 3秒后刷新页面
        setTimeout(() => {
          window.location.href = "/qd";
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
  cancelOrder() {
    this.stopPolling();
    this.qrCode = null;
    this.orderInfo = null;
    this.selectedPackage = null;
    this.orderExpired = false;
    this.paymentSuccess = false;
  }

  @action
  goBack() {
    window.location.href = "/qd";
  }

  willDestroy() {
    super.willDestroy();
    this.stopPolling();
  }
}
