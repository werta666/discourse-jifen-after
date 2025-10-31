import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { inject as service } from "@ember/service";

export default class QdCenterAdminController extends Controller {
  @service dialog;
  
  @tracked activeTab = "pending"; // pending / approved / shop / applications / settings
  @tracked rejectReason = "";
  @tracked rejectingWorkId = null;
  @tracked showRejectModal = false;
  @tracked showStatusModal = false;
  @tracked updatingWorkId = null;
  @tracked newStatus = "";
  
  // 创作者申请相关
  @tracked pendingApplications = [];
  @tracked rejectingApplicationId = null;
  @tracked showRejectApplicationModal = false;
  @tracked applicationRejectReason = "";
  @tracked applicationRefund = true;
  
  // 创作者管理相关
  @tracked creatorsList = [];
  @tracked revokingCreator = null;
  @tracked showRevokeCreatorModal = false;
  @tracked revokeReason = "";
  
  @tracked minLikes = 10;
  @tracked minClicks = 50;
  @tracked commissionRate = 0;
  @tracked maxDonationsPerWork = 0;
  @tracked savingSettings = false;
  
  @tracked whitelistText = "";
  @tracked likeWeight = 1;
  @tracked clickWeight = 1;
  @tracked paidCoinThreshold = 100;
  @tracked paidCoinMultiplier = 2;
  @tracked jifenWeight = 1;
  @tracked heatThresholds = [100, 200, 300, 500];
  @tracked recalculating = false;
  @tracked settingsLoaded = false;
  
  @tracked pendingWorks = [];
  @tracked approvedWorks = [];
  @tracked pendingShopApplications = [];
  @tracked approvedShopWorks = [];
  @tracked stats = {};
  
  @action
  initializeData() {
    if (!this.model) {
      return;
    }
    
    this.pendingWorks = this.model.pending_works || [];
    this.approvedWorks = this.model.approved_works || [];
    this.pendingShopApplications = this.model.pending_shop_applications || [];
    this.approvedShopWorks = this.model.approved_shop_works || [];
    this.pendingApplications = this.model.pending_applications || [];
    this.creatorsList = this.model.creators_list || [];
    this.stats = this.model.stats || {};
    
    // 第一次初始化时设置配置
    if (!this.settingsLoaded) {
      this.setupSettings();
      this.settingsLoaded = true;
    }
  }
  
  @action
  setupSettings() {
    if (!this.model) return;
    
    const standards = this.model.shop_standards || {};
    this.minLikes = standards.min_likes || 10;
    this.minClicks = standards.min_clicks || 50;
    this.commissionRate = this.model.commission_rate || 0;
    
    // 打赏次数限制
    this.maxDonationsPerWork = this.model.max_donations_per_work || 0;
    
    // 白名单
    const whitelist = this.model.whitelist || [];
    this.whitelistText = whitelist.join('\n');
    
    // 热度规则 - 使用独立的 tracked 属性
    const heat_rules = this.model.heat_rules || {};
    
    this.likeWeight = heat_rules.like_weight || heat_rules['like_weight'] || 1;
    this.clickWeight = heat_rules.click_weight || heat_rules['click_weight'] || 1;
    this.paidCoinThreshold = heat_rules.paid_coin_threshold || heat_rules['paid_coin_threshold'] || 100;
    this.paidCoinMultiplier = heat_rules.paid_coin_base_multiplier || heat_rules['paid_coin_base_multiplier'] || 2;
    this.jifenWeight = heat_rules.jifen_weight || heat_rules['jifen_weight'] || 1;
    
    // 火苗阈值
    const heatConfig = this.model.heat_config || { thresholds: [100, 200, 300, 500] };
    this.heatThresholds = [...(heatConfig.thresholds || [100, 200, 300, 500])];
  }
  
  @action
  switchTab(tab) {
    this.activeTab = tab;
    // 确保数据已初始化
    if (!this.stats || Object.keys(this.stats).length === 0) {
      this.initializeData();
    }
  }
  
  @action
  async approveWork(work) {
    if (!confirm(`确认审核通过作品"${work.title || '作品 #' + work.id}"？`)) {
      return;
    }
    
    try {
      await ajax("/qd/center/admin/approve_work", {
        type: "POST",
        data: { work_id: work.id }
      });
      
      this.dialog.alert("审核通过");
      await this.refreshData();
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    }
  }
  
