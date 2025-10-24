import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class QdShopController extends Controller {
  @service router;
  @tracked selectedProduct = null;
  @tracked showPurchaseModal = false;
  @tracked showAdminModal = false;
  @tracked purchaseQuantity = 1;
  @tracked purchaseRemark = "";
  @tracked isLoading = false;
  @tracked showSuccessPopup = false;
  @tracked successMessage = "";
  @tracked currentFilter = "all";
  
  // 付费币相关
  @tracked showExchangeModal = false;
  @tracked exchangeAmount = 1;
  
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
    }
  };

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
    console.log("🛒 显示商品详情:", product);
    this.selectedProduct = product;
    this.purchaseQuantity = 1;
    this.purchaseRemark = "";
    this.showPurchaseModal = true;
  }

  @action
  closePurchaseModal() {
    console.log("❌ 关闭购买模态框");
    this.showPurchaseModal = false;
    this.selectedProduct = null;
  }

  @action
  updatePurchaseQuantity(event) {
    const quantity = parseInt(event.target.value) || 1;
    const maxQuantity = this.selectedProduct?.stock || 1;
    
    console.log(`📝 手动输入数量: ${quantity}, 最大库存: ${maxQuantity}`);
    
    if (quantity > 0 && quantity <= maxQuantity) {
      this.purchaseQuantity = quantity;
    } else if (quantity > maxQuantity) {
      this.purchaseQuantity = maxQuantity;
      event.target.value = maxQuantity;
    } else {
      this.purchaseQuantity = 1;
      event.target.value = 1;
    }
    
    console.log(`📝 最终数量: ${this.purchaseQuantity}`);
  }

  @action
  updatePurchaseNotes(event) {
    this.purchaseRemark = event.target.value;
    console.log(`📝 更新备注: ${this.purchaseRemark}`);
  }

  @action
  increaseQuantity() {
    console.log("➕ 增加数量按钮被点击");
    if (this.selectedProduct && this.purchaseQuantity < this.selectedProduct.stock) {
      this.purchaseQuantity++;
      console.log(`➕ 数量增加到: ${this.purchaseQuantity}`);
    } else {
      console.log("➕ 已达到最大库存限制");
    }
  }

  @action
  decreaseQuantity() {
    console.log("➖ 减少数量按钮被点击");
    if (this.purchaseQuantity > 1) {
      this.purchaseQuantity--;
      console.log(`➖ 数量减少到: ${this.purchaseQuantity}`);
    } else {
      console.log("➖ 已达到最小数量限制");
    }
  }

  @action
  async confirmPurchase() {
    console.log("🛒 确认购买按钮被点击");
    
    if (!this.selectedProduct) {
      console.log("❌ 没有选中的商品");
      alert("❌ 没有选中的商品");
      return;
    }
    
    if (this.isLoading) {
      console.log("⏳ 正在处理中，跳过重复点击");
      return;
    }
    
    console.log(`🛒 开始购买: ${this.selectedProduct.name} x${this.purchaseQuantity}`);
    this.isLoading = true;
    
    try {
      const purchaseData = {
        product_id: this.selectedProduct.id,
        quantity: this.purchaseQuantity,
        user_note: this.purchaseRemark || ""
      };
      
      console.log("🛒 发送购买请求:", purchaseData);
      
      const result = await ajax("/qd/shop/purchase", {
        type: "POST",
        data: purchaseData
      });
      
      console.log("🛒 购买响应:", result);
      
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
        console.log("❌ 购买失败:", result.message);
        alert(`❌ ${result.message || "购买失败"}`);
      }
      
    } catch (error) {
      console.error("🛒 购买异常:", error);
      const errorMessage = error.jqXHR?.responseJSON?.message || "购买失败，请稍后重试";
      alert(`❌ ${errorMessage}`);
    } finally {
      this.isLoading = false;
      console.log("🛒 购买流程结束");
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

  get filteredProducts() {
    if (!this.model.products) return [];
    
    if (this.currentFilter === "all") {
      return this.model.products;
    }
    
    return this.model.products.filter(product => {
      const name = product.name;
      switch (this.currentFilter) {
        case "新品":
          return name.includes("[新品]>");
        case "热销":
          return name.includes("[热销]>");
        case "预购":
          return name.includes("[预购]>");
        default:
          return true;
      }
    });
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
    
    // 对数字字段进行类型转换
    if (field === 'price' || field === 'stock' || field === 'sort_order') {
      value = parseInt(value) || 0;
    }
    
    // 直接赋值，@tracked 会自动处理响应式更新
    this.newProduct[field] = value;
  }
  
  @action
  async addProduct() {
    if (this.isLoading) return;
    
    this.isLoading = true;
    
    try {
      // 根据选中的标签添加前缀到商品名称
      let productName = this.newProduct.name;
      if (this.newProduct.selectedTag.new) {
        productName = '[新品]>' + productName;
      } else if (this.newProduct.selectedTag.hot) {
        productName = '[热销]>' + productName;
      } else if (this.newProduct.selectedTag.preorder) {
        productName = '[预购]>' + productName;
      }
      
      const productData = {
        ...this.newProduct,
        name: productName
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
      }
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
    // 移除标签前缀，只显示纯净的商品名称
    let cleanName = product.name || "";
    cleanName = cleanName.replace(/^\[(?:新品|热销|预购)\]>/, '');
    
    // 深拷贝商品数据，确保所有字段都被正确复制
    this.editingProduct = {
      id: product.id,
      name: cleanName,
      description: product.description || "",
      icon_class: product.icon_class || "fa fa-gift",
      price: product.price || 0,
      stock: product.stock || 0,
      sort_order: product.sort_order || 0,
      currency_type: product.currency_type || "points",
      selectedTag: {
        new: false,
        hot: false,
        preorder: false
      }
    };
    
    // 初始化标签状态
    this.initializeProductTags({ name: product.name, selectedTag: this.editingProduct.selectedTag });
    
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
      // 移除现有标签前缀，然后根据选中的标签添加新前缀
      let productName = this.editingProduct.name;
      productName = productName.replace(/^\[(?:新品|热销|预购)\]>/, '');
      
      if (this.editingProduct.selectedTag.new) {
        productName = '[新品]>' + productName;
      } else if (this.editingProduct.selectedTag.hot) {
        productName = '[热销]>' + productName;
      } else if (this.editingProduct.selectedTag.preorder) {
        productName = '[预购]>' + productName;
      }
      
      const productData = {
        name: productName,
        description: this.editingProduct.description,
        icon_class: this.editingProduct.icon_class,
        price: parseInt(this.editingProduct.price) || 0,
        stock: parseInt(this.editingProduct.stock) || 0,
        sort_order: parseInt(this.editingProduct.sort_order) || 0,
        currency_type: this.editingProduct.currency_type || "points"
      };
      
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
    
    if (field === 'price' || field === 'stock' || field === 'sort_order') {
      value = parseInt(value) || 0;
    }
    
    // 确保 editingProduct 存在
    if (!this.editingProduct) {
      this.editingProduct = {};
    }
    
    this.editingProduct[field] = value;
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
    console.log("🎉 显示成功消息:", message);
    
    // 使用简单的弹框方式
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
    // 从产品名称中解析现有标签
    if (!product.selectedTag) {
      product.selectedTag = { new: false, hot: false, preorder: false };
    }
    
    if (product.name.includes('[新品]>')) {
      product.selectedTag.new = true;
    } else if (product.name.includes('[热销]>')) {
      product.selectedTag.hot = true;
    } else if (product.name.includes('[预购]>')) {
      product.selectedTag.preorder = true;
    } else {
      // 默认为新品
      product.selectedTag.new = true;
    }
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
        alert(`兑换成功！\n消耗: ${result.paid_coins_used} ${paidCoinName}\n获得: ${result.points_gained} 积分`);
        
        // 更新余额
        this.model.userPaidCoins = result.new_paid_coins;
        this.model.userPoints = result.new_points;
        
        this.closeExchangeModal();
      }
    } catch (error) {
      console.error("兑换失败:", error);
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }
}