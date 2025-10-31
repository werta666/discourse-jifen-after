import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { inject as service } from "@ember/service";

export default class QdCenterMakeController extends Controller {
  @service dialog;
  @service siteSettings;
  @service currentUser;
  
  @tracked showUploadModal = false;
  @tracked uploading = false;
  @tracked activeTab = "works"; // works / donations / partnership
  
  @tracked uploadTitle = "";
  @tracked uploadImageUrl = "";
  @tracked uploadImagePreview = "";
  @tracked uploadImageFile = null;
  @tracked uploadPostUrl = "";
  
  // 打赏记录筛选和分页
  @tracked filterDate = new Date().toISOString().split('T')[0];
  @tracked currentPage = 1;
  @tracked pageSize = 20;
  
  // 合作销售记录筛选和分页
  @tracked salesFilterDate = new Date().toISOString().split('T')[0];
  @tracked salesCurrentPage = 1;
  @tracked salesPageSize = 20;
  
  get siteUrl() {
    return window.location.origin;
  }
  
  get titleLength() {
    return this.uploadTitle.length;
  }
  
  get myWorks() {
    return this.model.my_works || [];
  }
  
  get donations() {
    return this.model.donations || [];
  }
  
  get partnershipSales() {
    return this.model.partnership_sales || [];
  }
  
  get filteredDonations() {
    const donations = this.donations;
    if (!this.filterDate) return donations;
    
    return donations.filter(donation => {
      return donation.created_at.startsWith(this.filterDate);
    });
  }
  
  get paginatedDonations() {
    const start = (this.currentPage - 1) * this.pageSize;
    const end = start + this.pageSize;
    return this.filteredDonations.slice(start, end);
  }
  
  get totalPages() {
    return Math.ceil(this.filteredDonations.length / this.pageSize);
  }
  
  get hasPreviousPage() {
    return this.currentPage > 1;
  }
  
  get hasNextPage() {
    return this.currentPage < this.totalPages;
  }
  
  get filteredPartnershipSales() {
    const sales = this.partnershipSales;
    if (!this.salesFilterDate) return sales;
    
    return sales.filter(sale => {
      return sale.created_at.startsWith(this.salesFilterDate);
    });
  }
  
  get paginatedPartnershipSales() {
    const start = (this.salesCurrentPage - 1) * this.salesPageSize;
    const end = start + this.salesPageSize;
    return this.filteredPartnershipSales.slice(start, end);
  }
  
  get salesTotalPages() {
    return Math.ceil(this.filteredPartnershipSales.length / this.salesPageSize);
  }
  
  get salesHasPreviousPage() {
    return this.salesCurrentPage > 1;
  }
  
  get salesHasNextPage() {
    return this.salesCurrentPage < this.salesTotalPages;
  }
  
  get totalPartnershipIncome() {
    return this.partnershipSales.reduce((sum, sale) => sum + (sale.partner_income || 0), 0);
  }
  
  get totalPartnershipIncomePaidCoins() {
    return this.filteredPartnershipSales
      .filter(sale => sale.currency_type === "paid_coins")
      .reduce((sum, sale) => sum + (sale.partner_income || 0), 0);
  }
  
  get totalPartnershipIncomeJifen() {
    return this.filteredPartnershipSales
      .filter(sale => sale.currency_type === "points" || !sale.currency_type)
      .reduce((sum, sale) => sum + (sale.partner_income || 0), 0);
  }
  
  get shopStandards() {
    return this.model.shop_standards || {};
  }
  
  get jifenName() {
    return this.model.jifen_name || "积分";
  }
  
  get paidCoinName() {
    return this.model.paid_coin_name || "付费币";
  }
  
  get totalReceived() {
    return this.donations.reduce((sum, d) => sum + d.creator_received, 0);
  }
  
  get totalLikes() {
    return this.myWorks.reduce((sum, work) => sum + (work.likes_count || 0), 0);
  }
  
  get totalClicks() {
    return this.myWorks.reduce((sum, work) => sum + (work.clicks_count || 0), 0);
  }
  
  @action
  switchTab(tab) {
    this.activeTab = tab;
  }
  
  @action
  openUploadModal() {
    this.uploadTitle = "";
    this.uploadImageUrl = "";
    this.uploadImagePreview = "";
    this.uploadImageFile = null;
    this.uploadPostUrl = "";
    this.showUploadModal = true;
  }
  
  @action
  closeUploadModal() {
    this.showUploadModal = false;
    this.uploadImageFile = null;
    this.uploadImagePreview = "";
  }
  
  @action
  updateUploadTitle(event) {
    this.uploadTitle = event.target.value;
  }
  
  @action
  updateUploadPostUrl(event) {
    this.uploadPostUrl = event.target.value;
  }
  
  @action
  handleImageUpload(event) {
    const file = event.target.files[0];
    if (!file) return;
    
    // 验证文件类型
    if (!file.type.match(/image\/(jpeg|jpg)/)) {
      this.dialog.alert("仅支持 JPG 格式的图片");
      event.target.value = "";
      return;
    }
    
    // 验证文件大小（5MB）
    if (file.size > 5 * 1024 * 1024) {
      this.dialog.alert("图片大小不能超过 5MB");
      event.target.value = "";
      return;
    }
    
    this.uploadImageFile = file;
    
    // 生成预览
    const reader = new FileReader();
    reader.onload = (e) => {
      this.uploadImagePreview = e.target.result;
    };
    reader.readAsDataURL(file);
  }
  
