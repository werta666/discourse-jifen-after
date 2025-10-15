# frozen_string_literal: true

module ::MyPluginModule
  class QdController < ::ApplicationController
    requires_plugin MyPluginModule::PLUGIN_NAME

    before_action :ensure_logged_in, except: [:index, :board, :tp, :tp_data]

    # Ember 引导页
    def index
      render "default/empty"
    end

    # 概览数据（/qd 页面所需）
    def summary
      render_json_dump MyPluginModule::JifenService.summary_for(current_user)
    end

    # 签到记录：仅返回最近 7 天（按日期倒序）
    def records
      start_date = Time.zone.today - 6
      recs = MyPluginModule::JifenSignin
        .where(user_id: current_user.id)
        .where("date >= ?", start_date)
        .order(date: :desc)

      render_json_dump(
        records: recs.map do |r|
          {
            date: r.date.to_s,
            signed_at: r.signed_at&.iso8601,
            makeup: r.makeup,
            points: r.points,
            streak_count: r.streak_count
          }
        end
      )
    end

    # 今日签到
    def signin
      render_json_dump MyPluginModule::JifenService.signin!(current_user)
    rescue ActiveRecord::RecordNotUnique
      render_json_error("今日已签到", status: 409)
    rescue => e
      render_json_error(e.message)
    end

    # 补签：仅允许系统启用日（含）之后、且不晚于今日的日期；消耗 1 张补签卡
    def makeup
      summary = MyPluginModule::JifenService.makeup_on_date!(current_user, params[:date])
      render_json_dump(summary)
    rescue StandardError => e
      render_json_error(e.message)
    end

    # 购买补签卡：扣减可用积分并增加卡数，返回最新概览
    def buy_makeup_card
      render_json_dump MyPluginModule::JifenService.purchase_makeup_card!(current_user)
    rescue StandardError => e
      render_json_error(e.message)
    end

    # 积分排行榜（前五名）
    def board
      # 未登录用户返回需要登录的提示
      unless current_user
        render_json_dump({
          requires_login: true,
          message: "请登录后查看积分排行榜",
          leaderboard: [],
          updated_at: Time.zone.now.iso8601
        })
        return
      end

      begin
        board_data = MyPluginModule::JifenService.get_leaderboard(limit: 5)
        render_json_dump(board_data.merge(
          requires_login: false,
          is_admin: current_user.admin?
        ))
      rescue => e
        Rails.logger.error "获取排行榜失败: #{e.message}"
        render_json_error("获取排行榜失败", status: 500)
      end
    end

    # 管理员强制刷新排行榜缓存
    def force_refresh_board
      ensure_logged_in
      ensure_admin
      
      begin
        fresh_data = MyPluginModule::JifenService.force_refresh_leaderboard!
        render_json_dump({
          success: true,
          message: "排行榜缓存已强制刷新",
          leaderboard: fresh_data[:leaderboard].first(5),
          updated_at: fresh_data[:updated_at]
        })
      rescue => e
        Rails.logger.error "强制刷新排行榜失败: #{e.message}"
        render_json_error("强制刷新失败", status: 500)
      end
    end

    # 投票竞猜页面
    def tp
      Rails.logger.info "🎰 投票竞猜页面访问"
      render "default/empty"
    rescue => e
      Rails.logger.error "🎰 投票竞猜页面错误: #{e.message}"
      render plain: "Error: #{e.message}", status: 500
    end

    # 投票竞猜数据接口
    def tp_data
      Rails.logger.info "🎰 tp_data 接口被调用，用户: #{current_user&.username || '未登录'}"
      
      begin
        # 模拟电竞赛事投票数据
        mock_events = [
          {
            id: 1,
            title: "2024 LPL春季赛决赛",
            subtitle: "JDG vs BLG",
            status: "active", # active, closed, finished
            end_time: (Time.current + 2.hours).iso8601,
            total_votes: 1247,
            total_pool: 15680,
            options: [
              {
                id: 1,
                name: "JDG",
                logo: "🏆",
                odds: 1.85,
                votes: 687,
                pool: 8420
              },
              {
                id: 2,
                name: "BLG", 
                logo: "⚡",
                odds: 2.15,
                votes: 560,
                pool: 7260
              }
            ]
          },
          {
            id: 2,
            title: "DOTA2 国际邀请赛",
            subtitle: "Team Spirit vs PSG.LGD",
            status: "active",
            end_time: (Time.current + 4.hours).iso8601,
            total_votes: 892,
            total_pool: 11240,
            options: [
              {
                id: 3,
                name: "Team Spirit",
                logo: "👻",
                odds: 2.3,
                votes: 340,
                pool: 4680
              },
              {
                id: 4,
                name: "PSG.LGD",
                logo: "🐉",
                odds: 1.7,
                votes: 552,
                pool: 6560
              }
            ]
          },
          {
            id: 3,
            title: "CS2 Major决赛",
            subtitle: "FaZe vs NAVI",
            status: "finished",
            end_time: (Time.current - 1.hour).iso8601,
            winner_id: 5,
            total_votes: 2156,
            total_pool: 28940,
            options: [
              {
                id: 5,
                name: "FaZe",
                logo: "🔥",
                odds: 2.1,
                votes: 1024,
                pool: 15680,
                winner: true
              },
              {
                id: 6,
                name: "NAVI",
                logo: "⭐",
                odds: 1.9,
                votes: 1132,
                pool: 13260
              }
            ]
          }
        ]

        response_data = {
          success: true,
          events: mock_events,
          user_balance: current_user ? MyPluginModule::JifenService.available_total_points(current_user) : 0,
          is_logged_in: !!current_user,
          is_admin: current_user&.admin? || false
        }
        
        Rails.logger.info "🎰 tp_data 返回数据: events=#{mock_events.length}, user_balance=#{response_data[:user_balance]}, logged_in=#{response_data[:is_logged_in]}"
        
        render_json_dump(response_data)
      rescue => e
        Rails.logger.error "🎰 获取投票数据失败: #{e.message}"
        render_json_error("获取数据失败", status: 500)
      end
    end

    # 投票接口
    def tp_vote
      if !current_user
        render_json_error("请先登录", status: 403)
        return
      end

      begin
        event_id = params[:event_id]&.to_i
        option_id = params[:option_id]&.to_i
        bet_amount = params[:bet_amount]&.to_i || 0

        # 校验余额并扣减可用积分（使用本插件积分口径）
        if bet_amount <= 0
          render_json_error("无效的投注金额", status: 422)
          return
        end

        available = MyPluginModule::JifenService.available_total_points(current_user)
        if bet_amount > available
          render_json_error("积分不足", status: 422)
          return
        end

        # 扣减可用积分并记录审计，返回最新 summary（含 total_score）
        summary = MyPluginModule::JifenService.adjust_points!(current_user, current_user, -bet_amount)

        render_json_dump({
          success: true,
          message: "投票成功！",
          event_id: event_id,
          option_id: option_id,
          bet_amount: bet_amount,
          new_balance: summary[:total_score]
        })
      rescue => e
        Rails.logger.error "🎰 投票失败: #{e.message}"
        render_json_error("投票失败: #{e.message}", status: 500)
      end
    end
  end
end