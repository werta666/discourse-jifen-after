import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { inject as service } from "@ember/service";

export default class QdCenterController extends Controller {
  @service dialog;
  @service siteSettings;
  @service currentUser;
  
  @tracked showDonateModal = false;
  @tracked selectedWork = null;
  @tracked donateAmount = 0;
  @tracked selectedCurrency = "jifen"; // jifen or paid_coin
  @tracked donating = false;
  @tracked showCelebrationModal = false;
  @tracked celebrationData = null;
  @tracked displayWorks = [];
  
  get works() {
    // 如果有显示数据，使用显示数据；否则使用 model 数据
    const sourceWorks = this.displayWorks.length > 0 ? this.displayWorks : (this.model.works || []);
    const thresholds = this.model.heat_config?.thresholds || [100, 200, 300, 500];
    
    // 为每个作品添加热度颜色
    const enrichedWorks = sourceWorks.map(work => {
      const heatScore = work.heat_score || 0;
      let heatColor;
      
      if (heatScore < thresholds[0]) {
        heatColor = '#52C41A'; // 绿色
      } else if (heatScore < thresholds[1]) {
        heatColor = '#EB2F96'; // 粉色
      } else if (heatScore < thresholds[2]) {
        heatColor = '#FAAD14'; // 黄橙色
      } else if (heatScore < thresholds[3]) {
        heatColor = '#FF7875'; // 淡红
      } else {
        heatColor = '#FF4D4F'; // 赤红
      }
      
      return {
        ...work,
        heatColor: heatColor
      };
    });
    
    return enrichedWorks;
  }
  
  get jifenName() {
    return this.model.jifen_name || "积分";
  }
  
  get paidCoinName() {
    return this.model.paid_coin_name || "付费币";
  }
  
  get heatConfig() {
    return this.model.heat_config || {
      thresholds: [100, 200, 300, 500]
    };
  }
  
  get isCreator() {
    if (!this.currentUser) return false;
    
    // 管理员总是可以创作
    if (this.currentUser.admin) return true;
    
    // 检查是否在白名单中
    const whitelist = this.model.whitelist || [];
    return whitelist.includes(this.currentUser.username);
  }
  
  @action
  async likeWork(work) {
    if (!this.currentUser) {
      this.dialog.alert("请先登录");
      return;
    }
    
    try {
      const result = await ajax("/qd/center/like", {
        type: "POST",
        data: { work_id: work.id }
      });
      
      // 重新加载整个页面数据以确保刷新
      const newData = await ajax("/qd/center");
      
      // 更新 tracked 属性触发响应式更新
      this.displayWorks = [...newData.works];
      this.model.works = newData.works;
      this.model.heat_config = newData.heat_config;
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    }
  }
  
  @action
  async recordClick(work) {
    try {
      await ajax("/qd/center/click", {
        type: "POST",
        data: { work_id: work.id }
      });
      work.clicks_count += 1;
    } catch (error) {
      // 静默失败
    }
  }
  
  @action
  openDonateModal(work) {
    if (!this.currentUser) {
      alert("请先登录");
      return;
    }
    
    this.selectedWork = work;
    this.donateAmount = 0;
    this.selectedCurrency = "jifen";
    this.showDonateModal = true;
  }
  
  @action
  closeDonateModal() {
    this.showDonateModal = false;
    this.selectedWork = null;
    this.donateAmount = 0;
  }
  
  @action
  updateDonateAmount(event) {
    this.donateAmount = parseInt(event.target.value) || 0;
  }
  
  @action
  selectCurrency(currency) {
    this.selectedCurrency = currency;
  }
  
  @action
  async confirmDonate() {
    if (!this.selectedWork || this.donateAmount <= 0) {
      alert("请输入有效的打赏金额");
      return;
    }
    
    this.donating = true;
    
    try {
      const result = await ajax("/qd/center/donate", {
        type: "POST",
        data: {
          work_id: this.selectedWork.id,
          amount: this.donateAmount,
          currency_type: this.selectedCurrency
        }
      });
      
      this.closeDonateModal();
      
      // 显示庆祝模态框
      if (result.show_celebration) {
        this.celebrationData = result;
        this.showCelebrationModal = true;
      }
      
      // 刷新页面数据（包括打赏统计）
      const newData = await ajax("/qd/center");
      
      // 更新 tracked 属性触发响应式更新
      this.displayWorks = [...newData.works];
      this.model.works = newData.works;
      this.model.heat_config = newData.heat_config;
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "打赏失败");
    } finally {
      this.donating = false;
    }
  }
  
  @action
  closeCelebrationModal() {
    this.showCelebrationModal = false;
    this.celebrationData = null;
  }
  
  @action
  goToPost(work) {
    this.recordClick(work);
    window.open(work.post_url, '_blank');
  }
  
  @action
  goToMake() {
    window.location.href = "/qd/center/make";
  }
  
  @action
  goToAdmin() {
    window.location.href = "/qd/center/admin";
  }
  
  @action
  goToApply() {
    window.location.href = "/qd/apply";
  }
  
  @action
  stopPropagation(event) {
    event.stopPropagation();
  }
}
