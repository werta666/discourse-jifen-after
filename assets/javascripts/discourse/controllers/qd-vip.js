import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { inject as service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdVipController extends Controller {
  @service dialog;
  
  // 使用@tracked直接追踪选中的套餐对象（像qd-shop一样）
  @tracked selectedPackage = null;
  @tracked showPurchaseModal = false;
  @tracked showSuccessModal = false;
  @tracked selectedDurationType = null;
  @tracked purchaseResult = null;
  @tracked purchasing = false;

  get hasVip() {
    return this.model.current_vip !== null;
  }

  get vipLevel() {
    return this.model.current_vip?.level || 0;
  }

  get vipExpiresAt() {
    if (!this.model.current_vip) return null;
    const date = new Date(this.model.current_vip.expires_at);
    return date.toLocaleDateString('zh-CN');
  }

  get vipDaysRemaining() {
    return this.model.current_vip?.days_remaining || 0;
  }

  get userBalance() {
    return this.model.user_paid_coins || 0;
  }

  get coinName() {
    return this.model.paid_coin_name || "付费币";
  }

  get packages() {
    return this.model.packages || [];
  }

  get hasPackages() {
    return this.packages.length > 0;
  }

  // 选中套餐的ID（模板使用，避免直接访问 this.selectedPackage.id）
  get selectedPackageId() {
    return this.selectedPackage ? this.selectedPackage.id : null;
  }

  // 获取当前套餐的定价方案（安全处理）
  get pricingPlans() {
    if (!this.selectedPackage) return [];
    const plans = this.selectedPackage.pricing_plans;
    return Array.isArray(plans) ? plans : [];
  }

  // 获取当前选中的价格
  get selectedPrice() {
    if (!this.selectedDurationType) return 0;
    const plan = this.pricingPlans.find(p => p.type === this.selectedDurationType);
    return plan ? plan.price : 0;
  }
  
  // 升级抵扣后的应付金额（非VIP或同级续费=原价；升级=差价，向上取整）
  get payablePrice() {
    const rawPrice = this.selectedPrice || 0;
    if (!this.selectedPackage || !this.selectedDurationType) return rawPrice;
    if (!this.hasVip) return rawPrice;
    const currentLevel = this.vipLevel || 0;
    const targetLevel = this.selectedPackage.level || 0;
    // 降级或同级：不做抵扣
    if (targetLevel <= currentLevel) return rawPrice;

    const plan = this.pricingPlans.find(p => p.type === this.selectedDurationType);
    const planDays = plan ? (parseInt(plan.days) || 0) : 0;
    const targetDaily = planDays > 0 ? (rawPrice / planDays) : 0;

    const cv = this.model.current_vip || {};
    const pricePaid = parseFloat(cv.price_paid || 0);
    const durationDays = parseInt(cv.duration_days || 0);
    const daysRemaining = parseInt(this.vipDaysRemaining || 0);
    const currentDaily = durationDays > 0 ? (pricePaid / durationDays) : 0;

    const remainingValue = daysRemaining * currentDaily;
    if (remainingValue >= rawPrice) {
      return 0;
    }
    return Math.ceil(rawPrice - remainingValue);
  }
  
  // 购买后余额（使用抵扣后的应付金额）
  get remainingBalance() {
    const balance = this.userBalance || 0;
    const payable = this.payablePrice || 0;
    return balance - payable;
  }
  
  // 获取当前选中的时长标签
  get selectedDurationLabel() {
    if (!this.selectedDurationType) return "";
    const plan = this.pricingPlans.find(p => p.type === this.selectedDurationType);
    return plan ? plan.label : "";
  }

  @action
  selectPackage(pkg) {
    // 直接赋值对象（像qd-shop的showProductDetail一样）
    this.selectedPackage = pkg;
  }

  @action
  openPurchaseModal() {
    if (!this.selectedPackage) {
      this.dialog.alert("请先选择VIP套餐");
      return;
    }
    // 前置校验：选择低于当前等级的套餐时直接提示并阻止打开
    if (this.hasVip && this.selectedPackage.level < this.vipLevel) {
      this.dialog.alert("不支持降级购买");
      return;
    }
    
    const plans = this.pricingPlans;
    if (plans.length === 0) {
      this.dialog.alert("该套餐暂无定价方案，请联系管理员");
      return;
    }
    
    // 默认选择第一个定价方案
    this.selectedDurationType = plans[0].type;
    this.showPurchaseModal = true;
  }

  @action
  closePurchaseModal() {
    this.showPurchaseModal = false;
    this.selectedDurationType = null;
    // 不清空selectedPackage，保持选中状态（用户可能想重新打开）
  }
  
  @action
  selectDuration(durationType) {
    this.selectedDurationType = durationType;
  }

  // 事件驱动的选择（避免在模板中使用 fn 创建闭包）
  @action
  handleCardClick(event) {
    const id = event?.currentTarget?.dataset?.pkgId;
    if (id === undefined) return;
    const pkg = this.packages.find(p => String(p.id) === String(id));
    if (pkg) {
      this.selectedPackage = pkg;
    }
  }

  @action
  handleDurationClick(event) {
    const t = event?.currentTarget?.dataset?.type;
    if (t === undefined) return;
    this.selectedDurationType = String(t);
  }

  @action
  async confirmPurchase() {
    if (!this.selectedPackage || !this.selectedDurationType) {
      alert("请选择购买时长");
      return;
    }
    // 前置校验：禁止降级购买（防止无谓请求）
    if (this.hasVip && this.selectedPackage?.level < this.vipLevel) {
      this.dialog.alert("不支持降级购买");
      return;
    }

    this.purchasing = true;

    try {
      const result = await ajax("/qd/vip/purchase", {
        type: "POST",
        data: { 
          package_id: this.selectedPackage.id,
          duration_type: this.selectedDurationType
        }
      });

      if (Array.isArray(result.warnings) && result.warnings.length > 0) {
        // eslint-disable-next-line no-console
        console.warn("[VIP Purchase] warnings:", result.warnings);
      }
      if (result.upgrade_applied) {
        // eslint-disable-next-line no-console
        console.info("[VIP Purchase] upgrade_calc:", result.upgrade_calc);
        // eslint-disable-next-line no-console
        console.info("[VIP Purchase] charged_amount:", result.charged_amount);
      }

      // 保存购买结果（避免展开运算符导致的问题）
      this.purchaseResult = result;
      this.purchaseResult.packageName = this.selectedPackage.name;
      this.purchaseResult.durationLabel = this.selectedDurationLabel;
      
      // 更新数据
      this.model.user_paid_coins = result.new_balance;
      this.model.current_vip = result.subscription;
      
      this.closePurchaseModal();
      
      // 显示成功模态框
      this.showSuccessModal = true;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.purchasing = false;
    }
  }

  @action
  closeSuccessModal() {
    this.showSuccessModal = false;
    this.purchaseResult = null;
    // 刷新页面数据
    window.location.reload();
  }

  @action
  stopPropagation(event) {
    event.stopPropagation();
  }

  @action
  goToRecharge() {
    window.location.href = "/qd/pay";
  }

  @action
  goToAdmin() {
    window.location.href = "/qd/vip/admin";
  }
}
