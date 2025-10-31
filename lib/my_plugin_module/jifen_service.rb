# frozen_string_literal: true

require "json"

module ::MyPluginModule
  module JifenService
    module_function

    def rewards_map
      raw = SiteSetting.jifen_consecutive_rewards_json.presence || "{}"
      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end

    def base_points
      SiteSetting.jifen_base_points_per_signin.to_i
    end

    def signed_today?(user_id)
      MyPluginModule::JifenSignin.exists?(user_id: user_id, date: Time.zone.today)
    end

    def last_signin(user_id)
      MyPluginModule::JifenSignin.where(user_id: user_id).order(date: :desc).first
    end

    def total_points(user_id)
      MyPluginModule::JifenSignin.where(user_id: user_id).sum(:points)
    end

    def today_points(user_id)
      MyPluginModule::JifenSignin.where(user_id: user_id, date: Time.zone.today).sum(:points)
    end

    # 用户自定义字段：已消费积分与补签卡数量
    def spent_points(user)
      (user.custom_fields["jifen_spent"].presence || 0).to_i
    end

    def makeup_cards(user)
      (user.custom_fields["jifen_makeup_cards"].presence || 0).to_i
    end

    def available_total_points(user)
      total_points(user.id) - spent_points(user)
    end

    # 购买补签卡：扣减可用积分、增加补签卡数量，并返回最新概览
    def purchase_makeup_card!(user)
      price = SiteSetting.jifen_makeup_card_price.to_i
      raise StandardError, "积分不足" if available_total_points(user) < price

      user.custom_fields["jifen_makeup_cards"] = makeup_cards(user) + 1
      user.custom_fields["jifen_spent"] = spent_points(user) + price
      user.save_custom_fields(true)

      summary_for(user)
    end

    # 手动调整积分（管理员）：delta>0 增加可用积分，delta<0 减少可用积分
    # 通过调整 jifen_spent 实现，并写入后台操作日志
    def adjust_points!(acting_user, target_user, delta)
      d = delta.to_i
      raise StandardError, "调整值不能为 0" if d == 0

      before_spent = spent_points(target_user)
      before_avail = available_total_points(target_user)

      new_spent = before_spent - d
      total = total_points(target_user.id)

      # 管理员调整积分：移除限制，允许任意调整
      # new_spent = 0 if new_spent < 0
      # new_spent = total if new_spent > total

      target_user.custom_fields["jifen_spent"] = new_spent
      target_user.save_custom_fields(true)

      begin
        StaffActionLogger.new(acting_user).log_custom(
          "jifen_adjust_points",
          target_user_id: target_user.id,
          target_username: target_user.username,
          delta: d,
          before_spent: before_spent,
          after_spent: new_spent,
          before_available: before_avail,
          after_available: available_total_points(target_user)
        )
      rescue StandardError
        # 忽略日志异常
      end

      summary_for(target_user)
    end

    # 重置指定用户“今日签到”状态（删除今日记录），允许重新签到
    def reset_today!(acting_user, target_user)
      removed = MyPluginModule::JifenSignin.where(user_id: target_user.id, date: Time.zone.today).delete_all

      begin
        StaffActionLogger.new(acting_user).log_custom(
          "jifen_reset_today",
          target_user_id: target_user.id,
          target_username: target_user.username,
          removed: removed
        )
      rescue StandardError
        # 忽略日志异常
      end

      removed
    end

    # 用于 summary 展示的连续天数（若今天没签，取到昨日为止的连续天数）
    def compute_streak_on_summary(user_id)
      last = last_signin(user_id)
      return 0 unless last
      if last.date == Time.zone.today
        last.streak_count
      elsif last.date == Time.zone.yesterday
        last.streak_count
      else
        0
      end
    end

    def next_reward_info(streak, rewards)
      return nil if rewards.blank?
      entries = rewards.map { |k, v| [k.to_i, v.to_i] }.sort_by(&:first)
      entries.each do |days, pts|
        if days > streak
          return { days: days, points: pts, remain: days - streak }
        end
      end
      nil
    end

    def recent_records_for(user_id, days: 7)
      start_date = Time.zone.today - (days - 1)
      MyPluginModule::JifenSignin
        .where(user_id: user_id)
        .where("date >= ?", start_date)
        .order(date: :desc)
        .limit(days)
        .map do |r|
          {
            date: r.date.to_s,
            signed_at: r.signed_at&.iso8601,
            makeup: r.makeup,
            points: r.points,
            streak_count: r.streak_count
          }
        end
    end

    def summary_for(user)
      uid = user.id
      signed = signed_today?(uid)
      streak = compute_streak_on_summary(uid)
      total_available = available_total_points(user)
      today = today_points(uid)
      rewards = rewards_map
      next_rw = next_reward_info(streak, rewards)
      install_date = MyPluginModule::JifenSignin.order(:date).limit(1).pluck(:date).first || Time.zone.today
      recent = recent_records_for(uid, days: 7)

      data = {
        user_logged_in: true,
        signed: signed,
        consecutive_days: streak,
        total_score: total_available,
        today_score: today,
        points: base_points,
        makeup_cards: makeup_cards(user),
        makeup_card_price: SiteSetting.jifen_makeup_card_price.to_i,
        install_date: install_date.to_s,
        rewards: rewards,
        recent_records: recent
      }
      data[:next_reward] = next_rw if next_rw
      data
    end

    def signin!(user)
      uid = user.id
      return summary_for(user) if signed_today?(uid)

      rewards = rewards_map
      vip_bonus = 0
      vip_info = nil
      
      ActiveRecord::Base.transaction do
        prev = MyPluginModule::JifenSignin.where(user_id: uid).order(date: :desc).lock(true).first
        if prev && prev.date == Time.zone.today
          raise ActiveRecord::RecordNotUnique
        end

        new_streak =
          if prev && prev.date == Time.zone.yesterday
            prev.streak_count + 1
          else
            1
          end

        reward_points = rewards[new_streak.to_s].to_i
        pts = base_points + reward_points
        
        # 检查用户是否是VIP，获取VIP签到额外积分
        current_vip = QdVipSubscription.current_vip_for(user)
        if current_vip && current_vip.valid_subscription?
          vip_package = QdVipPackage.find_by(id: current_vip.package_id)
          if vip_package && vip_package.daily_signin_bonus > 0
            vip_bonus = vip_package.daily_signin_bonus
            pts += vip_bonus
            vip_info = {
              level: current_vip.vip_level,
              bonus: vip_bonus
            }
          end
        end

        MyPluginModule::JifenSignin.create!(
          user_id: uid,
          date: Time.zone.today,
          signed_at: Time.zone.now,
          makeup: false,
          points: pts,
          streak_count: new_streak
        )
      end

      result = summary_for(user)
      # 添加VIP签到奖励信息
      if vip_info
        result[:vip_signin_bonus] = vip_info
      end
      result
    end

    # 系统启用日期（用于限制补签下限）：取最早一条签到记录的日期；若无记录，则为今日
    def install_date
      MyPluginModule::JifenSignin.order(:date).limit(1).pluck(:date).first || Time.zone.today
    end

    # 补签指定日期：仅允许系统启用日（含）之后、且不晚于今日的日期；需要消耗 1 张补签卡
    # 返回最新 summary（用于前端刷新）
    def makeup_on_date!(user, date_str)
      raise StandardError, "参数错误" if date_str.blank?
      date = begin
        Date.parse(date_str)
      rescue ArgumentError
        nil
      end
      raise StandardError, "日期格式不正确" unless date

      today = Time.zone.today
      inst = install_date
      raise StandardError, "不能补签未来日期" if date > today
      raise StandardError, "不能补签启用日期之前（#{inst}）" if date < inst

      if MyPluginModule::JifenSignin.exists?(user_id: user.id, date: date)
        raise StandardError, "该日期已存在签到记录"
      end

      cards = makeup_cards(user)
      raise StandardError, "补签卡不足" if cards <= 0

      # 补签得分 = 基础积分 * 比例（0-100%），默认 100%
      ratio = SiteSetting.respond_to?(:jifen_makeup_ratio_percent) ? SiteSetting.jifen_makeup_ratio_percent.to_i : 100
      ratio = 0 if ratio < 0
      ratio = 100 if ratio > 100
      pts = (base_points * ratio / 100)

      ActiveRecord::Base.transaction do
        # 扣 1 张补签卡
        user.custom_fields["jifen_makeup_cards"] = cards - 1
        user.save_custom_fields(true)

        # 计算补签日期的连续天数
        # 关键：需要检查后一天的记录来判断是否应该追溯前面的连续天数
        next_record = MyPluginModule::JifenSignin
          .where(user_id: user.id)
          .where("date > ?", date)
          .order(date: :asc)
          .first
        
        prev_record = MyPluginModule::JifenSignin
          .where(user_id: user.id)
          .where("date < ?", date)
          .order(date: :desc)
          .first
        
        # 如果后一天存在记录
        if next_record
          # 如果后一天是连续的（date + 1）
          if next_record.date == date + 1
            # 如果后一天的 streak_count = 1，说明是重新开始的，补签也应该是1
            # 如果后一天的 streak_count > 1，说明是连续的，需要检查前一天
            if next_record.streak_count == 1
              new_streak = 1
            elsif prev_record && prev_record.date == date - 1
              new_streak = prev_record.streak_count + 1
            else
              new_streak = 1
            end
          else
            # 后一天不连续，按正常逻辑处理
            new_streak = if prev_record && prev_record.date == date - 1
              prev_record.streak_count + 1
            else
              1
            end
          end
        else
          # 没有后续记录，按正常逻辑处理
          new_streak = if prev_record && prev_record.date == date - 1
            prev_record.streak_count + 1
          else
            1
          end
        end

        # 创建补签记录
        MyPluginModule::JifenSignin.create!(
          user_id: user.id,
          date: date,
          signed_at: Time.zone.now,
          makeup: true,
          points: pts,
          streak_count: new_streak
        )

        # 重新计算该日期之后所有签到记录的连续天数
        recalculate_streaks_after!(user.id, date)
      end

      summary_for(user)
    end

    # 重新计算指定日期之后所有签到记录的连续天数
    def recalculate_streaks_after!(user_id, start_date)
      records = MyPluginModule::JifenSignin
        .where(user_id: user_id)
        .where("date > ?", start_date)
        .order(date: :asc)
      
      records.each do |record|
        prev_record = MyPluginModule::JifenSignin
          .where(user_id: user_id)
          .where("date < ?", record.date)
          .order(date: :desc)
          .first
        
        new_streak = if prev_record && prev_record.date == record.date - 1
          prev_record.streak_count + 1
        else
          1
        end
        
        record.update_column(:streak_count, new_streak) if record.streak_count != new_streak
      end
    end

    # 获取积分排行榜（从缓存读取，性能优化版本）
    def self.get_leaderboard(limit: 5)
      cache_key = "jifen_leaderboard_cache"
      cached_data = Rails.cache.read(cache_key)
      
      if cached_data
        # 从缓存中取前N名
        limited_leaderboard = cached_data[:leaderboard].first(limit)
        return {
          leaderboard: limited_leaderboard,
          updated_at: cached_data[:updated_at],
          from_cache: true
        }
      else
        # 缓存未命中，实时计算并写入缓存
        Rails.logger.warn "[积分插件] 排行榜缓存未命中，执行实时计算"
        fresh_data = calculate_leaderboard_uncached(limit: 10)
        Rails.cache.write(cache_key, fresh_data, expires_in: 1.hour)
        
        return {
          leaderboard: fresh_data[:leaderboard].first(limit),
          updated_at: fresh_data[:updated_at],
          from_cache: false
        }
      end
    end

    # 强制刷新排行榜缓存（管理员功能）
    def self.force_refresh_leaderboard!
      cache_key = "jifen_leaderboard_cache"
      last_update_key = "jifen_leaderboard_last_update"
      fresh_data = calculate_leaderboard_uncached(limit: 10)
      current_time = Time.current
      
      Rails.cache.write(cache_key, fresh_data, expires_in: 2.hours)
      Rails.cache.write(last_update_key, current_time, expires_in: 2.hours)
      
      Rails.logger.info "[积分插件] 管理员强制刷新排行榜缓存"
      fresh_data
    end

    # 刷新排行榜缓存（后台任务和设置变更使用）
    def self.refresh_leaderboard_cache!
      cache_key = "jifen_leaderboard_cache"
      last_update_key = "jifen_leaderboard_last_update"
      fresh_data = calculate_leaderboard_uncached(limit: 10)
      current_time = Time.current
      
      Rails.cache.write(cache_key, fresh_data, expires_in: 2.hours)
      Rails.cache.write(last_update_key, current_time, expires_in: 2.hours)
      
      Rails.logger.info "[积分插件] 排行榜缓存已刷新"
      fresh_data
    end

    # 实际计算排行榜的方法（无缓存）
    def self.calculate_leaderboard_uncached(limit: 5)
      # 获取所有有签到记录的用户ID
      user_ids = MyPluginModule::JifenSignin.distinct.pluck(:user_id)
      
      # 计算每个用户的可用积分并排序
      user_scores = user_ids.map do |user_id|
        user = User.find_by(id: user_id)
        next unless user
        
        total = total_points(user_id)
        spent = spent_points(user)
        available = total - spent
        
        {
          user_id: user_id,
          username: user.username,
          available_points: available
        }
      end.compact.select { |u| u[:available_points] > 0 }
      
      # 按可用积分降序排列，取前N名
      top_users = user_scores.sort_by { |u| -u[:available_points] }.first(limit)
      
      leaderboard = top_users.map.with_index(1) do |user, rank|
        {
          rank: rank,
          username: user[:username],
          points: user[:available_points]
        }
      end

      {
        leaderboard: leaderboard,
        updated_at: Time.zone.now.iso8601
      }
    end
  end
end