  @action
  openRejectModal(work) {
    this.rejectingWorkId = work.id;
    this.rejectReason = "";
    this.showRejectModal = true;
  }
  
  @action
  closeRejectModal() {
    this.showRejectModal = false;
    this.rejectingWorkId = null;
    this.rejectReason = "";
  }
  
  @action
  updateRejectReason(event) {
    this.rejectReason = event.target.value;
  }
  
  @action
  async confirmReject() {
    if (!this.rejectReason.trim()) {
      alert("请填写驳回原因");
      return;
    }
    
    try {
      await ajax("/qd/center/admin/reject_work", {
        type: "POST",
        data: {
          work_id: this.rejectingWorkId,
          reason: this.rejectReason
        }
      });
      
      this.dialog.alert("已驳回");
      this.closeRejectModal();
      await this.refreshData();
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    }
  }
  
  @action
  async approveShop(work) {
    if (!confirm(`确认通过上架申请"${work.title || '作品 #' + work.id}"？`)) {
      return;
    }
    
    try {
      await ajax("/qd/center/admin/approve_shop", {
        type: "POST",
        data: { work_id: work.id }
      });
      
      this.dialog.alert("已批准上架");
      await this.refreshData();
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    }
  }
  
  @action
  async rejectShop(work) {
    const reason = prompt("请输入驳回原因：");
    if (!reason) return;
    
    try {
      await ajax("/qd/center/admin/reject_shop", {
        type: "POST",
        data: {
          work_id: work.id,
          reason: reason
        }
      });
      
      this.dialog.alert("已驳回");
      await this.refreshData();
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    }
  }
  
  @action
  updateMinLikes(event) {
    this.minLikes = parseInt(event.target.value) || 0;
  }
  
  @action
  updateMinClicks(event) {
    this.minClicks = parseInt(event.target.value) || 0;
  }
  
  @action
  updateCommissionRate(event) {
    this.commissionRate = parseFloat(event.target.value) || 0;
  }
  
  @action
  updateMaxDonations(event) {
    this.maxDonationsPerWork = parseInt(event.target.value) || 0;
  }
  
  @action
  async saveShopStandards() {
    this.savingSettings = true;
    
    try {
      await ajax("/qd/center/admin/update_shop_standards", {
        type: "POST",
        data: {
          min_likes: this.minLikes,
          min_clicks: this.minClicks
        }
      });
      
      this.dialog.alert("上架标准已更新");
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    } finally {
      this.savingSettings = false;
    }
  }
  
  @action
  async saveCommissionRate() {
    this.savingSettings = true;
    
    try {
      await ajax("/qd/center/admin/update_commission_rate", {
        type: "POST",
        data: { rate: this.commissionRate }
      });
      
      this.dialog.alert("抽成比例已更新");
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    } finally {
      this.savingSettings = false;
    }
  }
  
  @action
  async saveMaxDonations() {
    this.savingSettings = true;
    
    try {
      const result = await ajax("/qd/center/admin/update_max_donations", {
        type: "POST",
        data: { max_count: this.maxDonationsPerWork }
      });
      
      this.dialog.alert(result.message || "打赏次数限制已更新");
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    } finally {
      this.savingSettings = false;
    }
  }
  
  @action
  openStatusModal(work) {
    this.updatingWorkId = work.id;
    this.newStatus = work.status;
    this.rejectReason = "";
    this.showStatusModal = true;
  }
  
  @action
  closeStatusModal() {
    this.showStatusModal = false;
    this.updatingWorkId = null;
    this.newStatus = "";
    this.rejectReason = "";
  }
  
  @action
  selectStatus(status) {
    this.newStatus = status;
  }
  
  @action
  async confirmStatusUpdate() {
    if (this.newStatus === 'rejected' && !this.rejectReason.trim()) {
      alert("请填写驳回原因");
      return;
    }
    
    try {
      await ajax("/qd/center/admin/update_work_status", {
        type: "POST",
        data: {
          work_id: this.updatingWorkId,
          status: this.newStatus,
          reason: this.rejectReason
        }
      });
      
      this.dialog.alert("状态已更新");
      this.closeStatusModal();
      await this.refreshData();
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    }
  }
  
