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

        // 延迟生成二维码，确保DOM已更新
        setTimeout(() => {
          this.generateQRCode(result.qr_code);
        }, 100);

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

  // 生成二维码
  generateQRCode(text) {
    const canvas = document.getElementById("qrcode-canvas");
    if (!canvas) {
      console.error("Canvas元素不存在");
      return;
    }

    const ctx = canvas.getContext("2d");
    const size = 250;
    canvas.width = size;
    canvas.height = size;

    // 使用Google Chart API生成二维码图片
    const img = new Image();
    img.crossOrigin = "Anonymous";
    img.onload = () => {
      ctx.drawImage(img, 0, 0, size, size);
      console.log("二维码生成成功");
    };
    img.onerror = () => {
      console.error("二维码图片加载失败，尝试备用方案");
      // 备用方案：使用另一个二维码API
      this.tryAlternativeQRCode(text, canvas, ctx, size);
    };
    
    // 主要API：Google Chart API
    img.src = `https://chart.googleapis.com/chart?chs=${size}x${size}&cht=qr&chl=${encodeURIComponent(text)}&choe=UTF-8`;
  }

  // 备用二维码生成方案
  tryAlternativeQRCode(text, canvas, ctx, size) {
    const img = new Image();
    img.crossOrigin = "Anonymous";
    img.onload = () => {
      ctx.drawImage(img, 0, 0, size, size);
      console.log("二维码生成成功(备用方案)");
    };
    img.onerror = () => {
      console.error("备用方案也失败了，显示文本二维码");
      // 最后的备用方案：显示文本
      ctx.fillStyle = "#ffffff";
      ctx.fillRect(0, 0, size, size);
      ctx.fillStyle = "#000000";
      ctx.font = "14px Arial";
      ctx.textAlign = "center";
      ctx.fillText("请手动访问以下链接：", size / 2, size / 2 - 10);
      ctx.font = "12px Arial";
      ctx.fillText(text.substring(0, 30), size / 2, size / 2 + 10);
    };
    
    // 备用API：qrserver.com
    img.src = `https://api.qrserver.com/v1/create-qr-code/?size=${size}x${size}&data=${encodeURIComponent(text)}`;
  }

  willDestroy() {
    super.willDestroy();
    this.stopPolling();
  }
}
