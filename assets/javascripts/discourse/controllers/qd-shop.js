import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdShopController extends Controller {
  @service router;
  @tracked selectedProduct = null;
  @tracked showPurchaseModal = false;
  @tracked showAdminModal = false;
  @tracked purchaseQuantity = 1;
  @tracked purchaseRemark = "";
  @tracked purchaseEmail = "";
  @tracked purchaseAddress = "";
  @tracked isLoading = false;
  @tracked showSuccessPopup = false;
  @tracked successMessage = "";
  @tracked currentFilter = "all";
  
  // 付费币相关
  @tracked showExchangeModal = false;
  @tracked exchangeAmount = 1;
  @tracked showExchangeSuccess = false;
  @tracked exchangeResult = null;
  
  // 合作商品分类 - 单独tracked以确保响应式更新
  @tracked partnershipCategory = "";
  
  // 管理员添加商品表单
  @tracked newProduct = {
    name: "",
    description: "",
    icon_class: "fa fa-gift",
    price: 100,
    stock: 50,
    sort_order: 0,
    currency_type: "points",  // 默认为积分
    selectedTag: {
      new: true,  // 默认选中新品
      hot: false,
      preorder: false
    },
    // 合作商品字段
    is_partnership: false,
    partner_username: "",
    partnership_category: "",
    related_post_url: "",
    decoration_frame_id: null,
    decoration_badge_id: null,
    virtual_email_template: "",
    virtual_address_template: "",
    commission_rate: 0
  };
  
  // 图标选择器
  @tracked showNewProductIconPicker = false;
  @tracked showEditProductIconPicker = false;
  
  // 可用的Font Awesome图标列表
  availableIcons = [
    "fa fa-gift",
    "fa fa-trophy",
    "fa fa-star",
    "fa fa-crown",
    "fa fa-medal",
    "fa fa-gem",
    "fa fa-fire",
    "fa fa-bolt",
    "fa fa-heart",
    "fa fa-diamond",
    "fa fa-shopping-cart",
    "fa fa-shopping-bag",
    "fa fa-cube",
    "fa fa-box",
    "fa fa-rocket",
    "fa fa-magic",
    "fa fa-wand-magic-sparkles",
    "fa fa-palette"
  ];

  // 管理员界面状态
  @tracked adminActiveTab = "add";
  @tracked editingProduct = null;

  constructor() {
    super(...arguments);
    this.resetNewProduct();
    // 确保默认选中新品并设置前缀
    this.updateProductNameWithTags(this.newProduct);
  }

  @action
  showProductDetail(product) {
    this.selectedProduct = product;
    this.purchaseQuantity = 1;
    this.purchaseRemark = "";
    this.showPurchaseModal = true;
  }

  @action
  closePurchaseModal() {
    this.showPurchaseModal = false;
    this.selectedProduct = null;
    this.purchaseQuantity = 1;
    this.purchaseRemark = "";
    this.purchaseEmail = "";
    this.purchaseAddress = "";
  }

  @action
  updatePurchaseQuantity(event) {
    const quantity = parseInt(event.target.value) || 1;
    const maxQuantity = this.selectedProduct?.stock || 1;
    
    if (quantity > 0 && quantity <= maxQuantity) {
      this.purchaseQuantity = quantity;
    } else if (quantity > maxQuantity) {
      this.purchaseQuantity = maxQuantity;
      event.target.value = maxQuantity;
    } else {
      this.purchaseQuantity = 1;
      event.target.value = 1;
    }
  }

  @action
  updatePurchaseNotes(event) {
    this.purchaseRemark = event.target.value;
  }

  @action
  updatePurchaseEmail(event) {
    this.purchaseEmail = event.target.value;
  }

  @action
  updatePurchaseAddress(event) {
    this.purchaseAddress = event.target.value;
  }

  @action
  increaseQuantity() {
    if (this.selectedProduct && this.purchaseQuantity < this.selectedProduct.stock) {
      this.purchaseQuantity++;
    }
  }

  @action
  decreaseQuantity() {
    if (this.purchaseQuantity > 1) {
      this.purchaseQuantity--;
    }
  }

  @action
  async confirmPurchase() {
    if (!this.selectedProduct) {
      alert("❌ 没有选中的商品");
      return;
    }
    
    if (this.isLoading) {
      return;
    }
    
    this.isLoading = true;
    
    try {
      const purchaseData = {
        product_id: this.selectedProduct.id,
        quantity: this.purchaseQuantity,
        user_note: this.purchaseRemark || "",
        user_email: this.purchaseEmail || "",
        user_address: this.purchaseAddress || ""
      };
      
      const result = await ajax("/qd/shop/purchase", {
        type: "POST",
        data: purchaseData
      });
      
      if (result.status === "success") {
        // 更新用户积分显示
        if (result.data && result.data.remaining_points !== undefined) {
          this.model.userPoints = result.data.remaining_points;
        }
        
        // 显示绿色主题成功消息
        this.showSuccessMessage('购买成功！');
        
        this.closePurchaseModal();
        
        // 2秒后自动刷新页面
        setTimeout(() => {
          this.refreshProducts();
        }, 2000);
      } else {
        alert(`❌ ${result.message || "购买失败"}`);
      }
      
    } catch (error) {
      console.error("🛒 购买异常:", error);
      const errorMessage = error.jqXHR?.responseJSON?.message || "购买失败，请稍后重试";
      alert(`❌ ${errorMessage}`);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  refreshProducts() {
    // 刷新页面数据
    window.location.reload();
  }

  get totalPrice() {
    if (!this.selectedProduct) return 0;
    return this.selectedProduct.price * this.purchaseQuantity;
  }

  get canAfford() {
    if (!this.selectedProduct) return true;
    
    if (this.selectedProduct.currency_type === "paid_coins") {
      return (this.model.userPaidCoins || 0) >= this.totalPrice;
    } else {
      return this.model.userPoints >= this.totalPrice;
    }
  }

  get shortage() {
    if (!this.selectedProduct || this.canAfford) return 0;
    
    if (this.selectedProduct.currency_type === "paid_coins") {
      return this.totalPrice - (this.model.userPaidCoins || 0);
    } else {
      return this.totalPrice - this.model.userPoints;
    }
  }

  // 旧前缀解析已废弃
  deriveTagFromName(name = "") { return { key: null, label: null }; }

  mapTagKeyToLabel(key) {
    switch (key) {
      case "new":
        return "新品";
      case "hot":
        return "热销";
      case "preorder":
        return "预购";
      default:
        return null;
    }
  }

  // 生成用于前端展示的商品数据：清洗后的名称、角标样式、库存样式
  decorateProduct(product) {
    const name = product?.name || "";
    // 仅使用后端返回的独立标签
    const tagKey = product?.tag || null;
    const tagLabel = this.mapTagKeyToLabel(tagKey);
    const cleanName = name;
    const stock = parseInt(product?.stock || 0);
    let stockStatusClass = "in-stock";
    if (stock <= 0) {
      stockStatusClass = "out-of-stock";
    } else if (stock <= 5) {
      stockStatusClass = "low-stock";
    }
    const ribbonClass = tagKey ? `ribbon-${tagKey}` : "";

    return {
      ...product,
      cleanName,
      tag: tagLabel,
      tagKey,
      tagLabel,
      ribbonClass,
      stockStatusClass,
    };
  }

  get filteredProducts() {
    const raw = (this.model && this.model.products) ? this.model.products : [];
    const decorated = raw.map((p) => this.decorateProduct(p));
    if (this.currentFilter === "all") {
      return decorated;
    }
    // 前端筛选使用中文标签（新品/热销/预购）
    return decorated.filter((p) => p.tagLabel === this.currentFilter);
  }

  @action
  setFilter(filter) {
    this.currentFilter = filter;
  }
  
  // 管理员功能
  @action
  showAdminPanel() {
    this.showAdminModal = true;
  }
  
  @action
  closeAdminModal() {
    this.showAdminModal = false;
    this.resetNewProduct();
    this.editingProduct = null;
    this.adminActiveTab = "add";
  }
  
  @action
  updateNewProduct(field, event) {
    let value = event.target.value;
    
    // 对必填整数字段进行类型转换
    if (field === 'price' || field === 'stock' || field === 'sort_order') {
      value = parseInt(value) || 0;
    }
    
    // 对可选整数字段进行转换（空值保存为null）
    if (field === 'decoration_frame_id' || field === 'decoration_badge_id') {
      value = value ? parseInt(value) : null;
    }
    
    // 对浮点数字段进行转换
    if (field === 'commission_rate') {
      value = value ? parseFloat(value) : 0;
    }
    
    // 直接赋值，@tracked 会自动处理响应式更新
    this.newProduct[field] = value;
    
    // 同步更新单独的 tracked 属性
    if (field === 'partnership_category') {
      this.partnershipCategory = value;
    }
  }
  
  @action
  async addProduct() {
    if (this.isLoading) return;
    
    this.isLoading = true;
    
    try {
      // 独立存储标签：不再修改名称，单独发送 tag
      const tagKey = this.newProduct.selectedTag.new
        ? 'new'
        : this.newProduct.selectedTag.hot
        ? 'hot'
        : this.newProduct.selectedTag.preorder
        ? 'preorder'
        : null;

      const productData = {
        ...this.newProduct,
        name: this.newProduct.name,
        tag: tagKey
      };
      
      const result = await ajax("/qd/shop/add_product", {
        type: "POST",
        data: {
          product: productData
        }
      });
      
      if (result.status === "success") {
        alert(`✅ ${result.message}`);
        this.closeAdminModal();
        // 刷新页面数据
        window.location.reload();
      } else {
        alert(`❌ ${result.message}`);
      }
    } catch (error) {
      const errorMessage = error.jqXHR?.responseJSON?.message || "添加商品失败，请重试";
      alert(`❌ ${errorMessage}`);
    } finally {
      this.isLoading = false;
    }
  }
  
  @action
  async createSampleData() {
    if (this.isLoading) return;
    
    this.isLoading = true;
    
    try {
      const result = await ajax("/qd/shop/create_sample", {
        type: "POST"
      });
      
      if (result.status === "success") {
        alert(`✅ ${result.message}\n创建了 ${result.created_count} 个商品`);
        this.closeAdminModal();
        // 刷新页面数据
        window.location.reload();
      } else {
        alert(`❌ ${result.message}`);
      }
    } catch (error) {
      const errorMessage = error.jqXHR?.responseJSON?.message || "创建示例数据失败，请重试";
      alert(`❌ ${errorMessage}`);
    } finally {
      this.isLoading = false;
    }
  }
  
  @action
  resetNewProduct() {
    this.newProduct = {
      name: "",
      description: "",
      icon_class: "fa fa-gift",
      price: 100,
      stock: 50,
      sort_order: 0,
      currency_type: "points",
      selectedTag: {
        new: true,  // 默认选中新品
        hot: false,
        preorder: false
      },
      // 合作商品字段
      is_partnership: false,
      partner_username: "",
      partnership_category: "",
      related_post_url: "",
      decoration_frame_id: null,
      decoration_badge_id: null,
      virtual_email_template: "",
      virtual_address_template: "",
      commission_rate: 0
    };
  }

  @action
  stopPropagation(event) {
    event.stopPropagation();
  }

  // 管理员功能
  @action
  setAdminTab(tab) {
    this.adminActiveTab = tab;
  }

  @action
  editProduct(product) {
    this.editingProduct = {
      id: product.id,
      name: product.name || "",
      description: product.description || "",
      icon_class: product.icon_class || "fa fa-gift",
      price: product.price || 0,
      stock: product.stock || 0,
      sort_order: product.sort_order || 0,
      currency_type: product.currency_type || "points",
      tag: product.tagKey || product.tag || null,
      selectedTag: { new: false, hot: false, preorder: false },
      // 合作商品字段
      is_partnership: product.is_partnership || false,
      partner_username: product.partner_username || "",
      partnership_category: product.partnership_category || "",
      related_post_url: product.related_post_url || "",
      decoration_frame_id: product.decoration_frame_id || null,
      decoration_badge_id: product.decoration_badge_id || null,
      virtual_email_template: product.virtual_email_template || "",
      virtual_address_template: product.virtual_address_template || "",
      commission_rate: product.commission_rate || 0
    };
    this.initializeProductTags(this.editingProduct);
    this.adminActiveTab = "edit";
    this.showAdminModal = true;
  }

  @action
  async updateProduct() {
    if (this.isLoading || !this.editingProduct) {
      return;
    }
    
    this.isLoading = true;
    
    try {
      // 独立存储标签：不再修改名称，单独发送 tag
      const tagKey = this.editingProduct.selectedTag.new
        ? 'new'
        : this.editingProduct.selectedTag.hot
        ? 'hot'
        : this.editingProduct.selectedTag.preorder
        ? 'preorder'
        : null;
      
      const productData = {
        name: this.editingProduct.name,
        description: this.editingProduct.description,
        icon_class: this.editingProduct.icon_class,
        price: parseInt(this.editingProduct.price) || 0,
        stock: parseInt(this.editingProduct.stock) || 0,
        sort_order: parseInt(this.editingProduct.sort_order) || 0,
        currency_type: this.editingProduct.currency_type || "points",
        tag: tagKey
      };
      
      // 如果是合作商品，添加合作商品字段
      if (this.editingProduct.is_partnership) {
        productData.is_partnership = true;
        productData.partner_username = this.editingProduct.partner_username || "";
        productData.partnership_category = this.editingProduct.partnership_category || "";
        productData.related_post_url = this.editingProduct.related_post_url || "";
        productData.commission_rate = this.editingProduct.commission_rate || 0;
        productData.decoration_frame_id = this.editingProduct.decoration_frame_id || null;
        productData.decoration_badge_id = this.editingProduct.decoration_badge_id || null;
        productData.virtual_email_template = this.editingProduct.virtual_email_template || "";
        productData.virtual_address_template = this.editingProduct.virtual_address_template || "";
      }
      
      const result = await ajax(`/qd/shop/products/${this.editingProduct.id}`, {
        type: "PUT",
        data: {
          product: productData
        }
      });
      
      if (result.status === "success") {
        alert(`✅ ${result.message}`);
        
        // 更新本地商品列表数据
        const productIndex = this.model.products.findIndex(p => p.id === this.editingProduct.id);
        if (productIndex !== -1) {
          this.model.products[productIndex] = { ...this.model.products[productIndex], ...result.data };
          this.notifyPropertyChange('model');
        }
        
        // 重置编辑状态并切换到管理标签页
        this.editingProduct = null;
        this.adminActiveTab = "manage";
      } else {
        alert(`❌ ${result.message || "更新失败"}`);
      }
    } catch (error) {
      const errorMessage = error.jqXHR?.responseJSON?.message || "更新商品失败，请重试";
      alert(`❌ ${errorMessage}`);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  updateEditingProduct(field, event) {
    let value = event.target.value;
    
    // 对必填整数字段进行类型转换
    if (field === 'price' || field === 'stock' || field === 'sort_order') {
      value = parseInt(value) || 0;
    }
    
    // 对可选整数字段进行转换（空值保存为null）
    if (field === 'decoration_frame_id' || field === 'decoration_badge_id') {
      value = value ? parseInt(value) : null;
    }
    
    // 对浮点数字段进行转换
    if (field === 'commission_rate') {
      value = value ? parseFloat(value) : 0;
    }
    
    // 确保 editingProduct 存在
    if (!this.editingProduct) {
      this.editingProduct = {};
    }
    
    // 直接赋值
    this.editingProduct[field] = value;
    
    // 对于关键字段，强制触发响应式更新
    if (field === 'currency_type' || field === 'partnership_category') {
      this.editingProduct = { ...this.editingProduct };
    }
  }

  @action
  async deleteProduct(product) {
    if (!confirm(`确定要删除商品 "${product.name}" 吗？此操作不可恢复。`)) {
      return;
    }

    try {
      const result = await ajax(`/qd/shop/products/${product.id}`, {
        type: "DELETE"
      });

      if (result.status === "success") {
        alert(`✅ ${result.message}`);
        // 刷新页面数据
        window.location.reload();
      } else {
        alert(`❌ ${result.message}`);
      }
    } catch (error) {
      const errorMessage = error.jqXHR?.responseJSON?.message || "删除商品失败，请重试";
      alert(`❌ ${errorMessage}`);
    }
  }

  @action
  goToAdminOrders() {
    this.router.transitionTo("qd-shop-admin-orders");
  }

  @action
  showSuccessMessage(message) {
    this.successMessage = message;
    this.showSuccessPopup = true;
    
    // 3秒后自动隐藏
    setTimeout(() => {
      this.hideSuccessMessage();
    }, 3000);
  }

  @action
  hideSuccessMessage() {
    this.showSuccessPopup = false;
    this.successMessage = "";
  }

  // 商品标签管理功能
  @action
  selectProductTag(tagType, isNewProduct = true) {
    const product = isNewProduct ? this.newProduct : this.editingProduct;
    if (!product.selectedTag) {
      product.selectedTag = { new: false, hot: false, preorder: false };
    }
    
    // 重置所有标签为false
    product.selectedTag.new = false;
    product.selectedTag.hot = false;
    product.selectedTag.preorder = false;
    
    // 设置选中的标签为true
    product.selectedTag[tagType] = true;
    
    // 更新产品名称，添加对应的标签前缀
    this.updateProductNameWithTags(product);
  }

  @action
  updateProductNameWithTags(product) {
    // 不再动态更新商品名称，标签信息独立存储
    // 标签选择仅用于UI显示和后端处理
  }

  @action
  initializeProductTags(product) {
    // 仅使用后端 tag 字段初始化；若无则默认新品
    if (!product.selectedTag) {
      product.selectedTag = { new: false, hot: false, preorder: false };
    }
    const key = product.tag || 'new';
    product.selectedTag.new = key === 'new';
    product.selectedTag.hot = key === 'hot';
    product.selectedTag.preorder = key === 'preorder';
  }

  // ========== 合作商品功能 ==========
  
  @action
  async addPartnershipProduct() {
    if (this.isLoading) return;
    
    const isEditing = !!this.editingPartnershipProductId;
    
    // 验证必填字段
    if (!this.newProduct.name?.trim()) {
      alert("请填写商品名称");
      return;
    }
    
    if (!this.newProduct.partner_username?.trim()) {
      alert("请填写合作伙伴用户名");
      return;
    }
    
    if (!this.newProduct.partnership_category) {
      alert("请选择商品分类");
      return;
    }
    
    if (!this.newProduct.related_post_url?.trim()) {
      alert("请填写关联帖子URL");
      return;
    }
    
    // 验证装饰品至少填写一项
    if (this.newProduct.partnership_category === 'decoration') {
      if (!this.newProduct.decoration_frame_id && !this.newProduct.decoration_badge_id) {
        alert("装饰品类型至少需要填写头像框ID或勋章ID其中一项");
        return;
      }
    }
    
    // 虚拟物品的邮箱和地址模板都是可选的，不需要强制验证
    
    this.isLoading = true;
    
    try {
      // 获取选中的标签
      const selectedTags = this.newProduct.selectedTag || { new: true, hot: false, preorder: false };
      let tagValue = null;
      if (selectedTags.hot) tagValue = 'hot';
      else if (selectedTags.preorder) tagValue = 'preorder';
      else if (selectedTags.new) tagValue = 'new';
      
      const productData = {
        name: this.newProduct.name.trim(),
        description: this.newProduct.description?.trim() || "",
        icon_class: this.newProduct.icon_class || "fa fa-gift",
        price: parseInt(this.newProduct.price) || 0,
        stock: parseInt(this.newProduct.stock) || 0,
        sort_order: parseInt(this.newProduct.sort_order) || 0,
        currency_type: this.newProduct.currency_type || "points",
        tag: tagValue,
        is_partnership: true,
        partner_username: this.newProduct.partner_username.trim(),
        partnership_category: this.newProduct.partnership_category,
        related_post_url: this.newProduct.related_post_url.trim(),
        commission_rate: parseFloat(this.newProduct.commission_rate) || 0,
        decoration_frame_id: this.newProduct.decoration_frame_id ? parseInt(this.newProduct.decoration_frame_id) : null,
        decoration_badge_id: this.newProduct.decoration_badge_id ? parseInt(this.newProduct.decoration_badge_id) : null,
        virtual_email_template: this.newProduct.virtual_email_template?.trim() || "",
        virtual_address_template: this.newProduct.virtual_address_template?.trim() || ""
      };
      
      let response;
      if (isEditing) {
        // 更新现有合作商品
        response = await ajax(`/qd/shop/products/${this.editingPartnershipProductId}`, {
          type: "PUT",
          data: { 
            product: productData 
          }
        });
      } else {
        // 创建新合作商品
        response = await ajax("/qd/shop/add_product", {
          type: "POST",
          data: { product: productData }
        });
      }
      
      if (response.status === "success") {
        this.showSuccessMessage(isEditing ? "合作商品更新成功！" : "合作商品创建成功！");
        this.resetPartnershipProduct();
        
        // 刷新商品列表
        const shopData = await ajax("/qd/shop");
        this.model.products = shopData.products;
        
        // 关闭模态框并切换到管理商品tab
        this.showAdminModal = false;
        this.adminActiveTab = "manage";
      }
    } catch (error) {
      const errorMessage = error.jqXHR?.responseJSON?.message || error.message || (isEditing ? "更新失败" : "创建失败");
      alert(`${isEditing ? "更新" : "创建"}合作商品失败：${errorMessage}`);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  resetPartnershipProduct() {
    this.newProduct.name = "";
    this.newProduct.description = "";
    this.newProduct.icon_class = "fa fa-gift";
    this.newProduct.price = 100;
    this.newProduct.stock = 50;
    this.newProduct.sort_order = 0;
    this.newProduct.currency_type = "points";
    this.newProduct.selectedTag = { new: true, hot: false, preorder: false };
    this.newProduct.partner_username = "";
    this.newProduct.partnership_category = "";
    this.newProduct.related_post_url = "";
    this.newProduct.decoration_frame_id = null;
    this.newProduct.decoration_badge_id = null;
    this.newProduct.virtual_email_template = "";
    this.newProduct.virtual_address_template = "";
    this.newProduct.commission_rate = 0;
    this.partnershipCategory = "";  // 重置 tracked 属性
    this.editingPartnershipProductId = null;
  }

  @action
  editPartnershipProduct(product) {
    // 打开管理员模态框
    this.showAdminModal = true;
    
    // 加载商品数据到表单 - 使用对象赋值确保响应式更新
    this.newProduct = {
      name: product.name || "",
      description: product.description || "",
      icon_class: product.icon_class || "fa fa-gift",
      price: product.price || 0,
      stock: product.stock || 0,
      sort_order: product.sort_order || 0,
      currency_type: product.currency_type || "points",
      selectedTag: {
        new: product.tag === 'new',
        hot: product.tag === 'hot',
        preorder: product.tag === 'preorder'
      },
      is_partnership: true,  // 标记为合作商品
      partner_username: product.partner_username || "",
      partnership_category: product.partnership_category || "",
      related_post_url: product.related_post_url || "",
      decoration_frame_id: product.decoration_frame_id || null,
      decoration_badge_id: product.decoration_badge_id || null,
      virtual_email_template: product.virtual_email_template || "",
      virtual_address_template: product.virtual_address_template || "",
      commission_rate: product.commission_rate || 0
    };
    
    // 同步 tracked 属性 - 确保条件渲染正常工作
    this.partnershipCategory = product.partnership_category || "";
    
    // 记录正在编辑的商品ID
    this.editingPartnershipProductId = product.id;
    
    // 切换到合作商品设置标签页
    this.adminActiveTab = "partnership";
    
    console.log("📝 加载合作商品编辑数据:", this.newProduct);
    console.log("📝 分类:", this.partnershipCategory);
  }

  // ========== 付费币兑换功能 ==========

  @action
  openExchangeModal() {
    this.showExchangeModal = true;
    this.exchangeAmount = 1;
  }

  @action
  closeExchangeModal() {
    this.showExchangeModal = false;
    this.exchangeAmount = 1;
  }

  @action
  closeExchangeSuccessPopup() {
    this.showExchangeSuccess = false;
    this.exchangeResult = null;
  }
  
  @action
  updateExchangeAmount(event) {
    this.exchangeAmount = parseInt(event.target.value) || 1;
  }

  get exchangePointsGain() {
    const ratio = this.model.exchangeRatio || 100;
    return this.exchangeAmount * ratio;
  }

  get canExchange() {
    return this.exchangeAmount > 0 && this.exchangeAmount <= (this.model.userPaidCoins || 0);
  }

  @action
  async confirmExchange() {
    if (!this.canExchange) {
      alert("请输入有效的兑换数量");
      return;
    }

    const paidCoinName = this.model.paidCoinName || "付费币";
    const pointsToGet = this.exchangePointsGain;

    if (!confirm(`确定要用 ${this.exchangeAmount} ${paidCoinName} 兑换 ${pointsToGet} 积分吗？`)) {
      return;
    }

    this.isLoading = true;

    try {
      const result = await ajax("/qd/shop/exchange_coins.json", {
        type: "POST",
        data: {
          amount: this.exchangeAmount
        }
      });

      if (result.status === "success") {
        // 保存兑换结果
        this.exchangeResult = {
          paidCoinsUsed: result.paid_coins_used,
          pointsGained: result.points_gained,
          paidCoinName: paidCoinName
        };
        
        // 更新余额
        this.model.userPaidCoins = result.new_paid_coins;
        this.model.userPoints = result.new_points;
        
        // 关闭兑换模态框
        this.closeExchangeModal();
        
        // 显示成功提示框
        this.showExchangeSuccess = true;
        
        // 3秒后自动关闭
        setTimeout(() => {
          this.showExchangeSuccess = false;
        }, 3000);
      }
    } catch (error) {
      console.error("兑换失败:", error);
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }
  
  // 图标选择器相关方法
  @action
  toggleNewProductIconPicker() {
    this.showNewProductIconPicker = !this.showNewProductIconPicker;
  }
  
  @action
  toggleEditProductIconPicker() {
    this.showEditProductIconPicker = !this.showEditProductIconPicker;
  }
  
  @action
  selectNewProductIcon(icon) {
    this.newProduct = { ...this.newProduct, icon_class: icon };
    this.showNewProductIconPicker = false;
  }
  
  @action
  selectEditProductIcon(icon) {
    this.editingProduct = { ...this.editingProduct, icon_class: icon };
    this.showEditProductIconPicker = false;
  }
}