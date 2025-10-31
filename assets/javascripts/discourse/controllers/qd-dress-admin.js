import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdDressAdminController extends Controller {
  @service dialog;
  
  @tracked currentTab = "frames"; // frames, badges, grants
  @tracked frames = [];
  @tracked badges = [];
  @tracked grants = [];
  @tracked grantsSummary = {};
  @tracked isLoading = false;
  
  // 上传相关
  @tracked showUploadModal = false;
  @tracked uploadType = "frame"; // frame or badge
  @tracked badgeUploadType = "image"; // image or text
  
  // 头像框参数
  @tracked frameName = "";
  @tracked frameWidth = 70;
  @tracked frameHeight = 70;
  @tracked frameTop = 10;
  @tracked frameLeft = -10;
  
  // 勋章参数
  @tracked badgeName = "";
  @tracked badgeHeight = 25;
  @tracked badgeText = "";
  @tracked badgeStyle = "";
  @tracked selectedStylePreset = "";
  
  // 参数调整
  @tracked showParamsModal = false;
  @tracked editingItem = null;
  @tracked editingType = null;
  
  // 授予相关
  @tracked showGrantModal = false;
  @tracked grantUsername = "";
  @tracked grantDecorationType = "avatar_frame";
  @tracked grantDecorationId = null;
  @tracked grantExpiresInDays = 0;
  @tracked grantReason = "";
  @tracked grantsFilter = "all"; // all, active, expired, revoked
  
  // 勋章样式预设
  stylePresets = [
    { id: "", name: "自定义", style: "" },
    { id: "vip-gold", name: "VIP金色", style: "background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" },
    { id: "admin-red", name: "管理员红", style: "background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" },
    { id: "mod-blue", name: "版主蓝", style: "background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" },
    { id: "mvp-purple", name: "MVP紫", style: "background: linear-gradient(135deg, #a855f7 0%, #9333ea 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" },
  ];

  get filteredGrants() {
    if (!this.grants) return [];
    
    switch (this.grantsFilter) {
      case 'active':
        return this.grants.filter(g => g.active && !g.revoked);
      case 'expired':
        return this.grants.filter(g => g.expired);
      case 'revoked':
        return this.grants.filter(g => g.revoked);
      default:
        return this.grants;
    }
  }

  @action
  setTab(tab) {
    this.currentTab = tab;
    if (tab === 'grants') {
      this.loadGrants();
    }
  }

  @action
  async loadGrants() {
    try {
      const response = await ajax("/qd/dress/grants", {
        type: "GET",
        data: { status: this.grantsFilter }
      });
      this.grants = response.grants;
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  setGrantsFilter(filter) {
    this.grantsFilter = filter;
    this.loadGrants();
  }

  @action
  showUploadFrameModal() {
    this.uploadType = "frame";
    this.frameName = "";
    this.frameWidth = 64;
    this.frameHeight = 64;
    this.frameTop = -8;
    this.frameLeft = -8;
    this.showUploadModal = true;
  }

  @action
  showUploadBadgeModal(type) {
    this.uploadType = "badge";
    this.badgeUploadType = type;
    this.badgeName = "";
    this.badgeHeight = 25;
    this.badgeText = "";
    this.badgeStyle = "";
    this.selectedStylePreset = "";
    this.showUploadModal = true;
  }

  @action
  closeUploadModal() {
    this.showUploadModal = false;
  }

  @action
  selectStylePreset(event) {
    const presetId = event.target.value;
    this.selectedStylePreset = presetId;
    
    const preset = this.stylePresets.find(p => p.id === presetId);
    if (preset) {
      this.badgeStyle = preset.style;
    }
  }

  @action
  async uploadFrame() {
    // 验证名称
    if (!this.frameName || !this.frameName.trim()) {
      this.dialog.alert("请输入头像框名称");
      return;
    }
    
    // 验证名称格式（只允许字母、数字、下划线和连字符）
    if (!/^[a-zA-Z0-9_-]+$/.test(this.frameName.trim())) {
      this.dialog.alert("名称只能包含字母、数字、下划线和连字符");
      return;
    }
    
    const fileInput = document.getElementById("frame-file-input");
    const file = fileInput?.files[0];
    
    if (!file) {
      this.dialog.alert("请选择文件");
      return;
    }
    
    this.isLoading = true;
    
    try {
      const formData = new FormData();
      formData.append("file", file);
      formData.append("name", this.frameName.trim());
      formData.append("width", this.frameWidth);
      formData.append("height", this.frameHeight);
      formData.append("top", this.frameTop);
      formData.append("left", this.frameLeft);
      
      await ajax("/qd/dress/upload-frame", {
        type: "POST",
        data: formData,
        processData: false,
        contentType: false
      });
      
      this.dialog.alert("✅ 头像框上传成功！");
      this.showUploadModal = false;
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async uploadBadge() {
    if (!this.badgeName.trim()) {
      this.dialog.alert("请输入勋章名称");
      return;
    }
    
    this.isLoading = true;
    
    try {
      const formData = new FormData();
      formData.append("name", this.badgeName);
      formData.append("type", this.badgeUploadType);
      
      if (this.badgeUploadType === "text") {
        if (!this.badgeText.trim()) {
          this.dialog.alert("请输入文字内容");
          this.isLoading = false;
          return;
        }
        formData.append("text", this.badgeText);
        formData.append("style", this.badgeStyle);
      } else {
        const fileInput = document.getElementById("badge-file-input");
        const file = fileInput?.files[0];
        
        if (!file) {
          this.dialog.alert("请选择文件");
          this.isLoading = false;
          return;
        }
        
        formData.append("file", file);
        formData.append("height", this.badgeHeight);
      }
      
      await ajax("/qd/dress/upload-badge", {
        type: "POST",
        data: formData,
        processData: false,
        contentType: false
      });
      
      this.dialog.alert("✅ 勋章上传成功！");
      this.showUploadModal = false;
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  showEditParams(item, type) {
    this.editingItem = item;
    this.editingType = type;
    
    if (type === 'frame') {
      this.frameWidth = item.width || 70;
      this.frameHeight = item.height || 70;
      this.frameTop = item.top !== undefined ? item.top : 10;
      this.frameLeft = item.left !== undefined ? item.left : -10;
    } else {
      this.badgeHeight = item.height || 25;
    }
    
    this.showParamsModal = true;
  }

  @action
  closeParamsModal() {
    this.showParamsModal = false;
    this.editingItem = null;
    this.editingType = null;
  }

  @action
  async saveParams() {
    try {
      if (this.editingType === 'frame') {
        await ajax("/qd/dress/update-frame-params", {
          type: "PUT",
          data: {
            frame_id: this.editingItem.id,
            width: this.frameWidth,
            height: this.frameHeight,
            top: this.frameTop,
            left: this.frameLeft
          }
        });
      } else {
        await ajax("/qd/dress/update-badge-params", {
          type: "PUT",
          data: {
            badge_id: this.editingItem.id,
            height: this.badgeHeight
          }
        });
      }
      
      this.dialog.alert("✅ 参数更新成功！");
      this.showParamsModal = false;
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  deleteItem(item, type) {
    const itemName = type === 'frame' ? '头像框' : '勋章';
    
    this.dialog.yesNoConfirm({
      message: `确定要删除这个${itemName}吗？所有授予记录将被撤销。`,
      didConfirm: async () => {
        try {
          const endpoint = type === 'frame' ? '/qd/dress/delete-frame' : '/qd/dress/delete-badge';
          const idParam = type === 'frame' ? 'frame_id' : 'badge_id';
          
          await ajax(endpoint, {
            type: "DELETE",
            data: { [idParam]: item.id }
          });
          
          this.dialog.alert(`✅ ${itemName}已删除！`);
          window.location.reload();
        } catch (error) {
          popupAjaxError(error);
        }
      }
    });
  }

  @action
  openGrantModal(item, type) {
    this.grantDecorationType = type === 'frame' ? 'avatar_frame' : 'badge';
    this.grantDecorationId = item.id;
    this.grantUsername = "";
    this.grantExpiresInDays = 0;
    this.grantReason = "";
    this.showGrantModal = true;
  }

  @action
  closeGrantModal() {
    this.showGrantModal = false;
  }

  @action
  async submitGrant() {
    if (!this.grantUsername.trim()) {
      this.dialog.alert("请输入用户名");
      return;
    }
    
    this.isLoading = true;
    
    try {
      // 先查找用户ID
      const userResponse = await ajax(`/u/${this.grantUsername}.json`);
      const userId = userResponse.user.id;
      
      await ajax("/qd/dress/grant", {
        type: "POST",
        data: {
          user_id: userId,
          decoration_type: this.grantDecorationType,
          decoration_id: this.grantDecorationId,
          expires_in_days: this.grantExpiresInDays,
          reason: this.grantReason
        }
      });
      
      this.dialog.alert("✅ 装饰授予成功！");
      this.showGrantModal = false;
      this.loadGrants();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async revokeGrant(grant) {
    const confirmed = await this.dialog.confirm({
      message: `确定要撤销对 ${grant.username} 的 ${grant.decoration_name} 授予吗？`,
      confirmButtonLabel: "确认撤销",
      cancelButtonLabel: "取消"
    });
    
    if (!confirmed) return;
    
    try {
      await ajax("/qd/dress/revoke", {
        type: "POST",
        data: {
          grant_id: grant.id,
          reason: "管理员撤销"
        }
      });
      
      this.dialog.alert("✅ 授予已撤销！");
      this.loadGrants();
    } catch (error) {
      popupAjaxError(error);
    }
  }
  
  @action
  async deleteRevokedGrants() {
    const revokedCount = this.grants.filter(g => g.revoked).length;
    
    if (revokedCount === 0) {
      this.dialog.alert("没有已撤销的记录");
      return;
    }
    
    const confirmed = await this.dialog.confirm({
      message: `确定要删除 ${revokedCount} 条已撤销的记录吗？\n\n此操作不可恢复！`,
      confirmButtonLabel: "确认删除",
      cancelButtonLabel: "取消",
      confirmButtonClass: "btn-danger"
    });
    
    if (!confirmed) return;
    
    try {
      await ajax("/qd/dress/delete_revoked_grants", {
        type: "DELETE"
      });
      
      this.dialog.alert(`✅ 已删除 ${revokedCount} 条撤销记录！`);
      this.loadGrants();
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  stopPropagation(event) {
    event.stopPropagation();
  }

  @action
  formatDuration(seconds) {
    if (!seconds) return "永久";
    
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    
    if (days > 0) {
      return `${days}天${hours}小时`;
    }
    return `${hours}小时`;
  }

  @action
  formatDate(dateStr) {
    if (!dateStr) return "-";
    return new Date(dateStr).toLocaleString('zh-CN');
  }
}
