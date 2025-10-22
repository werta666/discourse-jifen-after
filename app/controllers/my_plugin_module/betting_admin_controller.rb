# frozen_string_literal: true

module ::MyPluginModule
  class BettingAdminController < ::ApplicationController
    requires_plugin MyPluginModule::PLUGIN_NAME
    before_action :ensure_logged_in
    before_action :ensure_admin, except: [:create_event]

    # 创建事件
    def create_event
      # 如果创建积分竞猜，需要管理员权限
      if params[:event_type] == MyPluginModule::BettingEvent::TYPE_BET && !current_user.admin?
        render_json_error("只有管理员可以创建积分竞猜", status: 403)
        return
      end
      title = params.require(:title)
      description = params[:description]
      event_type = params.require(:event_type)
      category = params[:category] || "other"
      start_time = params.require(:start_time)
      end_time = params.require(:end_time)
      min_bet_amount = params[:min_bet_amount].to_i
      options_params = params.require(:options)

      # 验证事件类型
      unless [MyPluginModule::BettingEvent::TYPE_BET, MyPluginModule::BettingEvent::TYPE_VOTE].include?(event_type)
        render_json_error("无效的事件类型", status: 422)
        return
      end

      # 转换选项参数为数组
      options_array = if options_params.is_a?(Array)
        options_params
      elsif options_params.is_a?(ActionController::Parameters)
        options_params.values
      else
        []
      end

      # 验证选项数量
      if options_array.size < 2
        render_json_error("至少需要2个选项", status: 422)
        return
      end

      if options_array.size > 10
        render_json_error("最多10个选项", status: 422)
        return
      end

      # 普通用户创建投票需要消耗积分
      if !current_user.admin? && event_type == MyPluginModule::BettingEvent::TYPE_VOTE
        creation_cost = SiteSetting.jifen_betting_vote_creation_cost
        available = MyPluginModule::JifenService.available_total_points(current_user)
        
        if available < creation_cost
          render_json_error("创建投票事件需要 #{creation_cost} 积分，您的余额不足", status: 422)
          return
        end
      end

      ActiveRecord::Base.transaction do
        # 扣除创建费用（如果需要）
        if !current_user.admin? && event_type == MyPluginModule::BettingEvent::TYPE_VOTE
          creation_cost = SiteSetting.jifen_betting_vote_creation_cost
          MyPluginModule::JifenService.adjust_points!(
            current_user,
            current_user,
            -creation_cost,
            "创建投票事件"
          )
        end

        # 创建事件
        event = MyPluginModule::BettingEvent.create!(
          creator_id: current_user.id,
          title: title,
          description: description,
          event_type: event_type,
          category: category,
          start_time: Time.zone.parse(start_time),
          end_time: Time.zone.parse(end_time),
          min_bet_amount: event_type == MyPluginModule::BettingEvent::TYPE_BET ? [min_bet_amount, 1].max : 0,
          status: MyPluginModule::BettingEvent::STATUS_PENDING
        )

        # 创建选项
        options_array.each_with_index do |option_params, index|
          # 确保option_params可以正确访问
          opt = option_params.is_a?(ActionController::Parameters) ? option_params : option_params.with_indifferent_access
          
          event.options.create!(
            name: opt[:name],
            logo: opt[:logo] || "⚪",
            description: opt[:description] || "",
            sort_order: index,
            current_odds: MyPluginModule::BettingOddsCalculator::DEFAULT_ODDS
          )
        end

        render_json_dump({
          success: true,
          message: "事件创建成功",
          event: event_data(event)
        })
      end
    rescue ActiveRecord::RecordInvalid => e
      render_json_error("创建失败: #{e.message}", status: 422)
    rescue => e
      Rails.logger.error "[竞猜管理] 创建事件失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("创建事件失败: #{e.message}", status: 500)
    end

    # 更新事件
    def update_event
      event = MyPluginModule::BettingEvent.find(params[:id])

      # 只有待开始的事件可以修改
      unless event.status == MyPluginModule::BettingEvent::STATUS_PENDING
        render_json_error("只能修改待开始的事件", status: 422)
        return
      end

      update_params = {}
      update_params[:title] = params[:title] if params[:title].present?
      update_params[:description] = params[:description] if params[:description].present?
      update_params[:category] = params[:category] if params[:category].present?
      update_params[:start_time] = Time.zone.parse(params[:start_time]) if params[:start_time].present?
      update_params[:end_time] = Time.zone.parse(params[:end_time]) if params[:end_time].present?
      update_params[:min_bet_amount] = params[:min_bet_amount].to_i if params[:min_bet_amount].present?

      event.update!(update_params)

      render_json_dump({
        success: true,
        message: "事件更新成功",
        event: event_data(event)
      })
    rescue ActiveRecord::RecordNotFound
      render_json_error("事件不存在", status: 404)
    rescue ActiveRecord::RecordInvalid => e
      render_json_error("更新失败: #{e.message}", status: 422)
    rescue => e
      Rails.logger.error "[竞猜管理] 更新事件失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("更新事件失败", status: 500)
    end

    # 激活事件
    def activate_event
      event = MyPluginModule::BettingEvent.find(params[:id])
      event.activate!

      render_json_dump({
        success: true,
        message: "事件已激活",
        event: event_data(event)
      })
    rescue ActiveRecord::RecordNotFound
      render_json_error("事件不存在", status: 404)
    rescue StandardError => e
      render_json_error(e.message, status: 422)
    rescue => e
      Rails.logger.error "[竞猜管理] 激活事件失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("激活事件失败", status: 500)
    end

    # 结束事件
    def finish_event
      event = MyPluginModule::BettingEvent.find(params[:id])
      event.finish!

      render_json_dump({
        success: true,
        message: "事件已结束",
        event: event_data(event)
      })
    rescue ActiveRecord::RecordNotFound
      render_json_error("事件不存在", status: 404)
    rescue => e
      Rails.logger.error "[竞猜管理] 结束事件失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("结束事件失败", status: 500)
    end

    # 取消事件
    def cancel_event
      event = MyPluginModule::BettingEvent.find(params[:id])
      
      # 普通投票直接取消，不涉及退款
      if event.is_vote?
        event.cancel!
        
        render_json_dump({
          success: true,
          message: "投票事件已取消"
        })
      # 积分竞猜：如果有投注，执行退款
      elsif event.total_bets > 0
        result = MyPluginModule::BettingSettlementService.refund_event!(event)
        
        render_json_dump({
          success: true,
          message: "事件已取消，已退款 #{result[:total_refunded]} 积分给 #{result[:refund_count]} 位参与者",
          refund_result: result
        })
      else
        event.cancel!
        
        render_json_dump({
          success: true,
          message: "事件已取消"
        })
      end
    rescue ActiveRecord::RecordNotFound
      render_json_error("事件不存在", status: 404)
    rescue StandardError => e
      render_json_error(e.message, status: 422)
    rescue => e
      Rails.logger.error "[竞猜管理] 取消事件失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("取消事件失败", status: 500)
    end

    # 删除事件
    def delete_event
      event = MyPluginModule::BettingEvent.find(params[:id])
      
      # 只能删除未开始或已结束且无投注的事件
      if event.status == 'active'
        render_json_error("进行中的事件不能删除，请先结束或取消", status: 422)
        return
      end
      
      if event.records.exists?
        render_json_error("已有投注的事件不能删除，只能取消", status: 422)
        return
      end
      
      event_title = event.title
      event.destroy!
      
      render_json_dump({
        success: true,
        message: "事件《#{event_title}》已删除"
      })
    rescue ActiveRecord::RecordNotFound
      render_json_error("事件不存在", status: 404)
    rescue => e
      Rails.logger.error "[竞猜管理] 删除事件失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("删除事件失败: #{e.message}", status: 500)
    end

    # 设置获胜选项
    def set_winner
      event = MyPluginModule::BettingEvent.find(params[:id])
      option_id = params.require(:option_id).to_i

      event.set_winner!(option_id)

      render_json_dump({
        success: true,
        message: "已设置获胜选项",
        event: event_data(event)
      })
    rescue ActiveRecord::RecordNotFound
      render_json_error("事件不存在", status: 404)
    rescue StandardError => e
      render_json_error(e.message, status: 422)
    rescue => e
      Rails.logger.error "[竞猜管理] 设置获胜选项失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("设置获胜选项失败", status: 500)
    end

    # 结算事件
    def settle_event
      event = MyPluginModule::BettingEvent.find(params[:id])
      
      result = MyPluginModule::BettingSettlementService.settle_event!(event)

      render_json_dump({
        success: true,
        message: "结算完成",
        settlement_result: result
      })
    rescue ActiveRecord::RecordNotFound
      render_json_error("事件不存在", status: 404)
    rescue StandardError => e
      render_json_error(e.message, status: 422)
    rescue => e
      Rails.logger.error "[竞猜管理] 结算失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("结算失败: #{e.message}", status: 500)
    end

    # 管理员事件列表
    def events_list
      page = (params[:page] || 1).to_i
      per_page = 20

      events_query = MyPluginModule::BettingEvent.includes(:creator, :options)
      
      # 状态筛选
      if params[:status].present?
        events_query = events_query.where(status: params[:status])
      end

      total = events_query.count
      events = events_query.by_start_time
        .offset((page - 1) * per_page)
        .limit(per_page)
        .map { |e| event_data(e, detailed: true) }

      render_json_dump({
        success: true,
        events: events,
        pagination: {
          page: page,
          per_page: per_page,
          total: total,
          total_pages: (total.to_f / per_page).ceil
        }
      })
    rescue => e
      Rails.logger.error "[竞猜管理] 获取事件列表失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      render_json_error("获取事件列表失败", status: 500)
    end

    # 事件统计
    def event_stats
      event = MyPluginModule::BettingEvent.includes(:options, :records).find(params[:id])

      records_by_option = event.records.group(:option_id).count
      amounts_by_option = event.records.group(:option_id).sum(:bet_amount)
      
      options_stats = event.options.map do |option|
        {
          id: option.id,
          name: option.name,
          logo: option.logo,
          total_votes: option.total_votes,
          total_amount: option.total_amount,
          current_odds: option.current_odds.to_f,
          bet_percentage: option.bet_percentage,
          unique_bettors: records_by_option[option.id] || 0,
          is_winner: option.is_winner
        }
      end

      render_json_dump({
        success: true,
        event: event_data(event, detailed: true),
        options_stats: options_stats,
        summary: {
          total_participants: event.total_participants,
          total_bets: event.total_bets,
          total_pool: event.total_pool,
          views_count: event.views_count
        }
      })
    rescue ActiveRecord::RecordNotFound
      render_json_error("事件不存在", status: 404)
    rescue => e
      Rails.logger.error "[竞猜管理] 获取统计失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
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
        created_at: event.created_at.iso8601,
        creator: {
          id: event.creator.id,
          username: event.creator.username
        },
        options: event.options.by_sort_order.map do |option|
          {
            id: option.id,
            name: option.name,
            logo: option.logo,
            total_amount: option.total_amount,
            total_votes: option.total_votes,
            current_odds: option.current_odds.to_f,
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
  end
end
