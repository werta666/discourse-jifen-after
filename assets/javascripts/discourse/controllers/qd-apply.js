import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdApplyController extends Controller {
  @service dialog;
  
  @tracked creativeField = "";
  @tracked creativeExperience = "";
  @tracked portfolioImages = [];
  @tracked uploadedImageUrls = [];
  @tracked uploadingImage = false;
  @tracked isSubmitting = false;
  @tracked showSuccess = false;
  @tracked successMessage = "";
  @tracked submittedApplication = null;

  get hasImages() {
    return this.uploadedImageUrls.length > 0;
  }
  
  get imageCount() {
    return this.uploadedImageUrls.length;
  }
  
  get canUploadMore() {
    return this.uploadedImageUrls.length < 5;
  }
  
  get hasEnoughImages() {
    return this.uploadedImageUrls.length >= 2;
  }

  get canSubmit() {
    return (
      this.creativeField.trim().length >= 10 &&
      this.creativeField.trim().length <= 500 &&
      this.creativeExperience.trim().length >= 20 &&
      this.creativeExperience.trim().length <= 2000 &&
      this.uploadedImageUrls.length >= 2 &&
      this.uploadedImageUrls.length <= 5 &&
      this.model.can_afford &&
      !this.model.is_creator &&
      !this.model.has_pending_application &&
      !this.isSubmitting
    );
  }

  @action
  updateCreativeField(event) {
    this.creativeField = event.target.value;
  }

  @action
  updateCreativeExperience(event) {
    this.creativeExperience = event.target.value;
  }

  @action
  async handleImageUpload(event) {
    const files = Array.from(event.target.files);
    if (files.length === 0) return;
    
    // 检查是否已达到最大数量
    if (this.uploadedImageUrls.length >= 5) {
      this.dialog.alert("最多只能上传5张图片");
      event.target.value = "";
      return;
    }
    
    this.uploadingImage = true;
    
    try {
      for (const file of files) {
        // 检查当前数量
        if (this.uploadedImageUrls.length >= 5) {
          this.dialog.alert("已达到最大上传数量（5张）");
          break;
        }
        
        // 验证文件类型
        if (!file.type.match(/image\/(jpeg|jpg|png|gif)/)) {
          this.dialog.alert("仅支持 JPG、PNG、GIF 格式的图片");
          continue;
        }
        
        // 验证文件大小（5MB）
        if (file.size > 5 * 1024 * 1024) {
          this.dialog.alert("图片大小不能超过 5MB");
          continue;
        }
        
        // 上传图片
        const formData = new FormData();
        formData.append("file", file);
        formData.append("type", "creator_application");
        formData.append("synchronous", "true");
        
        const uploadResult = await ajax("/uploads.json", {
          type: "POST",
          data: formData,
          processData: false,
          contentType: false
        });
        
        if (uploadResult && uploadResult.url) {
          this.uploadedImageUrls = [...this.uploadedImageUrls, uploadResult.url];
        }
      }
    } catch (error) {
      this.dialog.alert("图片上传失败，请重试");
    } finally {
      this.uploadingImage = false;
      event.target.value = "";
    }
  }
  
  @action
  removeImage(index) {
    this.uploadedImageUrls = this.uploadedImageUrls.filter((_, i) => i !== index);
  }

  @action
  async submitApplication() {
    if (!this.canSubmit) {
      return;
    }

    this.isSubmitting = true;

    try {
      const result = await ajax("/qd/apply/submit.json", {
        type: "POST",
        data: {
          creative_field: this.creativeField.trim(),
          creative_experience: this.creativeExperience.trim(),
          portfolio_images: this.uploadedImageUrls
        }
      });

      if (result.success) {
        this.showSuccess = true;
        this.successMessage = result.message;
        this.submittedApplication = result.application;
        
        // 清空表单
        this.creativeField = "";
        this.creativeExperience = "";
        this.uploadedImageUrls = [];
        
        // 3秒后刷新页面
        setTimeout(() => {
          window.location.reload();
        }, 3000);
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSubmitting = false;
    }
  }

  @action
  hideSuccess() {
    this.showSuccess = false;
  }
}
