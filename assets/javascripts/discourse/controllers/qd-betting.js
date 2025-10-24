import Controller from "@ember/controller";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { inject as service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";

export default class QdBettingController extends Controller {
  @service currentUser;
  @service siteSettings;
  
  constructor() {
    super(...arguments);
    // 页面加载时获取待处理决斗和正在进行的决斗
    if (this.currentUser) {
      this.loadPendingDuels();
      this.loadActiveDuels();
    }
  }
  
  @tracked isLoading = false;
  @tracked isCreating = false;
  @tracked selectedEvent = null;
  @tracked selectedOption = null;
  @tracked betAmount = 0;
  @tracked showBetModal = false;
  @tracked showCreateModal = false;
  @tracked filterStatus = "all";
  @tracked filterType = "all";
  @tracked filterCategory = "all";
  @tracked searchQuery = "";
  @tracked showIconPickerForIndex = null;
  
  // 决斗相关
  @tracked showDuelModal = false;
  @tracked isCreatingDuel = false;
  @tracked pendingDuels = [];
  @tracked activeDuels = [];
  @tracked duelForm = {
    opponentUsername: "",
    title: "",
    description: "",
    stakeAmount: 100
  };

  // 可用的Font Awesome图标列表
  availableIcons = [
    "fa-solid fa-crown",
    "fa-solid fa-star",
    "fa-solid fa-trophy",
    "fa-solid fa-medal",
    "fa-solid fa-fire",
    "fa-solid fa-bolt",
    "fa-solid fa-heart",
    "fa-solid fa-skull",
    "fa-solid fa-dragon",
    "fa-solid fa-shield",
    "fa-solid fa-gem",
    "fa-solid fa-wand-sparkles",
    "fa-solid fa-circle",
    "fa-solid fa-square",
    "fa-solid fa-flag",
    "fa-solid fa-diamond",
    "fa-solid fa-chess-knight",
    "fa-solid fa-chess-queen"
  ];
  
  // 创建表单
  @tracked createForm = {
    eventType: "vote",
    title: "",
    description: "",
    startTime: "",
    endTime: "",
    minBetAmount: 100,
    options: [
      { logo: "fa-solid fa-crown", name: "" },
      { logo: "fa-solid fa-star", name: "" }
    ]
  };

  // 投票创建费用
  get voteCreationCost() {
    return this.siteSettings.jifen_betting_vote_creation_cost || 100;
  }

  // 获取用户头像URL
  getUserAvatar(avatarTemplate) {
    if (!avatarTemplate) {
      return "/images/avatar.png";
    }
    // 将模板中的 {size} 替换为实际尺寸
    return avatarTemplate.replace("{size}", "48");
  }

  // 筛选后的事件
  get filteredEvents() {
    let events = this.model.events || [];
    
    // 搜索筛选
    if (this.searchQuery && this.searchQuery.trim()) {
      const query = this.searchQuery.trim().toLowerCase();
      events = events.filter(e => 
        e.title.toLowerCase().includes(query) ||
        (e.description && e.description.toLowerCase().includes(query))
      );
    }
    
    // 状态筛选
    if (this.filterStatus !== "all") {
      events = events.filter(e => e.status === this.filterStatus);
    }
    
    // 类型筛选
    if (this.filterType !== "all") {
      events = events.filter(e => e.event_type === this.filterType);
    }
    
    // 分类筛选
    if (this.filterCategory !== "all") {
      events = events.filter(e => e.category === this.filterCategory);
    }

    return events;
  }

  // 进行中的事件
  get activeEvents() {
    return this.filteredEvents.filter(e => e.status === "active");
  }

  // 即将开始的事件
  get pendingEvents() {
    return this.filteredEvents.filter(e => e.status === "pending");
  }

  // 已结束的事件
  get finishedEvents() {
    return this.filteredEvents.filter(e => e.status === "finished");
  }

  // 预期收益
  get potentialWin() {
    if (!this.selectedOption || !this.betAmount) return 0;
    return Math.floor(this.betAmount * this.selectedOption.current_odds);
  }

  // 净收益
  get netProfit() {
    return this.potentialWin - this.betAmount;
  }

  // 计算倒计时
  getTimeRemaining(endTime) {
    const now = new Date();
    const end = new Date(endTime);
    const diff = end - now;
    
    if (diff <= 0) return "已结束";
    
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    const hours = Math.floor((diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
    const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    
    if (days > 0) {
      return `${days}天${hours}小时后结束`;
    } else if (hours > 0) {
      return `${hours}小时${minutes}分钟后结束`;
    } else {
      return `${minutes}分钟后结束`;
    }
  }

  // 获取事件类型图标
  getEventTypeIcon(eventType) {
    return eventType === "bet" 
      ? "fa-solid fa-trophy" 
      : "fa-solid fa-square-poll-vertical";
  }

  // 获取事件类型文本
  getEventTypeText(eventType) {
    return eventType === "bet" ? "积分竞猜" : "普通投票";
  }

  // 获取状态图标
  getStatusIcon(status) {
    const icons = {
      active: "fa-solid fa-circle-play",
      pending: "fa-solid fa-hourglass-half",
      finished: "fa-solid fa-circle-check",
      cancelled: "fa-solid fa-circle-xmark"
    };
    return icons[status] || "fa-solid fa-circle";
  }

  // 获取状态文本
  getStatusText(status) {
    const texts = {
      active: "进行中",
      pending: "即将开始",
      finished: "已结束",
      cancelled: "已取消"
    };
    return texts[status] || status;
  }

  // 获取分类图标
  getCategoryIcon(category) {
    const icons = {
      lol: "fa-solid fa-gamepad",
      dota2: "fa-solid fa-shield-halved",
      csgo: "fa-solid fa-bullseye",
      valorant: "fa-solid fa-fire",
      other: "fa-solid fa-dice"
    };
    return icons[category] || "fa-solid fa-gamepad";
  }

  @action
  setFilter(type, value) {
    if (type === "status") {
      this.filterStatus = value;
    } else if (type === "type") {
      this.filterType = value;
    } else if (type === "category") {
      this.filterCategory = value;
    }
  }

  @action
  openBetModal(event, option) {
    if (!this.model.isLoggedIn) {
      alert("请先登录后再参与！");
      window.location.href = "/login";
      return;
    }

    // 检查是否已经投注过
    if (event.user_has_bet) {
      alert("您已经参与过该事件！");
      return;
    }

    this.selectedEvent = event;
    this.selectedOption = option;
    
    // 设置默认投注金额
    if (event.event_type === "bet") {
      this.betAmount = event.min_bet_amount || 100;
    } else {
      this.betAmount = 0;
    }
    
    this.showBetModal = true;
  }

  @action
  closeBetModal() {
    this.showBetModal = false;
    this.selectedEvent = null;
    this.selectedOption = null;
    this.betAmount = 0;
  }

  @action
  updateBetAmount(event) {
    this.betAmount = parseInt(event.target.value) || 0;
  }

  @action
  setQuickAmount(amount) {
    this.betAmount = Math.min(amount, this.model.userBalance);
  }

  @action
  stopPropagation(event) {
    event.stopPropagation();
  }

  @action
  async placeBet() {
    if (!this.selectedEvent || !this.selectedOption) {
      alert("请选择有效的选项！");
      return;
    }

    // 验证投注金额
    if (this.selectedEvent.event_type === "bet") {
      if (this.betAmount < this.selectedEvent.min_bet_amount) {
        alert(`投注金额不能低于 ${this.selectedEvent.min_bet_amount} 积分！`);
        return;
      }

      if (this.betAmount > this.model.userBalance) {
        alert("积分不足！请充值或减少投注金额。");
        return;
      }
    }

    this.isLoading = true;
    
    try {
      const result = await ajax("/qd/betting/place_bet.json", {
        type: "POST",
        data: {
          event_id: this.selectedEvent.id,
          option_id: this.selectedOption.id,
          bet_amount: this.betAmount
        }
      });

      if (result.success) {
        // 更新用户余额
        this.model.userBalance = result.new_balance;
        
        // 更新事件数据
        const eventIndex = this.model.events.findIndex(e => e.id === this.selectedEvent.id);
        if (eventIndex !== -1) {
          this.model.events[eventIndex] = result.event;
        }
        
        const message = this.selectedEvent.event_type === "bet" 
          ? `🎉 投注成功！\n投注 ${this.betAmount} 积分到 ${this.selectedOption.name}\n预期收益: ${this.potentialWin} 积分`
          : `🎉 投票成功！\n已投票给 ${this.selectedOption.name}`;
        
        alert(message);
        this.closeBetModal();
      }
    } catch (error) {
      console.error("投注失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "操作失败，请重试";
      alert("❌ " + errorMsg);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async refreshData() {
    const wasLoading = this.isLoading;
    this.isLoading = true;
    try {
      const result = await ajax("/qd/betting/events.json");
      
      if (result.success) {
        // 使用set触发响应式更新
        this.set("model.events", result.events || []);
        this.set("model.userBalance", result.user_balance || 0);
        this.notifyPropertyChange("model.events");
        this.notifyPropertyChange("model.userBalance");
        
        console.log("[竞猜] 数据已更新:", {
          events: result.events?.length || 0,
          balance: result.user_balance
        });
      }
    } catch (error) {
      console.error("刷新数据失败:", error);
      if (wasLoading) {
        alert("刷新失败，请重试");
      }
    } finally {
      this.isLoading = false;
    }
  }

  // 启动自动刷新
  startAutoRefresh() {
    // 先停止之前的定时器（如果有）
    this.stopAutoRefresh();
    // 每15秒自动刷新一次
    this.autoRefreshInterval = setInterval(() => {
      console.log("[竞猜] 自动刷新数据...");
      this.refreshData();
    }, 15000);
  }

  // 停止自动刷新
  stopAutoRefresh() {
    if (this.autoRefreshInterval) {
      clearInterval(this.autoRefreshInterval);
      this.autoRefreshInterval = null;
    }
  }

  @action
  goToMyRecords() {
    window.location.href = "/qd/betting/my_records";
  }

  @action
  openCreateModal() {
    if (!this.model.isLoggedIn) {
      alert("请先登录！");
      window.location.href = "/login";
      return;
    }
    
    // 重置表单
    this.createForm = {
      eventType: this.model.isAdmin ? "bet" : "vote",
      title: "",
      description: "",
      startTime: "",
      endTime: "",
      minBetAmount: 100,
      options: [
        { logo: "fa-solid fa-crown", name: "" },
        { logo: "fa-solid fa-star", name: "" }
      ]
    };
    
    this.showCreateModal = true;
  }

  @action
  closeCreateModal() {
    this.showCreateModal = false;
  }

  @action
  setCreateType(type) {
    this.createForm = { ...this.createForm, eventType: type };
  }

  @action
  updateCreateField(field, event) {
    const value = event.target.value;
    this.createForm = { ...this.createForm, [field]: value };
  }

  @action
  updateOption(index, field, event) {
    // 确保获取正确的值
    const value = event?.target?.value ?? event;
    const options = [...this.createForm.options];
    options[index][field] = value;
    // 触发响应式更新
    this.createForm.options = [...options];
  }

  @action
  addOption() {
    if (this.createForm.options.length < 10) {
      const options = [...this.createForm.options, { logo: "fa-solid fa-circle", name: "" }];
      this.createForm = { ...this.createForm, options };
    }
  }

  @action
  updateSearch(event) {
    this.searchQuery = event.target.value;
  }

  @action
  removeOption(index) {
    if (this.createForm.options.length > 2) {
      const options = this.createForm.options.filter((_, i) => i !== index);
      this.createForm = { ...this.createForm, options };
    }
  }

  @action
  toggleIconPicker(index) {
    if (this.showIconPickerForIndex === index) {
      this.showIconPickerForIndex = null;
    } else {
      this.showIconPickerForIndex = index;
    }
  }

  @action
  selectIcon(index, icon) {
    const options = [...this.createForm.options];
    options[index] = { ...options[index], logo: icon };
    this.createForm = { ...this.createForm, options };
    this.showIconPickerForIndex = null;
  }

  @action
  async submitCreateEvent() {
    // 验证表单
    if (!this.createForm.title || this.createForm.title.trim().length < 5) {
      alert("请输入至少5个字符的标题！");
      return;
    }

    if (!this.createForm.startTime || !this.createForm.endTime) {
      alert("请设置开始和结束时间！");
      return;
    }

    // 验证选项
    const validOptions = this.createForm.options.filter(opt => opt.name && opt.name.trim());
    if (validOptions.length < 2) {
      alert("至少需要2个有效的投注选项！");
      return;
    }

    // 验证积分竞猜的最低投注额
    if (this.createForm.eventType === "bet" && (!this.createForm.minBetAmount || this.createForm.minBetAmount < 1)) {
      alert("请设置有效的最低投注额！");
      return;
    }

    // 检查余额（普通用户创建投票需消耗积分）
    if (!this.model.isAdmin && this.createForm.eventType === "vote") {
      if (this.model.userBalance < this.voteCreationCost) {
        alert(`创建投票事件需要 ${this.voteCreationCost} 积分，您的余额不足！`);
        return;
      }
    }

    this.isCreating = true;

    try {
      const result = await ajax("/qd/betting/admin/create_event.json", {
        type: "POST",
        data: {
          title: this.createForm.title.trim(),
          description: this.createForm.description.trim(),
          event_type: this.createForm.eventType,
          category: "other",
          start_time: this.createForm.startTime,
          end_time: this.createForm.endTime,
          min_bet_amount: this.createForm.eventType === "bet" ? this.createForm.minBetAmount : null,
          options: validOptions.map((opt, idx) => ({
            name: opt.name.trim(),
            logo: opt.logo || "⚪",
            description: "",
            sort_order: idx
          }))
        }
      });

      if (result.success) {
        alert("✅ 事件创建成功！");
        this.closeCreateModal();
        
        // 刷新列表
        await this.refreshData();
      }
    } catch (error) {
      console.error("创建事件失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "创建失败，请重试";
      alert("❌ " + errorMsg);
    } finally {
      this.isCreating = false;
    }
  }

  // ========== 决斗相关方法 ==========
  
  // 决斗创建费用
  get duelCreationCost() {
    return this.siteSettings.jifen_duel_creation_cost || 50;
  }

  // 总计费用
  get totalDuelCost() {
    const stake = parseInt(this.duelForm.stakeAmount) || 0;
    return this.duelCreationCost + stake;
  }

  @action
  openDuelModal() {
    this.showDuelModal = true;
    this.duelForm = {
      opponentUsername: "",
      title: "",
      description: "",
      stakeAmount: 100
    };
  }

  @action
  closeDuelModal() {
    this.showDuelModal = false;
  }

  @action
  updateDuelForm(field, event) {
    this.duelForm = { 
      ...this.duelForm, 
      [field]: event.target.value 
    };
  }

  @action
  async submitDuel() {
    // 验证表单
    if (!this.duelForm.opponentUsername || !this.duelForm.opponentUsername.trim()) {
      alert("请输入决斗对象的用户名");
      return;
    }

    if (!this.duelForm.title || this.duelForm.title.trim().length < 5) {
      alert("决斗主题至少需要5个字符");
      return;
    }

    const stakeAmount = parseInt(this.duelForm.stakeAmount);
    if (!stakeAmount || stakeAmount <= 0) {
      alert("请输入有效的赌注金额");
      return;
    }

    this.isCreatingDuel = true;

    try {
      const result = await ajax("/qd/duel/create.json", {
        type: "POST",
        data: {
          opponent_username: this.duelForm.opponentUsername.trim(),
          title: this.duelForm.title.trim(),
          description: this.duelForm.description?.trim() || "",
          stake_amount: stakeAmount
        }
      });

      if (result.success) {
        alert("✅ " + result.message);
        this.closeDuelModal();
        this.loadPendingDuels(); // 刷新待处理决斗列表
      }
    } catch (error) {
      console.error("发起决斗失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "发起决斗失败";
      alert("❌ " + errorMsg);
    } finally {
      this.isCreatingDuel = false;
    }
  }

  // 加载待处理的决斗（对手视角）
  @action
  async loadPendingDuels() {
    try {
      const result = await ajax("/qd/duel/pending.json");
      if (result.success) {
        this.pendingDuels = result.duels || [];
      }
    } catch (error) {
      console.error("加载待处理决斗失败:", error);
    }
  }

  // 加载正在进行的决斗
  @action
  async loadActiveDuels() {
    try {
      const result = await ajax("/qd/duel/active.json");
      if (result.success) {
        this.activeDuels = result.duels || [];
      }
    } catch (error) {
      console.error("加载进行中决斗失败:", error);
    }
  }

  // 接受决斗
  @action
  async acceptDuel(duel) {
    if (!confirm(`确定接受来自 ${duel.challenger.username} 的决斗挑战吗？\n\n需要锁定 ${duel.stake_amount} 积分作为赌注。`)) {
      return;
    }

    try {
      const result = await ajax(`/qd/duel/${duel.id}/accept.json`, {
        type: "POST"
      });

      if (result.success) {
        alert("✅ " + result.message);
        this.loadPendingDuels(); // 刷新待处理列表
        this.loadActiveDuels(); // 刷新进行中列表
      }
    } catch (error) {
      console.error("接受决斗失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "接受决斗失败";
      alert("❌ " + errorMsg);
    }
  }

  // 拒绝决斗
  @action
  async rejectDuel(duel) {
    if (!confirm(`确定拒绝来自 ${duel.challenger.username} 的决斗挑战吗？`)) {
      return;
    }

    try {
      const result = await ajax(`/qd/duel/${duel.id}/reject.json`, {
        type: "POST"
      });

      if (result.success) {
        alert("✅ " + result.message);
        this.loadPendingDuels(); // 刷新列表
      }
    } catch (error) {
      console.error("拒绝决斗失败:", error);
      const errorMsg = error.jqXHR?.responseJSON?.errors?.[0] || "拒绝决斗失败";
      alert("❌ " + errorMsg);
    }
  }
}
