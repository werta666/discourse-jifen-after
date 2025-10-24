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
  
  get isAdmin() {
    return this.currentUser?.admin;
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
  
  isFrameEquipped(frameId) {
    return this.equippedFrameId === frameId;
  }
  
  isBadgeEquipped(badgeId) {
    return this.equippedBadgeId === badgeId;
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
}
