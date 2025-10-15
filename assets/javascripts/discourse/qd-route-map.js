 // Ember v5+ 路由映射：注册 /qd 路由
export default function () {
  this.route("qd", { path: "/qd" });
  this.route("qd-board", { path: "/qd/board" });
  this.route("qd-tp", { path: "/qd/tp" });
  this.route("qd-shop", { path: "/qd/shop" });
  this.route("qd-shop-orders", { path: "/qd/shop/orders" });
  this.route("qd-shop-admin-orders", { path: "/qd/shop/admin/orders" });
}
