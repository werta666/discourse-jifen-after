import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdTestController extends Controller {
  @service currentUser;
  @service dialog;
  
  @tracked uploadingFrame = false;
  @tracked uploadingBadge = false;
  @tracked badgeUploadType = "image"; // "image" or "text"
  @tracked badgeUploadName = "";
  @tracked badgeUploadText = "";
  @tracked badgeUploadStyle = "";
  @tracked selectedStylePreset = "";
  
  // 勋章样式预设
  stylePresets = [
    { id: "", name: "自定义", style: "" },
    { id: "vip-gold", name: "VIP金色", style: "background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" },
    { id: "admin-red", name: "管理员红", style: "background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" },
    { id: "mod-blue", name: "版主蓝", style: "background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" },
    { id: "mvp-purple", name: "MVP紫", style: "background: linear-gradient(135deg, #a855f7 0%, #9333ea 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" },
    { id: "supporter-green", name: "支持者绿", style: "background: linear-gradient(135deg, #10b981 0%, #059669 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" },
    { id: "pro-black", name: "Pro黑金", style: "background: linear-gradient(135deg, #1f2937 0%, #111827 100%); color: #fbbf24; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.3); border: 1px solid #fbbf24;" },
    { id: "premium-pink", name: "Premium粉", style: "background: linear-gradient(135deg, #ec4899 0%, #db2777 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" },
    { id: "expert-cyan", name: "专家青", style: "background: linear-gradient(135deg, #06b6d4 0%, #0891b2 100%); color: white; font-weight: 700; padding: 3px 10px; border-radius: 4px; box-shadow: 0 2px 4px rgba(0,0,0,0.2);" }
  ];
  
  get isAdmin() {
    return this.currentUser?.admin;
  }
  
  get previewStyle() {
    return this.badgeUploadStyle || "";
  }
  
  get availableFrames() {
    return this.model?.frames || [];
  }
  
  get availableBadges() {
    return this.model?.badges || [];
  }
  
  get equippedFrameId() {
    return this.model?.equippedFrameId;
  }
  
  get equippedBadgeId() {
    return this.model?.equippedBadgeId;
  }
  
  @action
  async uploadFrame(event) {
    const file = event.target.files[0];
    if (!file) return;
    
    this.uploadingFrame = true;
    const formData = new FormData();
    formData.append("file", file);
    formData.append("name", file.name.split('.')[0]);
    
    try {
      const result = await ajax("/qd/test/upload-frame", {
        type: "POST",
        data: formData,
        processData: false,
        contentType: false
      });
      
      this.dialog.alert("✅ " + result.message);
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.uploadingFrame = false;
      event.target.value = "";
    }
  }
  
  @action
  async uploadBadge(event) {
    if (this.badgeUploadType === "image") {
      const file = event.target.files[0];
      if (!file) return;
      
      if (!this.badgeUploadName) {
        this.dialog.alert("❌ 请先输入勋章名称！");
        event.target.value = "";
        return;
      }
      
      this.uploadingBadge = true;
      const formData = new FormData();
      formData.append("file", file);
      formData.append("name", this.badgeUploadName);
      formData.append("type", "image");
      
      try {
        const result = await ajax("/qd/test/upload-badge", {
          type: "POST",
          data: formData,
          processData: false,
          contentType: false
        });
        
        this.dialog.alert("✅ " + result.message);
        this.badgeUploadName = "";
        window.location.reload();
      } catch (error) {
        popupAjaxError(error);
      } finally {
        this.uploadingBadge = false;
        event.target.value = "";
      }
    }
  }
  
  @action
  async uploadTextBadge() {
    if (!this.badgeUploadName || !this.badgeUploadText) {
      this.dialog.alert("❌ 请填写勋章名称和文字内容！");
      return;
    }
    
    this.uploadingBadge = true;
    
    try {
      const result = await ajax("/qd/test/upload-badge", {
        type: "POST",
        data: {
          name: this.badgeUploadName,
          type: "text",
          text: this.badgeUploadText,
          style: this.badgeUploadStyle
        }
      });
      
      this.dialog.alert("✅ " + result.message);
      this.badgeUploadName = "";
      this.badgeUploadText = "";
      this.badgeUploadStyle = "";
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.uploadingBadge = false;
    }
  }
  
  @action
  async equipFrame(frameId) {
    try {
      const result = await ajax("/qd/test/equip-frame", {
        type: "POST",
        data: { frame_id: frameId }
      });
      
      this.dialog.alert("✅ " + result.message);
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
    }
  }
  
  @action
  async equipBadge(badgeId) {
    try {
      const result = await ajax("/qd/test/equip-badge", {
        type: "POST",
        data: { badge_id: badgeId }
      });
      
      this.dialog.alert("✅ " + result.message);
      window.location.reload();
    } catch (error) {
      popupAjaxError(error);
    }
  }
  
  @action
  switchBadgeType(type) {
    this.badgeUploadType = type;
  }
  
  @action
  selectStylePreset(event) {
    const presetId = event.target.value;
    this.selectedStylePreset = presetId;
    
    const preset = this.stylePresets.find(p => p.id === presetId);
    if (preset) {
      this.badgeUploadStyle = preset.style;
    }
  }
}
