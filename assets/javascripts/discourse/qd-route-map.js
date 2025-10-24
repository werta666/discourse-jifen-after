 // Ember v5+ 路由映射：注册 /qd 路由
export default function () {
  this.route("qd", { path: "/qd" });
  this.route("qd-board", { path: "/qd/board" });
  this.route("qd-betting", { path: "/qd/betting" });
  this.route("qd-betting-my-records", { path: "/qd/betting/my_records" });
  this.route("qd-betting-admin", { path: "/qd/betting/admin" });
  this.route("qd-shop", { path: "/qd/shop" });
  this.route("qd-shop-orders", { path: "/qd/shop/orders" });
  this.route("qd-shop-admin-orders", { path: "/qd/shop/admin/orders" });
  this.route("qd-pay", { path: "/qd/pay" });
  this.route("qd-pay-admin", { path: "/qd/pay/admin" });
  this.route("qd-test", { path: "/qd/test" });
}
