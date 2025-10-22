# frozen_string_literal: true

module ::MyPluginModule
  class BettingSettlementService
    # 默认平台手续费率5%
    DEFAULT_FEE_RATE = 0.05

    class << self
      # 结算单个事件
      # @param event [BettingEvent] 竞猜事件
      # @param fee_rate [Float] 平台手续费率（可选）
      # @return [Hash] 结算结果
      def settle_event!(event, fee_rate: nil)
        raise StandardError, "事件不可结算" unless event.settleable?
        raise StandardError, "未设置获胜选项" unless event.winner_option_id

        fee_rate ||= get_fee_rate
        winner_option = event.winner_option
        
        ActiveRecord::Base.transaction do
          result = {
            event_id: event.id,
            total_pool: event.total_pool,
            winner_option_id: winner_option.id,
            winner_count: 0,
            loser_count: 0,
            refund_count: 0,
            platform_fee: 0,
            total_payout: 0
          }

          # 如果是普通投票，不需要结算积分
          if event.is_vote?
            settle_vote_event!(event, result)
          else
            settle_betting_event!(event, winner_option, fee_rate, result)
          end

          # 标记事件已结算
          event.update!(settled_at: Time.current)

          result
        end
      end

      # 取消事件并退款
      # @param event [BettingEvent] 竞猜事件
      # @return [Hash] 退款结果
      def refund_event!(event)
        raise StandardError, "事件已结算" if event.settled_at.present?

        ActiveRecord::Base.transaction do
          result = {
            event_id: event.id,
            refund_count: 0,
            total_refunded: 0
          }

          # 退还所有投注
          event.records.pending.find_each do |record|
            refund_record!(record)
            result[:refund_count] += 1
            result[:total_refunded] += record.bet_amount
          end

          # 取消事件
          event.cancel!

          result
        end
      end

      # 手动结算单条记录（补发奖励）
      # @param record [BettingRecord] 投注记录
      def manual_settle_record!(record)
        return if record.status != BettingRecord::STATUS_PENDING

        event = record.event
        return unless event.settled_at.present?

        if record.option_id == event.winner_option_id
          # 获胜
          win_amount = BettingOddsCalculator.calculate_win_amount(
            record.bet_amount,
            record.odds_at_bet
          )
          
          record.mark_as_won!(win_amount)
          
          # 发放奖励
          MyPluginModule::JifenService.adjust_points!(
            Discourse.system_user,
            record.user,
            win_amount
          )
        else
          # 失败
          record.mark_as_lost!
        end
      end

      private

      # 结算积分竞猜事件
      def settle_betting_event!(event, winner_option, fee_rate, result)
        # 计算平台手续费
        platform_fee = (event.total_pool * fee_rate).to_i
        net_pool = event.total_pool - platform_fee

        result[:platform_fee] = platform_fee

        # 处理获胜记录
        winner_records = event.records.pending.where(option_id: winner_option.id)
        winner_records.find_each do |record|
          settle_winner_record!(record, net_pool, winner_option.total_amount, result)
        end

        # 处理失败记录
        loser_records = event.records.pending.where.not(option_id: winner_option.id)
        loser_records.find_each do |record|
          settle_loser_record!(record, result)
        end
      end

      # 结算普通投票事件（仅更新状态）
      def settle_vote_event!(event, result)
        winner_option_id = event.winner_option_id
        
        event.records.pending.find_each do |record|
          if record.option_id == winner_option_id
            # 选择了获胜选项，标记为赢（但不发放积分，因为是投票）
            record.mark_as_won!(0)
            result[:winner_count] += 1
          else
            # 选择了失败选项，标记为输
            record.mark_as_lost!
            result[:loser_count] += 1
          end
        end
      end

      # 结算获胜记录
      def settle_winner_record!(record, net_pool, winner_total_amount, result)
        # 按投注比例分配奖池
        if winner_total_amount > 0
          win_ratio = record.bet_amount.to_f / winner_total_amount
          win_amount = (net_pool * win_ratio).to_i
        else
          win_amount = record.bet_amount  # 退还本金
        end

        # 标记为赢
        record.mark_as_won!(win_amount)

        # 发放奖励
        MyPluginModule::JifenService.adjust_points!(
          Discourse.system_user,
          record.user,
          win_amount
        )

        result[:winner_count] += 1
        result[:total_payout] += win_amount
      end

      # 结算失败记录
      def settle_loser_record!(record, result)
        record.mark_as_lost!
        result[:loser_count] += 1
      end

      # 退款单条记录
      def refund_record!(record)
        record.refund!

        # 退还积分
        MyPluginModule::JifenService.adjust_points!(
          Discourse.system_user,
          record.user,
          record.bet_amount
        )
      end

      # 获取平台手续费率
      def get_fee_rate
        # 从插件配置读取，如果没有配置则使用默认值
        SiteSetting.respond_to?(:jifen_platform_fee_rate) ? 
          (SiteSetting.jifen_platform_fee_rate.to_f / 100) : 
          DEFAULT_FEE_RATE
      end
    end
  end
end
