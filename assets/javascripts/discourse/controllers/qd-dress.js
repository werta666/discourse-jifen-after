import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdDressController extends Controller {
  @tracked selectedTab = "avatar-frame";
  @tracked selectedFrameId = null;
  @tracked previewFrameId = null;
  @tracked ownedFrames = [];
  @tracked isLoading = false;
  @tracked showPurchaseModal = false;
  @tracked selectedItem = null;
  
  // 管理员上传相关（头像框）
  @tracked showUploadModal = false;
  @tracked uploadFileName = "";
  @tracked uploadFile = null;
  @tracked uploadPrice = 0;
  @tracked uploadCurrency = "points";
  @tracked isUploading = false;

  // 管理员上传相关（勋章）
  @tracked showBadgeUploadModal = false;
  @tracked badgeUploadType = "text"; // text or image
  @tracked badgeUploadName = "";
  @tracked badgeUploadText = "";
  @tracked badgeUploadStyle = "";
  @tracked badgeUploadFile = null;
  @tracked badgeUploadPrice = 0;
  @tracked badgeUploadCurrency = "points";
  @tracked isBadgeUploading = false;

  get currentUser() {
    return this.model?.user;
  }

  get userPoints() {
    return this.currentUser?.custom_fields?.points || 0;
  }

  get userPaidCoins() {
    return this.currentUser?.custom_fields?.paid_coins || 0;
  }

  get availableFrames() {
    return this.model?.availableFrames || [];
  }

  get userBadges() {
    return this.model?.badges || [];
  }

  get availableDecorations() {
    return this.model?.availableDecorations || [];
  }

  get ownedBadges() {
    return this.model?.ownedBadges || [];
  }

  get currentAvatarUrl() {
    return this.currentUser?.avatar_template?.replace("{size}", "150");
  }

  get previewFrame() {
    const frameId = this.previewFrameId || this.selectedFrameId;
    return this.availableFrames.find(f => f.id === frameId);
  }

  get isAdmin() {
    return this.currentUser?.admin || false;
  }

  isFrameOwned(frameId) {
    return this.ownedFrames.includes(frameId);
  }

  isFrameEquipped(frameId) {
    return this.selectedFrameId === frameId;
  }

  isBadgeOwned(badgeId) {
    return this.ownedBadges.includes(badgeId);
  }

  @action
  switchTab(tab) {
    this.selectedTab = tab;
  }

  @action
  previewFrame(frameId) {
    this.previewFrameId = frameId;
  }

  @action
  clearPreview() {
    this.previewFrameId = null;
  }

  @action
  equipFrame(frameId) {
    if (!this.isFrameOwned(frameId)) {
      this.dialog.alert("你还没有拥有这个头像框！");
      return;
    }

    this.isLoading = true;
    ajax("/qd/dress/equip-frame", {
      type: "POST",
      data: { frame_id: frameId }
    })
      .then(() => {
        this.selectedFrameId = frameId;
        this.dialog.alert("✅ 头像框已装备！");
      })
      .catch(popupAjaxError)
      .finally(() => {
        this.isLoading = false;
      });
  }

  @action
  openPurchaseModal(item) {
    this.selectedItem = item;
    this.showPurchaseModal = true;
  }

  @action
  closePurchaseModal() {
    this.showPurchaseModal = false;
    this.selectedItem = null;
  }

  @action
  confirmPurchase() {
    if (!this.selectedItem) return;

    const item = this.selectedItem;
    const canAfford = item.currency === "points" 
      ? this.userPoints >= item.price 
      : this.userPaidCoins >= item.price;

    if (!canAfford) {
      this.dialog.alert("❌ 余额不足！");
      return;
    }

    this.isLoading = true;
    ajax("/qd/dress/purchase-frame", {
      type: "POST",
      data: { 
        frame_id: item.id,
        currency: item.currency,
        price: item.price
      }
    })
      .then(result => {
        this.ownedFrames.push(item.id);
        if (item.currency === "points") {
          this.currentUser.set("custom_fields.points", result.new_balance);
        } else {
          this.currentUser.set("custom_fields.paid_coins", result.new_balance);
        }
        this.closePurchaseModal();
        this.dialog.alert("🎉 购买成功！");
      })
      .catch(popupAjaxError)
      .finally(() => {
        this.isLoading = false;
      });
  }

  @action
  openUploadModal() {
    this.showUploadModal = true;
    this.uploadFileName = "";
    this.uploadFile = null;
    this.uploadPrice = 0;
    this.uploadCurrency = "points";
  }

  @action
  closeUploadModal() {
    this.showUploadModal = false;
  }

  @action
  updateFileName(event) {
    this.uploadFileName = event.target.value;
  }

  @action
  updatePrice(event) {
    this.uploadPrice = parseInt(event.target.value) || 0;
  }

  @action
  updateCurrency(event) {
    this.uploadCurrency = event.target.value;
  }

  @action
  handleFileChange(event) {
    const file = event.target.files[0];
    if (!file) return;

    // 验证文件类型
    if (!file.type.includes("png")) {
      this.dialog.alert("❌ 只支持 PNG 格式！");
      event.target.value = "";
      return;
    }

    this.uploadFile = file;
  }

  @action
  uploadFrame() {
    if (!this.uploadFileName) {
      this.dialog.alert("❌ 请输入文件名！");
      return;
    }

    if (!this.uploadFile) {
      this.dialog.alert("❌ 请选择文件！");
      return;
    }

    this.isUploading = true;

    const formData = new FormData();
    formData.append("file", this.uploadFile);
    formData.append("filename", this.uploadFileName);
    formData.append("price", this.uploadPrice);
    formData.append("currency", this.uploadCurrency);

    ajax("/qd/dress/upload-frame", {
      type: "POST",
      data: formData,
      processData: false,
      contentType: false
    })
      .then(result => {
        this.dialog.alert("✅ 上传成功！");
        this.closeUploadModal();
        // 刷新页面数据
        window.location.reload();
      })
      .catch(popupAjaxError)
      .finally(() => {
        this.isUploading = false;
      });
  }

  @action
  stopPropagation(event) {
    event.stopPropagation();
  }

  // ========================================
  // 勋章相关 Actions
  // ========================================
  @action
  openBadgeUploadModal() {
    this.showBadgeUploadModal = true;
    this.badgeUploadType = "text";
    this.badgeUploadName = "";
    this.badgeUploadText = "";
    this.badgeUploadStyle = "background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white;";
    this.badgeUploadFile = null;
    this.badgeUploadPrice = 0;
    this.badgeUploadCurrency = "points";
  }

  @action
  closeBadgeUploadModal() {
    this.showBadgeUploadModal = false;
  }

  @action
  updateBadgeType(event) {
    this.badgeUploadType = event.target.value;
  }

  @action
  updateBadgeName(event) {
    this.badgeUploadName = event.target.value;
  }

  @action
  updateBadgeText(event) {
    this.badgeUploadText = event.target.value;
  }

  @action
  updateBadgeStyle(event) {
    this.badgeUploadStyle = event.target.value;
  }

  @action
  updateBadgePrice(event) {
    this.badgeUploadPrice = parseInt(event.target.value) || 0;
  }

  @action
  updateBadgeCurrency(event) {
    this.badgeUploadCurrency = event.target.value;
  }

  @action
  handleBadgeFileChange(event) {
    const file = event.target.files[0];
    if (!file) return;

    // 验证文件类型
    if (!file.type.includes("png") && !file.type.includes("jpg") && !file.type.includes("jpeg")) {
      this.dialog.alert("❌ 只支持 PNG/JPG 格式！");
      event.target.value = "";
      return;
    }

    this.badgeUploadFile = file;
  }

  @action
  equipBadge(badgeId) {
    if (!this.isBadgeOwned(badgeId)) {
      this.dialog.alert("你还没有拥有这个勋章！");
      return;
    }

    this.isLoading = true;
    ajax("/qd/dress/equip-badge", {
      type: "POST",
      data: { badge_id: badgeId }
    })
      .then(() => {
        this.dialog.alert("✅ 勋章已装备！");
        window.location.reload();
      })
      .catch(popupAjaxError)
      .finally(() => {
        this.isLoading = false;
      });
  }

  @action
  purchaseBadge(badge) {
    this.selectedItem = badge;
    this.showPurchaseModal = true;
  }

  @action
  uploadBadge() {
    if (!this.badgeUploadName) {
      this.dialog.alert("❌ 请输入勋章名称！");
      return;
    }

    if (this.badgeUploadType === "text") {
      if (!this.badgeUploadText) {
        this.dialog.alert("❌ 请输入文字内容！");
        return;
      }
    } else {
      if (!this.badgeUploadFile) {
        this.dialog.alert("❌ 请选择文件！");
        return;
      }
    }

    this.isBadgeUploading = true;

    const formData = new FormData();
    formData.append("name", this.badgeUploadName);
    formData.append("type", this.badgeUploadType);
    formData.append("price", this.badgeUploadPrice);
    formData.append("currency", this.badgeUploadCurrency);

    if (this.badgeUploadType === "text") {
      formData.append("text", this.badgeUploadText);
      formData.append("style", this.badgeUploadStyle);
    } else {
      formData.append("file", this.badgeUploadFile);
    }

    ajax("/qd/dress/upload-badge", {
      type: "POST",
      data: formData,
      processData: false,
      contentType: false
    })
      .then(result => {
        this.dialog.alert("✅ 勋章上传成功！");
        this.closeBadgeUploadModal();
        // 刷新页面数据
        window.location.reload();
      })
      .catch(popupAjaxError)
      .finally(() => {
        this.isBadgeUploading = false;
      });
  }
}
