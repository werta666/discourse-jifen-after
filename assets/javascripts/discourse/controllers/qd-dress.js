import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdDressController extends Controller {
  @service dialog;
  
  @tracked isLoading = false;

  get hasFrames() {
    return this.model.owned_frames && this.model.owned_frames.length > 0;
  }

  get hasBadges() {
    return this.model.owned_badges && this.model.owned_badges.length > 0;
  }

  @action
  async equipFrame(frameId) {
    console.log("[Dress] 装备头像框 ID:", frameId);
    
    if (this.isLoading) {
      console.log("[Dress] 正在加载中，忽略重复点击");
      return;
    }
    
    this.isLoading = true;
    
    try {
      console.log("[Dress] 发送装备请求...");
      const result = await ajax("/qd/dress/equip-frame", {
        type: "POST",
        data: { frame_id: frameId }
      });
      
      console.log("[Dress] 装备成功:", result);
      this.dialog.alert("✅ 头像框装备成功！");
      this.model.equipped_frame_id = frameId;
      
      // 清除所有装饰相关缓存，确保重新加载
      localStorage.removeItem('qd_dress_user_frame_data');
      localStorage.removeItem('qd_dress_user_badge_data');
      localStorage.removeItem('qd_dress_user_data_v2');
      localStorage.removeItem('qd_dress_user_data_v3');
      
      setTimeout(() => window.location.reload(), 500);
    } catch (error) {
      console.error("[Dress] 装备失败:", error);
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async equipBadge(badgeId) {
    console.log("[Dress] 装备勋章 ID:", badgeId);
    
    if (this.isLoading) {
      console.log("[Dress] 正在加载中，忽略重复点击");
      return;
    }
    
    this.isLoading = true;
    
    try {
      console.log("[Dress] 发送装备请求...");
      const result = await ajax("/qd/dress/equip-badge", {
        type: "POST",
        data: { badge_id: badgeId }
      });
      
      console.log("[Dress] 装备成功:", result);
      this.dialog.alert("✅ 勋章装备成功！");
      this.model.equipped_badge_id = badgeId;
      
      // 清除所有装饰相关缓存，确保重新加载
      localStorage.removeItem('qd_dress_user_frame_data');
      localStorage.removeItem('qd_dress_user_badge_data');
      localStorage.removeItem('qd_dress_user_data_v2');
      localStorage.removeItem('qd_dress_user_data_v3');
      
      setTimeout(() => window.location.reload(), 500);
    } catch (error) {
      console.error("[Dress] 装备失败:", error);
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async unequipFrame() {
    this.isLoading = true;
    
    try {
      await ajax("/qd/dress/equip-frame", {
        type: "POST",
        data: { frame_id: 0 }
      });
      
      this.dialog.alert("✅ 已取消装备头像框");
      this.model.equipped_frame_id = null;
      
      // 清除所有装饰相关缓存
      localStorage.removeItem('qd_dress_user_frame_data');
      localStorage.removeItem('qd_dress_user_badge_data');
      localStorage.removeItem('qd_dress_user_data_v2');
      localStorage.removeItem('qd_dress_user_data_v3');
      
      setTimeout(() => window.location.reload(), 500);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async unequipBadge() {
    this.isLoading = true;
    
    try {
      await ajax("/qd/dress/equip-badge", {
        type: "POST",
        data: { badge_id: 0 }
      });
      
      this.dialog.alert("✅ 已取消装备勋章");
      this.model.equipped_badge_id = null;
      
      // 清除所有装饰相关缓存
      localStorage.removeItem('qd_dress_user_frame_data');
      localStorage.removeItem('qd_dress_user_badge_data');
      localStorage.removeItem('qd_dress_user_data_v2');
      localStorage.removeItem('qd_dress_user_data_v3');
      
      setTimeout(() => window.location.reload(), 500);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  formatDate(dateStr) {
    if (!dateStr) return "-";
    return new Date(dateStr).toLocaleString('zh-CN');
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
}
