import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdVipAdminController extends Controller {
  @tracked showCreateModal = false;
  @tracked showEditModal = false;
  @tracked editingPackage = null;
  @tracked saving = false;

  // Tab state
  @tracked activeTab = "packages"; // 'packages' | 'users'

  // Users management state
  @tracked users = [];
  @tracked userLoading = false;
  @tracked userPage = 1;
  @tracked userTotalPages = 1;
  @tracked showUserEditModal = false;
  @tracked editingUser = null; // { user_id, username, vip_level, expires_at }
  @tracked savingUser = false;
  @tracked editVipLevel = 1;
  @tracked editExpireDate = ""; // YYYY-MM-DD
  @tracked editExpireTime = "23:59"; // HH:mm

  // 表单数据
  @tracked formName = "";
  @tracked formLevel = 1;
  @tracked formDescription = "";
  @tracked formPricingPlans = [
    { type: "monthly", label: "月付", days: 30, price: 0 }
  ];  // 默认包含月付方案
  @tracked formMakeupCards = 0;
  @tracked formAvatarFrameId = null;
  @tracked formBadgeId = null;
  @tracked formDailySigninBonus = 0;  // VIP每日签到额外积分
  @tracked formIsActive = true;
  @tracked formSortOrder = 0;

  get packages() {
    return this.model.packages || [];
  }

  // ===== Users Management =====
  @action
  handleTabClick(event) {
    const tab = event?.currentTarget?.dataset?.tab;
    if (!tab) return;
    this.activeTab = tab;
    if (tab === "users" && this.users.length === 0) {
      this.loadUsers(1);
    }
  }

  async loadUsers(page = 1) {
    this.userLoading = true;
    try {
      const data = await ajax("/qd/vip/admin/users", { data: { page } });
      this.users = data.users || [];
      this.userPage = data.meta?.page || page;
      this.userTotalPages = data.meta?.total_pages || 1;
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.userLoading = false;
    }
  }

  @action
  openUserEdit(event) {
    const id = event?.currentTarget?.dataset?.userId;
    if (!id) return;
    const user = this.users.find(u => String(u.user_id) === String(id));
    if (!user) return;
    this.editingUser = user;
    this.editVipLevel = user.vip_level || 1;
    // Split expires_at to date & time
    const d = user.expires_at ? new Date(user.expires_at) : new Date();
    const yyyy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, "0");
    const dd = String(d.getDate()).padStart(2, "0");
    const hh = String(d.getHours()).padStart(2, "0");
    const mi = String(d.getMinutes()).padStart(2, "0");
    this.editExpireDate = `${yyyy}-${mm}-${dd}`;
    this.editExpireTime = `${hh}:${mi}`;
    this.showUserEditModal = true;
  }

  @action
  closeUserEditModal() {
    this.showUserEditModal = false;
    this.editingUser = null;
  }

  @action
  updateUserVipLevel(event) {
    this.editVipLevel = parseInt(event?.target?.value || 1) || 1;
  }

  @action
  updateUserExpireDate(event) {
    this.editExpireDate = event?.target?.value || "";
  }

  @action
  updateUserExpireTime(event) {
    this.editExpireTime = event?.target?.value || "";
  }

  @action
  async saveUserEdit() {
    if (!this.editingUser) return;
    if (!this.editExpireDate) {
      alert("请选择到期日期");
      return;
    }
    const expiresAt = `${this.editExpireDate} ${this.editExpireTime || "23:59"}:59`;
    this.savingUser = true;
    try {
      const result = await ajax(`/qd/vip/admin/users/${this.editingUser.user_id}`, {
        type: "PUT",
        data: { vip_level: this.editVipLevel, expires_at: expiresAt }
      });
      // 更新行
      const idx = this.users.findIndex(u => u.user_id === this.editingUser.user_id);
      if (idx !== -1) {
        this.users[idx] = {
          ...this.users[idx],
          vip_level: result.user.vip_level,
          expires_at: result.user.expires_at,
          days_remaining: result.user.days_remaining
        };
        this.users = [...this.users];
      }
      this.closeUserEditModal();
      alert(result.message || "修改成功");
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.savingUser = false;
    }
  }

  @action
  usersPrevPage() {
    if (this.userPage > 1 && !this.userLoading) {
      this.loadUsers(this.userPage - 1);
    }
  }

  @action
  usersNextPage() {
    if (this.userPage < this.userTotalPages && !this.userLoading) {
      this.loadUsers(this.userPage + 1);
    }
  }

  @action
  async cancelUserVip(event) {
    const id = event?.currentTarget?.dataset?.userId;
    if (!id) return;
    if (!confirm("确定要取消该用户VIP吗？这将撤回所有套餐奖励。")) return;
    this.userLoading = true;
    try {
      const result = await ajax(`/qd/vip/admin/users/${id}`, { type: "DELETE" });
      this.users = this.users.filter(u => String(u.user_id) !== String(id));
      alert(result.message || "已取消该用户VIP");
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.userLoading = false;
    }
  }

  get coinName() {
    return this.model.paid_coin_name || "付费币";
  }

  get hasUsers() {
    return this.users && this.users.length > 0;
  }

  get durationTypes() {
    return [
      { value: "monthly", label: "月付", days: 30 },
      { value: "quarterly", label: "季付", days: 90 },
      { value: "annual", label: "年付", days: 365 }
    ];
  }
  
  get hasPricingPlans() {
    return this.formPricingPlans && this.formPricingPlans.length > 0;
  }

  @action
  openCreateModal() {
    this.resetForm();
    console.log("[VIP Admin] Opening create modal, pricing plans:", this.formPricingPlans);
    this.showCreateModal = true;
  }

  @action
  closeCreateModal() {
    this.showCreateModal = false;
    this.resetForm();
  }

  @action
  openEditModal(pkg) {
    this.editingPackage = pkg;
    this.formName = pkg.name;
    this.formLevel = pkg.level;
    this.formDescription = pkg.description || "";
    
    // 加载定价方案
    if (pkg.pricing_plans && pkg.pricing_plans.length > 0) {
      this.formPricingPlans = pkg.pricing_plans.map(p => ({
        type: p.type,
        label: p.label,
        days: p.days,
        price: p.price
      }));
    } else {
      // 向后兼容：从旧字段创建
      this.formPricingPlans = [{
        type: pkg.duration_type,
        label: pkg.duration_label,
        days: pkg.duration_days,
        price: pkg.price
      }];
    }
    
    this.formMakeupCards = pkg.rewards?.makeup_cards || 0;
    this.formAvatarFrameId = pkg.rewards?.avatar_frame_id || null;
    this.formBadgeId = pkg.rewards?.badge_id || null;
    this.formDailySigninBonus = pkg.daily_signin_bonus || 0;
    this.formIsActive = pkg.is_active;
    this.formSortOrder = pkg.sort_order || 0;
    this.showEditModal = true;
  }

  @action
  closeEditModal() {
    this.showEditModal = false;
    this.editingPackage = null;
    this.resetForm();
  }

  // 定价方案管理
  @action
  addPricingPlan(type) {
    const durationType = this.durationTypes.find(t => t.value === type);
    if (!durationType) return;
    
    // 检查是否已存在
    if (this.formPricingPlans.some(p => p.type === type)) {
      alert("该时长类型已存在");
      return;
    }
    
    this.formPricingPlans = [
      ...this.formPricingPlans,
      {
        type: type,
        label: durationType.label,
        days: durationType.days,
        price: 0
      }
    ];
  }
  
  @action
  removePricingPlan(type) {
    this.formPricingPlans = this.formPricingPlans.filter(p => p.type !== type);
  }
  
  @action
  updatePlanPrice(type, event) {
    const price = event.target.value; // 保持字符串，允许输入过程
    const plan = this.formPricingPlans.find(p => p.type === type);
    if (plan) {
      plan.price = price;
    }
  }

  @action
  async createPackage() {
    if (!this.validateForm()) return;

    this.saving = true;
    
    const formData = this.getFormData();
    console.log("[VIP Admin] Creating package with data:", formData);
    console.log("[VIP Admin] pricing_plans type:", typeof formData.pricing_plans);
    console.log("[VIP Admin] pricing_plans is array:", Array.isArray(formData.pricing_plans));

    try {
      const result = await ajax("/qd/vip/admin/packages", {
        type: "POST",
        data: JSON.stringify(formData),
        contentType: "application/json",
        dataType: "json"
      });

      alert(result.message || "套餐创建成功！");
      
      // 更新列表
      this.model.packages.pushObject(result.package);
      
      this.closeCreateModal();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async updatePackage() {
    if (!this.validateForm() || !this.editingPackage) return;

    this.saving = true;

    try {
      const result = await ajax(`/qd/vip/admin/packages/${this.editingPackage.id}`, {
        type: "PUT",
        data: JSON.stringify(this.getFormData()),
        contentType: "application/json",
        dataType: "json"
      });

      alert(result.message || "套餐更新成功！");
      
      // 更新列表中的数据
      const index = this.model.packages.findIndex(p => p.id === this.editingPackage.id);
      if (index !== -1) {
        this.model.packages[index] = result.package;
        this.model.packages = [...this.model.packages]; // 触发更新
      }
      
      this.closeEditModal();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.saving = false;
    }
  }

  @action
  async deletePackage(pkg) {
    if (!confirm(`确定要删除套餐"${pkg.name}"吗？\n\n注意：如果该套餐有活跃订阅将无法删除。`)) {
      return;
    }

    try {
      await ajax(`/qd/vip/admin/packages/${pkg.id}`, {
        type: "DELETE"
      });

      alert("套餐已删除");
      
      // 从列表中移除
      this.model.packages = this.model.packages.filter(p => p.id !== pkg.id);
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  async toggleActive(pkg) {
    try {
      await ajax(`/qd/vip/admin/packages/${pkg.id}`, {
        type: "PUT",
        data: { is_active: !pkg.is_active }
      });

      // 更新本地数据
      pkg.is_active = !pkg.is_active;
      this.model.packages = [...this.model.packages]; // 触发更新
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  goToVipPage() {
    window.location.href = "/qd/vip";
  }

  @action
  stopPropagation(event) {
    event.stopPropagation();
  }

  // 表单更新方法
  @action
  updateFormName(event) {
    this.formName = event.target.value;
  }

  @action
  updateFormLevel(event) {
    this.formLevel = parseInt(event.target.value) || 1;
  }

  @action
  updateFormDescription(event) {
    this.formDescription = event.target.value;
  }

  @action
  updateFormDurationDays(event) {
    this.formDurationDays = parseInt(event.target.value) || 30;
  }

  @action
  updateFormPrice(event) {
    this.formPrice = parseInt(event.target.value) || 0;
  }

  @action
  updateFormMakeupCards(event) {
    this.formMakeupCards = parseInt(event.target.value) || 0;
  }

  @action
  updateFormAvatarFrameId(event) {
    const value = event.target.value;
    this.formAvatarFrameId = value ? parseInt(value) : null;
  }

  @action
  updateFormBadgeId(event) {
    const value = event.target.value;
    this.formBadgeId = value ? parseInt(value) : null;
  }

  @action
  updateFormDailySigninBonus(event) {
    this.formDailySigninBonus = parseInt(event.target.value) || 0;
  }

  @action
  updateFormIsActive(event) {
    this.formIsActive = event.target.checked;
  }

  @action
  updateFormSortOrder(event) {
    this.formSortOrder = parseInt(event.target.value) || 0;
  }

  // 辅助方法
  resetForm() {
    this.formName = "";
    this.formLevel = 1;
    this.formDescription = "";
    this.formPricingPlans = [
      { type: "monthly", label: "月付", days: 30, price: 0 }
    ];
    this.formMakeupCards = 0;
    this.formAvatarFrameId = null;
    this.formBadgeId = null;
    this.formDailySigninBonus = 0;
    this.formIsActive = true;
    this.formSortOrder = 0;
  }

  validateForm() {
    if (!this.formName.trim()) {
      alert("请输入套餐名称");
      return false;
    }
    if (this.formLevel < 1) {
      alert("VIP等级必须大于0");
      return false;
    }
    if (!this.formPricingPlans || this.formPricingPlans.length === 0) {
      alert("请至少添加一个定价方案");
      return false;
    }
    for (const plan of this.formPricingPlans) {
      if (plan.price < 0) {
        alert(`${plan.label}的价格不能为负数`);
        return false;
      }
    }
    return true;
  }

  getFormData() {
    console.log("[VIP Admin] Current formPricingPlans:", this.formPricingPlans);
    
    const pricingPlans = this.formPricingPlans.map(p => ({
      type: p.type,
      days: parseInt(p.days) || 0,
      price: parseInt(p.price) || 0
    }));
    
    console.log("[VIP Admin] Processed pricing_plans:", pricingPlans);
    
    return {
      name: this.formName,
      level: this.formLevel,
      description: this.formDescription,
      pricing_plans: pricingPlans,
      makeup_cards: parseInt(this.formMakeupCards) || 0,
      avatar_frame_id: this.formAvatarFrameId ? parseInt(this.formAvatarFrameId) : 0,
      badge_id: this.formBadgeId ? parseInt(this.formBadgeId) : 0,
      daily_signin_bonus: parseInt(this.formDailySigninBonus) || 0,
      is_active: this.formIsActive,
      sort_order: parseInt(this.formSortOrder) || 0
    };
  }
}