  @action
  async deleteWork(work) {
    if (!confirm(`确认删除作品"${work.title || '作品 #' + work.id}"？此操作不可恢复！`)) {
      return;
    }
    
    try {
      await ajax(`/qd/center/admin/delete_work`, {
        type: "DELETE",
        data: { work_id: work.id }
      });
      
      this.dialog.alert("作品已删除");
      await this.refreshData();
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "删除失败");
    }
  }
  
  @action
  goToCenter() {
    window.location.href = "/qd/center";
  }
  
  @action
  stopPropagation(event) {
    event.stopPropagation();
  }
  
  // 白名单管理
  @action
  updateWhitelist(event) {
    this.whitelistText = event.target.value;
  }
  
  @action
  async saveWhitelist() {
    this.savingSettings = true;
    
    try {
      const usernames = this.whitelistText.split('\n')
        .map(u => u.trim())
        .filter(u => u.length > 0);
      
      const result = await ajax("/qd/center/admin/update_whitelist", {
        type: "POST",
        data: { usernames: usernames }
      });
      
      if (result.invalid_usernames && result.invalid_usernames.length > 0) {
        this.dialog.alert(`白名单已更新，但以下用户不存在：${result.invalid_usernames.join(', ')}`);
      } else {
        this.dialog.alert("白名单已更新");
      }
      
      // 更新显示
      this.whitelistText = result.whitelist.join('\n');
      this.model.whitelist = result.whitelist;
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    } finally {
      this.savingSettings = false;
    }
  }
  
  // 热度规则管理
  @action
  updateLikeWeight(event) {
    this.likeWeight = parseInt(event.target.value) || 0;
  }
  
  @action
  updateClickWeight(event) {
    this.clickWeight = parseInt(event.target.value) || 0;
  }
  
  @action
  updatePaidCoinThreshold(event) {
    this.paidCoinThreshold = parseInt(event.target.value) || 0;
  }
  
  @action
  updatePaidCoinMultiplier(event) {
    this.paidCoinMultiplier = parseInt(event.target.value) || 1;
  }
  
  @action
  updateJifenWeight(event) {
    this.jifenWeight = parseInt(event.target.value) || 0;
  }
  
  @action
  async saveHeatRules() {
    this.savingSettings = true;
    
    try {
      const heat_rules = {
        like_weight: this.likeWeight,
        click_weight: this.clickWeight,
        paid_coin_threshold: this.paidCoinThreshold,
        paid_coin_base_multiplier: this.paidCoinMultiplier,
        jifen_weight: this.jifenWeight
      };
      
      const result = await ajax("/qd/center/admin/update_heat_rules", {
        type: "POST",
        data: { heat_rules: heat_rules }
      });
      
      // 更新 model 以确保下次刷新时正确加载
      this.model.heat_rules = result.heat_rules || heat_rules;
      
      this.dialog.alert("热度规则已更新，所有作品热度已重新计算");
      
      // 刷新数据以显示最新的热度值
      await this.refreshData();
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    } finally {
      this.savingSettings = false;
    }
  }
  
  @action
  async recalculateAllHeat() {
    this.recalculating = true;
    
    try {
      const result = await ajax("/qd/center/admin/recalculate_heat", {
        type: "POST"
      });
      
      this.dialog.alert(result.message || "热度已重新计算");
      
      // 刷新数据以显示最新的热度值
      await this.refreshData();
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    } finally {
      this.recalculating = false;
    }
  }
  
  // 火苗颜色管理
  @action
  updateLowThreshold(event) {
    this.heatConfig = { 
      ...this.heatConfig, 
      low: { ...this.heatConfig.low, threshold: parseInt(event.target.value) || 0 }
    };
  }
  
  @action
  updateThreshold(index, event) {
    const value = parseInt(event.target.value) || 0;
    const newThresholds = [...this.heatThresholds];
    newThresholds[index] = value;
    this.heatThresholds = newThresholds;
  }
  
  @action
  async saveHeatConfig() {
    this.savingSettings = true;
    
    try {
      // 验证阈值递增
      for (let i = 0; i < this.heatThresholds.length - 1; i++) {
        if (this.heatThresholds[i] >= this.heatThresholds[i + 1]) {
          this.dialog.alert("阈值必须递增！");
          this.savingSettings = false;
          return;
        }
      }
      
      const result = await ajax("/qd/center/admin/update_heat_config", {
        type: "POST",
        data: { 
          heat_config: { 
            thresholds: this.heatThresholds 
          }
        }
      });
      
      // 更新 model 以确保下次刷新时正确加载
      this.model.heat_config = result.heat_config || { thresholds: this.heatThresholds };
      
      this.dialog.alert("火苗热度阈值已更新");
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "操作失败");
    } finally {
      this.savingSettings = false;
    }
  }
  
  async refreshData() {
    const newData = await ajax("/qd/center/admin");
    
    // 更新 tracked 属性以触发响应式更新
    this.pendingWorks = newData.pending_works || [];
    this.approvedWorks = newData.approved_works || [];
    this.pendingShopApplications = newData.pending_shop_applications || [];
    this.approvedShopWorks = newData.approved_shop_works || [];
    this.pendingApplications = newData.pending_applications || [];
    this.creatorsList = newData.creators_list || [];
    this.stats = newData.stats || {};
    
    // 更新 model 数据
    this.model.pending_works = newData.pending_works;
    this.model.approved_works = newData.approved_works;
    this.model.pending_shop_applications = newData.pending_shop_applications;
    this.model.approved_shop_works = newData.approved_shop_works;
    this.model.pending_applications = newData.pending_applications;
    this.model.stats = newData.stats;
    this.model.heat_rules = newData.heat_rules;
    this.model.heat_config = newData.heat_config;
    this.model.shop_standards = newData.shop_standards;
    this.model.commission_rate = newData.commission_rate;
    this.model.whitelist = newData.whitelist;
    this.model.max_donations_per_work = newData.max_donations_per_work;
    
    // 重新设置配置数据
    this.setupSettings();
  }
  
  // 创作者申请审核相关方法
  @action
  async approveApplication(application) {
    if (!confirm(`确定通过 ${application.username} 的创作者申请吗？`)) {
      return;
    }
    
    try {
      const result = await ajax("/qd/center/admin/approve_application", {
        type: "POST",
        data: { application_id: application.id }
      });
      
      if (result.success) {
        this.dialog.alert(result.message);
        await this.refreshData();
      }
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "审核失败");
    }
  }
  
  @action
  openRejectApplicationModal(application) {
    this.rejectingApplicationId = application.id;
    this.applicationRejectReason = "";
    this.applicationRefund = true;
    this.showRejectApplicationModal = true;
  }
  
  @action
  closeRejectApplicationModal() {
    this.showRejectApplicationModal = false;
    this.rejectingApplicationId = null;
    this.applicationRejectReason = "";
    this.applicationRefund = true;
  }
  
  @action
  updateApplicationRejectReason(event) {
    this.applicationRejectReason = event.target.value;
  }
  
  @action
  toggleApplicationRefund(event) {
    this.applicationRefund = event.target.checked;
  }
  
  @action
  async confirmRejectApplication() {
    if (!this.applicationRejectReason.trim()) {
      this.dialog.alert("请填写拒绝理由");
      return;
    }
    
    try {
      const result = await ajax("/qd/center/admin/reject_application", {
        type: "POST",
        data: {
          application_id: this.rejectingApplicationId,
          reason: this.applicationRejectReason,
          refund: this.applicationRefund
        }
      });
      
      if (result.success) {
        this.dialog.alert(result.message);
        this.closeRejectApplicationModal();
        await this.refreshData();
      }
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "拒绝失败");
    }
  }
  
  // 创作者管理相关方法
  @action
  openRevokeCreatorModal(creator) {
    this.revokingCreator = creator;
    this.revokeReason = "";
    this.showRevokeCreatorModal = true;
  }
  
  @action
  closeRevokeCreatorModal() {
    this.showRevokeCreatorModal = false;
    this.revokingCreator = null;
    this.revokeReason = "";
  }
  
  @action
  updateRevokeReason(event) {
    this.revokeReason = event.target.value;
  }
  
  @action
  async confirmRevokeCreator() {
    if (!this.revokeReason.trim()) {
      this.dialog.alert("请填写撤销理由");
      return;
    }
    
    if (!confirm(`确定要撤销 ${this.revokingCreator.username} 的创作者资格吗？此操作不可恢复！`)) {
      return;
    }
    
    try {
      const result = await ajax("/qd/center/admin/revoke_creator", {
        type: "POST",
        data: {
          username: this.revokingCreator.username,
          reason: this.revokeReason
        }
      });
      
      if (result.success) {
        this.dialog.alert(result.message);
        this.closeRevokeCreatorModal();
        await this.refreshData();
      }
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "撤销失败");
    }
  }
}
