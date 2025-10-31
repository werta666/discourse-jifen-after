# frozen_string_literal: true

module ::MyPluginModule
  class BettingController < ::ApplicationController
    requires_plugin MyPluginModule::PLUGIN_NAME
    before_action :ensure_logged_in, except: [:index, :events]

    # 页面入口
    def index
      render "default/empty"
    end

    # 获取事件列表
    def events
      begin
        status_filter = params[:status]
        type_filter = params[:type]
        category_filter = params[:category]

        events_query = MyPluginModule::BettingEvent.includes(:options, :creator)

        # 状态筛选
        if status_filter.present?
          case status_filter
          when "active"
            events_query = events_query.active
          when "finished"
            events_query = events_query.finished
          when "pending"
            events_query = events_query.pending
          end
        else
          # 默认显示进行中和待开始的事件
          events_query = events_query.where(status: [
            MyPluginModule::BettingEvent::STATUS_ACTIVE,
            MyPluginModule::BettingEvent::STATUS_PENDING
          ])
        end

        # 类型筛选
        if type_filter.present?
          case type_filter
          when "bet"
            events_query = events_query.betting_type
          when "vote"
            events_query = events_query.vote_type
          end
        end

        # 分类筛选
        if category_filter.present? && MyPluginModule::BettingEvent::CATEGORIES.include?(category_filter)
          events_query = events_query.where(category: category_filter)
        end

        events = events_query.by_start_time.limit(50).map do |event|
          event_data(event)
        end

        render_json_dump({
          success: true,
          events: events,
          user_balance: current_user ? MyPluginModule::JifenService.available_total_points(current_user) : 0,
          is_logged_in: !!current_user,
          is_admin: current_user&.admin? || false
        })
      rescue => e
        Rails.logger.error "[竞猜] 获取事件列表失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        render_json_error("获取事件列表失败", status: 500)
      end
    end

    # 获取单个事件详情
    def show
      event = MyPluginModule::BettingEvent.includes(:options).find(params[:id])
      event.increment_views!

      # 获取用户的投注记录（如果已登录）
      user_record = nil
      if current_user
        user_record = event.records.find_by(user_id: current_user.id)
      end

      render_json_dump({
        success: true,
        event: event_data(event, detailed: true),
        user_record: user_record ? record_data(user_record) : nil
      })
    rescue ActiveRecord::RecordNotFound
      render_json_error("事件不存在", status: 404)
    rescue => e
      Rails.logger.error "[竞猜] 获取事件详情失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("获取事件详情失败", status: 500)
    end

    # 投注/投票
    def place_bet
      event_id = params.require(:event_id).to_i
      option_id = params.require(:option_id).to_i
      bet_amount = params[:bet_amount].to_i

      event = MyPluginModule::BettingEvent.find(event_id)
      option = event.options.find(option_id)

      # 验证事件状态
      unless event.bettable?
        render_json_error("该事件当前不可投注", status: 422)
        return
      end

      # 验证是否已经投注过
      if event.records.exists?(user_id: current_user.id)
        render_json_error("您已经参与过该事件", status: 422)
        return
      end

      # 验证投注金额
      if event.is_betting?
        if bet_amount < event.min_bet_amount
          render_json_error("投注金额不能低于最低投注额 #{event.min_bet_amount}", status: 422)
          return
        end

        available = MyPluginModule::JifenService.available_total_points(current_user)
        if bet_amount > available
          render_json_error("积分不足", status: 422)
          return
        end
      else
        # 普通投票，投注金额为0
        bet_amount = 0
      end

      ActiveRecord::Base.transaction do
        # 记录当前赔率
        current_odds = option.current_odds

        # 创建投注记录
        record = event.records.create!(
          user_id: current_user.id,
          option_id: option.id,
          bet_amount: bet_amount,
          odds_at_bet: current_odds,
          status: MyPluginModule::BettingRecord::STATUS_PENDING
        )

        # 如果是积分竞猜，扣除积分并更新统计
        if event.is_betting? && bet_amount > 0
          # 扣除积分
          MyPluginModule::JifenService.adjust_points!(
            current_user,
            current_user,
            -bet_amount
          )

          # 更新选项统计
          option.add_bet!(bet_amount)

          # 更新事件统计
          event.increment!(:total_pool, bet_amount)
          event.increment!(:total_bets)
          
          # 检查是否需要更新参与人数
          if event.records.where(user_id: current_user.id).count == 1
            event.increment!(:total_participants)
          end

          # 重新计算所有选项的赔率
          MyPluginModule::BettingOddsCalculator.update_event_odds!(event)
        else
          # 普通投票，只更新投票数
          option.increment!(:total_votes)
          event.increment!(:total_bets)
          
          if event.records.where(user_id: current_user.id).count == 1
            event.increment!(:total_participants)
          end
        end

        # 刷新数据
        event.reload

        new_balance = MyPluginModule::JifenService.available_total_points(current_user)

        render_json_dump({
          success: true,
          message: event.is_betting? ? "投注成功！" : "投票成功！",
          record: record_data(record),
          event: event_data(event),
          new_balance: new_balance
        })
      end
    rescue ActiveRecord::RecordNotFound
      render_json_error("事件或选项不存在", status: 404)
    rescue ActiveRecord::RecordInvalid => e
      render_json_error(e.message, status: 422)
    rescue => e
      Rails.logger.error "[竞猜] 投注失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("操作失败: #{e.message}", status: 500)
    end

    # 我的投注记录
    def my_records
      page = (params[:page] || 1).to_i
      per_page = 20

      records_query = MyPluginModule::BettingRecord
        .includes(:event, :option)
        .where(user_id: current_user.id)
        .recent

      total = records_query.count
      records = records_query.offset((page - 1) * per_page).limit(per_page)

      render_json_dump({
        success: true,
        records: records.map { |r| record_data(r, with_event: true) },
        pagination: {
          page: page,
          per_page: per_page,
          total: total,
          total_pages: (total.to_f / per_page).ceil
        }
      })
    rescue => e
      Rails.logger.error "[竞猜] 获取记录失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("获取记录失败", status: 500)
    end

    # 用户统计
    def my_stats
      records = MyPluginModule::BettingRecord.where(user_id: current_user.id)
      
      total_bets = records.count
      total_wagered = records.sum(:bet_amount)
      total_won = records.won.sum(:win_amount)
      total_lost = records.lost.sum(:bet_amount)
      win_count = records.won.count
      loss_count = records.lost.count
      win_rate = total_bets > 0 ? ((win_count.to_f / total_bets) * 100).round(2) : 0
      net_profit = total_won - total_wagered

      render_json_dump({
        success: true,
        stats: {
          total_bets: total_bets,
          total_wagered: total_wagered,
          total_won: total_won,
          total_lost: total_lost,
          win_count: win_count,
          loss_count: loss_count,
          win_rate: win_rate,
          net_profit: net_profit
        }
      })
    rescue => e
      Rails.logger.error "[竞猜] 获取统计失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("获取统计失败", status: 500)
    end

    private

    # 格式化事件数据
    def event_data(event, detailed: false)
      data = {
        id: event.id,
        title: event.title,
        description: event.description,
        event_type: event.event_type,
        category: event.category,
        status: event.status,
        start_time: event.start_time.iso8601,
        end_time: event.end_time.iso8601,
        min_bet_amount: event.min_bet_amount,
        total_pool: event.total_pool,
        total_bets: event.total_bets,
        total_participants: event.total_participants,
        views_count: event.views_count,
        time_remaining: event.time_remaining,
        creator: {
          id: event.creator.id,
          username: event.creator.username,
          avatar_template: event.creator.avatar_template
        },
        options: event.options.by_sort_order.map do |option|
          {
            id: option.id,
            name: option.name,
            logo: option.logo,
            description: option.description,
            total_amount: option.total_amount,
            total_votes: option.total_votes,
            current_odds: option.current_odds.to_f,
            bet_percentage: option.bet_percentage,
            is_winner: option.is_winner
          }
        end
      }

      if detailed
        data[:settled_at] = event.settled_at&.iso8601
        data[:winner_option_id] = event.winner_option_id
      end

      data
    end

    # 格式化记录数据
    def record_data(record, with_event: false)
      data = {
        id: record.id,
        option_id: record.option_id,
        option_name: record.option.name,
        option_logo: record.option.logo,
        bet_amount: record.bet_amount,
        odds_at_bet: record.odds_at_bet&.to_f,
        status: record.status,
        win_amount: record.win_amount,
        potential_win: record.potential_win,
        net_profit: record.net_profit,
        is_winner: record.option_id == record.event.winner_option_id,
        created_at: record.created_at.strftime("%Y-%m-%d %H:%M"),
        settled_at: record.settled_at&.strftime("%Y-%m-%d %H:%M")
      }

      if with_event
        data[:event_id] = record.event.id
        data[:event_title] = record.event.title
        data[:event_type] = record.event.event_type
        data[:event_status] = record.event.status
      end

      data
    end
  end
end
