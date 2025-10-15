import Route from "@ember/routing/route";
import { ajax } from "discourse/lib/ajax";

export default class QdTpRoute extends Route {
  async model() {
    try {
      const result = await ajax("/qd/tp_data.json");
      
      if (result.success) {
        return {
          events: result.events || [],
          userBalance: result.user_balance || 0,
          isLoggedIn: result.is_logged_in || false,
          isAdmin: result.is_admin || false
        };
      }
    } catch (error) {
      if (error.jqXHR?.status === 403) {
        return { needLogin: true };
      }
      throw error;
    }
  }
}