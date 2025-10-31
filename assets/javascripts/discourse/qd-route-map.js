// Ember v5+ 路由映射：注册 /qd 路由
export default function () {
  // 主页
  this.route("qd", { path: "/qd" });
  
  // 排行榜
  this.route("qd-board", { path: "/qd/board" });
  
  // 竞猜系统
  this.route("qd-betting", { path: "/qd/betting" });
  this.route("qd-betting-my-records", { path: "/qd/betting/my_records" });
  this.route("qd-betting-admin", { path: "/qd/betting/admin" });
  
  // 商店系统
  this.route("qd-shop", { path: "/qd/shop" });
  this.route("qd-shop-orders", { path: "/qd/shop/orders" });
  this.route("qd-shop-admin-orders", { path: "/qd/shop/admin/orders" });
  
  // 充值系统
  this.route("qd-pay", { path: "/qd/pay" });
  this.route("qd-pay-admin", { path: "/qd/pay/admin" });
  
  // 装饰系统
  this.route("qd-dress", { path: "/qd/dress" });              // 个人装饰页面
  this.route("qd-dress-admin", { path: "/qd/dress/admin" });  // 管理界面

  // VIP系统
  this.route("qd-vip", { path: "/qd/vip" });
  this.route("qd-vip-admin", { path: "/qd/vip/admin" });
  
  // 创作者申请
  this.route("qd-apply", { path: "/qd/apply" });
  
  // 创作者中心
  this.route("qd-center", { path: "/qd/center" });
  this.route("qd-center-make", { path: "/qd/center/make" });
  this.route("qd-center-admin", { path: "/qd/center/admin" });
  this.route("qd-center-work", { path: "/qd/center/zp/:work_id" });  // 作品详情页
}
