# frozen_string_literal: true

module ::MyPluginModule
  class UpdateLeaderboardJob < ::Jobs::Scheduled
    # 使用最小间隔1分钟，在execute中检查是否需要实际更新
    every 1.minute

    # 获取更新间隔设置
    def self.update_interval_minutes
      return 3 unless defined?(SiteSetting)
      return 3 unless SiteSetting.respond_to?(:jifen_leaderboard_update_minutes)
      
      interval = SiteSetting.jifen_leaderboard_update_minutes
      return 3 if interval.nil? || interval < 1 || interval > 60
      
      interval
    rescue => e
      Rails.logger.warn "[积分插件] 读取更新间隔设置失败: #{e.message}，使用默认值3分钟"
      3
    end

    def execute(args)
      return unless SiteSetting.jifen_enabled

      # 检查是否需要更新（基于上次更新时间）
      cache_key = "jifen_leaderboard_cache"
      last_update_key = "jifen_leaderboard_last_update"
      
      last_update_time = Rails.cache.read(last_update_key)
      current_time = Time.current
      update_interval = self.class.update_interval_minutes.minutes
      
      # 如果还没到更新时间，跳过本次执行
      if last_update_time && (current_time - last_update_time) < update_interval
        return
      end

      begin
        # 计算排行榜数据（前10名，比显示的5名多一些作为缓存）
        leaderboard_data = MyPluginModule::JifenService.calculate_leaderboard_uncached(limit: 10)
        
        # 存入缓存，设置较长的过期时间（防止任务失败时缓存丢失）
        Rails.cache.write(cache_key, leaderboard_data, expires_in: 2.hours)
        Rails.cache.write(last_update_key, current_time, expires_in: 2.hours)
        
        Rails.logger.info "[积分插件] 排行榜缓存已更新（间隔#{self.class.update_interval_minutes}分钟），共 #{leaderboard_data[:leaderboard].size} 名用户"
        
      rescue => e
        Rails.logger.error "[积分插件] 更新排行榜缓存失败: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

  end
end