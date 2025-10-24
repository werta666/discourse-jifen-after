import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdPayRoute extends Route {
  async model() {
    try {
      const data = await ajax("/qd/pay/packages.json");
      return {
        packages: data.packages || [],
        alipayEnabled: data.alipay_enabled || false,
        wechatEnabled: data.wechat_enabled || false,
        userPaidCoins: data.user_paid_coins || 0,
        paidCoinName: data.paid_coin_name || "付费币",
        qrCodeApi: data.qr_code_api || "https://api.pwmqr.com/qrcode/create/?url=",
        loadTime: new Date().toISOString()
      };
    } catch (error) {
      console.error("加载充值套餐失败:", error);
      return {
        packages: [],
        alipayEnabled: false,
        wechatEnabled: false,
        userPaidCoins: 0,
        paidCoinName: "付费币",
        qrCodeApi: "https://api.pwmqr.com/qrcode/create/?url=",
        error: "加载充值套餐失败"
      };
    }
  }
}
