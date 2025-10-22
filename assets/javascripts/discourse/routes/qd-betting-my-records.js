import DiscourseRoute from "discourse/routes/discourse";
import { ajax } from "discourse/lib/ajax";

export default DiscourseRoute.extend({
  async model() {
    try {
      const [recordsData, statsData] = await Promise.all([
        ajax("/qd/betting/my_records.json"),
        ajax("/qd/betting/my_stats.json")
      ]);
      
      return {
        records: recordsData.records || [],
        stats: statsData.stats || {}
      };
    } catch (error) {
      console.error("获取我的记录失败:", error);
      return {
        records: [],
        stats: {}
      };
    }
  }
});
