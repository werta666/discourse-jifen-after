import Controller from "@ember/controller";
import { computed } from "@ember/object";

export default Controller.extend({
  filterStatus: "all", // all, pending, won, lost, refunded

  // 筛选后的记录
  filteredRecords: computed("filterStatus", "model.records.[]", function() {
    if (this.filterStatus === "all") {
      return this.model.records;
    }
    return this.model.records.filter(r => r.status === this.filterStatus);
  }),

  actions: {
    setFilter(status) {
      this.set("filterStatus", status);
    },

    goBack() {
      window.history.back();
    }
  }
});