  @action
  removeImage() {
    this.uploadImageFile = null;
    this.uploadImagePreview = "";
    this.uploadImageUrl = "";
    
    // 清空文件输入
    const input = document.getElementById("image-upload-input");
    if (input) {
      input.value = "";
    }
  }
  
  @action
  async confirmUpload() {
    // 验证必填项
    if (!this.uploadTitle.trim()) {
      this.dialog.alert("请填写作品标题");
      return;
    }
    
    if (!this.uploadImageFile) {
      this.dialog.alert("请上传作品图片");
      return;
    }
    
    if (!this.uploadPostUrl.trim()) {
      this.dialog.alert("请填写帖子地址");
      return;
    }
    
    this.uploading = true;
    
    try {
      // 第一步：上传图片
      const formData = new FormData();
      formData.append("file", this.uploadImageFile);
      formData.append("type", "composer");
      formData.append("synchronous", "true");
      
      const uploadResult = await ajax("/uploads.json", {
        type: "POST",
        data: formData,
        processData: false,
        contentType: false
      });
      
      if (!uploadResult || !uploadResult.url) {
        throw new Error("图片上传失败");
      }
      
      // 第二步：创建作品
      const fullPostUrl = `${this.siteUrl}/t/${this.uploadPostUrl}`;
      
      const result = await ajax("/qd/center/create_work", {
        type: "POST",
        data: {
          title: this.uploadTitle.trim(),
          image_url: uploadResult.url,
          post_url: fullPostUrl
        }
      });
      
      if (result.success) {
        this.dialog.alert("作品提交成功，等待审核！");
        this.closeUploadModal();
        // 刷新数据
        window.location.reload();
      }
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || error.message || "上传失败，请重试");
    } finally {
      this.uploading = false;
    }
  }
  
  @action
  async applyShop(work) {
    if (!confirm(`确认申请上架作品"${work.title || '作品 #' + work.id}"到商店？`)) {
      return;
    }
    
    try {
      await ajax("/qd/center/apply_shop", {
        type: "POST",
        data: { work_id: work.id }
      });
      
      this.dialog.alert("申请已提交，等待管理员审核");
      
      // 刷新数据
      const newData = await ajax("/qd/center/make");
      this.model.my_works = newData.my_works;
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "申请失败");
    }
  }
  
  @action
  async deleteRejectedWork(work) {
    if (!confirm(`确认删除已被驳回的作品"${work.title || '作品 #' + work.id}"？\n此操作不可恢复。`)) {
      return;
    }
    
    try {
      await ajax("/qd/center/delete_rejected_work", {
        type: "DELETE",
        data: { work_id: work.id }
      });
      
      this.dialog.alert("作品已删除");
      
      // 刷新数据
      const newData = await ajax("/qd/center/make");
      this.model.my_works = newData.my_works;
    } catch (error) {
      this.dialog.alert(error.jqXHR?.responseJSON?.error || "删除失败");
    }
  }
  
  @action
  async shareWork(work) {
    const shareUrl = `${window.location.origin}/qd/center/zp/${work.id}`;
    
    try {
      await navigator.clipboard.writeText(shareUrl);
      this.dialog.alert("分享链接已复制到剪贴板！\n\n" + shareUrl);
    } catch (error) {
      this.dialog.alert(`作品分享链接：\n\n${shareUrl}\n\n请手动复制`);
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
  
  @action
  updateFilterDate(event) {
    this.filterDate = event.target.value;
    this.currentPage = 1; // 重置到第一页
  }
  
  @action
  clearFilter() {
    this.filterDate = "";
    this.currentPage = 1;
  }
  
  @action
  previousPage() {
    if (this.hasPreviousPage) {
      this.currentPage--;
    }
  }
  
  @action
  nextPage() {
    if (this.hasNextPage) {
      this.currentPage++;
    }
  }
  
  @action
  goToPage(page) {
    this.currentPage = page;
  }
  
  @action
  updateSalesFilterDate(event) {
    this.salesFilterDate = event.target.value;
    this.salesCurrentPage = 1;
  }
  
  @action
  clearSalesFilter() {
    this.salesFilterDate = "";
    this.salesCurrentPage = 1;
  }
  
  @action
  salesPreviousPage() {
    if (this.salesHasPreviousPage) {
      this.salesCurrentPage--;
    }
  }
  
  @action
  salesNextPage() {
    if (this.salesHasNextPage) {
      this.salesCurrentPage++;
    }
  }
  
  @action
  goToSalesPage(page) {
    this.salesCurrentPage = page;
  }
  
  getStatusLabel(status) {
    const labels = {
      'pending': '待审核',
      'approved': '已通过',
      'rejected': '已驳回'
    };
    return labels[status] || status;
  }
  
  getStatusClass(status) {
    return `status-${status}`;
  }
  
  getOrderStatusLabel(status) {
    const labels = {
      'pending': '待处理',
      'completed': '已完成',
      'refunded': '已退款'
    };
    return labels[status] || status;
  }
}
