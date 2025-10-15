import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "qd-tp-debug",

  initialize() {
    console.log("🎰 QD-TP Debug initializer loaded");

    withPluginApi("1.0.0", (api) => {
      console.log("🎰 QD-TP Plugin API initialized");
      
      // 添加路由调试
      if (window.location.pathname === "/qd/tp") {
        console.log("🎰 当前在 /qd/tp 页面");
      }
    });
  }
};