import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdCenterWorkController extends Controller {
  @service dialog;
  @service currentUser;
  @service router;
  
  @tracked showDonationModal = false;
  @tracked donationAmount = 100;
  @tracked donationCurrency = "jifen"; // jifen 或 paid_coin
  @tracked isDonating = false;
  @tracked showShareModal = false;
  
  // 使用tracked存储作品数据，确保响应式更新
  @tracked workData = null;
  @tracked creatorData = null;
  @tracked userJifenData = 0;
  @tracked userPaidCoinData = 0;
  
  get work() {
    return this.workData || this.model.work;
  }
  
  get creator() {
    return this.creatorData || this.model.creator;
  }
  
  get isOwnWork() {
    return this.currentUser && this.currentUser.id === this.work.user_id;
  }
  
  get shareUrl() {
    return `${window.location.origin}/qd/center/zp/${this.work.id}`;
  }
  
  get jifenName() {
    return this.model.jifen_name || "积分";
  }
  
  get paidCoinName() {
    return this.model.paid_coin_name || "付费币";
  }
  
  get userJifen() {
    return this.userJifenData || this.model.user_jifen || 0;
  }
  
  get userPaidCoin() {
    return this.userPaidCoinData || this.model.user_paid_coin || 0;
  }
  
  get maxDonationsPerWork() {
    return this.model.max_donations_per_work || 0;
  }
  
  get canDonate() {
    if (!this.currentUser) return false;
    if (this.isOwnWork) return false;
    if (this.maxDonationsPerWork > 0 && this.work.user_donation_count >= this.maxDonationsPerWork) return false;
    return true;
  }
  
  get donationLimitReached() {
    return this.maxDonationsPerWork > 0 && this.work.user_donation_count >= this.maxDonationsPerWork;
  }
  
  // 检测来源是否是帖子页面
  get isFromTopic() {
    const referrer = document.referrer;
    const currentOrigin = window.location.origin;
    // 检查是否从当前域名的/t/路径来的
    return referrer.startsWith(currentOrigin + "/t/");
  }
  
  get backUrl() {
    if (this.isFromTopic) {
      return document.referrer;
    }
    return "/qd/center";
  }
  
  get backButtonText() {
    return this.isFromTopic ? "返回帖子" : "返回作品墙";
  }
  
  @action
  goBack() {
    window.location.href = this.backUrl;
  }
  
  @action
  async viewPost() {
    // 记录浏览量
    try {
      await ajax("/qd/center/click", {
        type: "POST",
        data: { work_id: this.work.id }
      });
      // 刷新浏览量数据
      await this.refreshWorkData();
    } catch (error) {
      console.error("记录浏览失败:", error);
    }
    
    // 打开原帖
    window.open(this.work.post_url, '_blank');
  }
  
  @action
  async toggleLike() {
    if (!this.currentUser) {
      this.dialog.alert("请先登录");
      return;
    }
    
    try {
      const result = await ajax("/qd/center/toggle_like", {
        type: "POST",
        data: { work_id: this.work.id }
      });
      
      // 重新加载数据刷新状态
      await this.refreshWorkData();
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    }
  }
  
  async refreshWorkData() {
    try {
      const data = await ajax(`/qd/center/work/${this.work.id}.json`);
      
      // 更新tracked属性以触发响应式更新
      this.workData = { ...data.work };
      this.creatorData = { ...data.creator };
      this.userJifenData = data.user_jifen;
      this.userPaidCoinData = data.user_paid_coin;
      
      // 同时更新model以保持一致性
      Object.assign(this.model, data);
    } catch (error) {
      console.error("刷新作品数据失败:", error);
    }
  }
  
  @action
  openDonationModal() {
    if (!this.currentUser) {
      this.dialog.alert("请先登录后再打赏");
      return;
    }
    
    if (this.isOwnWork) {
      this.dialog.alert("不能打赏自己的作品");
      return;
    }
    
    if (this.donationLimitReached) {
      this.dialog.alert(`您已达到该作品的打赏次数上限（${this.maxDonationsPerWork}次）`);
      return;
    }
    
    this.donationAmount = 100;
    this.donationCurrency = "jifen";
    this.showDonationModal = true;
  }
  
  @action
  closeDonationModal() {
    this.showDonationModal = false;
  }
  
  @action
  updateDonationAmount(event) {
    this.donationAmount = parseInt(event.target.value) || 0;
  }
  
  @action
  selectCurrency(currency) {
    this.donationCurrency = currency;
  }
  
  @action
  async confirmDonation() {
    if (this.donationAmount <= 0) {
      this.dialog.alert("打赏金额必须大于0");
      return;
    }
    
    const maxBalance = this.donationCurrency === "jifen" ? this.userJifen : this.userPaidCoin;
    const currencyName = this.donationCurrency === "jifen" ? this.jifenName : this.paidCoinName;
    
    if (this.donationAmount > maxBalance) {
      this.dialog.alert(`${currencyName}余额不足`);
      return;
    }
    
    this.isDonating = true;
    
    try {
      const result = await ajax("/qd/center/donate", {
        type: "POST",
        data: {
          work_id: this.work.id,
          amount: this.donationAmount,
          currency_type: this.donationCurrency
        }
      });
      
      if (result.success) {
        this.dialog.alert("打赏成功！感谢您的支持！");
        this.closeDonationModal();
        
        // 刷新数据（包括用户余额和打赏统计）
        await this.refreshWorkData();
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isDonating = false;
    }
  }
  
  @action
  openShareModal() {
    this.showShareModal = true;
  }
  
  @action
  closeShareModal() {
    this.showShareModal = false;
  }
  
  @action
  async copyShareLink() {
    try {
      await navigator.clipboard.writeText(this.shareUrl);
      this.dialog.alert("链接已复制到剪贴板");
      this.closeShareModal();
    } catch (error) {
      this.dialog.alert("复制失败，请手动复制");
    }
  }
  
  @action
  stopPropagation(event) {
    event.stopPropagation();
  }
}
