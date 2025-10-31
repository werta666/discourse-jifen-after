# frozen_string_literal: true

module ::MyPluginModule
  class BettingOddsCalculator
    # 赔率限制
    MIN_ODDS = 1.1
    MAX_ODDS = 10.0
    DEFAULT_ODDS = 2.0
    PROTECTION_BASE = 100  # 保护基数，防止除以0

    class << self
      # 计算所有选项的赔率
      # @param event [BettingEvent] 竞猜事件
      # @return [Hash] { option_id => new_odds }
      def calculate_all_odds(event)
        return {} unless event.is_betting?
        
        options = event.options.by_sort_order
        return {} if options.empty?

        # 如果还没有人投注，返回默认赔率
        if event.total_pool == 0
          return options.each_with_object({}) do |option, hash|
            hash[option.id] = DEFAULT_ODDS
          end
        end

        # 计算每个选项的赔率
        options.each_with_object({}) do |option, hash|
          hash[option.id] = calculate_option_odds(event, option)
        end
      end

      # 计算单个选项的赔率
      # @param event [BettingEvent] 竞猜事件
      # @param option [BettingOption] 投注选项
      # @return [Float] 赔率
      def calculate_option_odds(event, option)
        return DEFAULT_ODDS if event.total_pool == 0
        return DEFAULT_ODDS if option.total_amount == 0

        # 基础赔率 = 总奖池 / (该选项投注额 + 保护基数)
        raw_odds = event.total_pool.to_f / (option.total_amount + PROTECTION_BASE)

        # 应用赔率限制
        clamp_odds(raw_odds)
      end

      # 更新事件的所有赔率
      # @param event [BettingEvent] 竞猜事件
      def update_event_odds!(event)
        odds_map = calculate_all_odds(event)
        
        odds_map.each do |option_id, new_odds|
          option = event.options.find(option_id)
          option.update_odds!(new_odds.round(2))
        end
      end

      # 计算投注后的新赔率（不保存）
      # @param event [BettingEvent] 竞猜事件
      # @param option_id [Integer] 选项ID
      # @param bet_amount [Integer] 投注金额
      # @return [Float] 投注后的赔率
      def preview_odds_after_bet(event, option_id, bet_amount)
        option = event.options.find(option_id)
        
        new_total_pool = event.total_pool + bet_amount
        new_option_amount = option.total_amount + bet_amount

        return DEFAULT_ODDS if new_total_pool == 0

        raw_odds = new_total_pool.to_f / (new_option_amount + PROTECTION_BASE)
        clamp_odds(raw_odds)
      end

      # 计算平台抽成后的实际奖池
      # @param total_pool [Integer] 总奖池
      # @param fee_rate [Float] 手续费率（0-1之间）
      # @return [Integer] 扣除手续费后的奖池
      def calculate_net_pool(total_pool, fee_rate = 0.05)
        (total_pool * (1 - fee_rate)).to_i
      end

      # 计算获胜者应得奖励
      # @param bet_amount [Integer] 投注金额
      # @param odds [Float] 赔率
      # @return [Integer] 获胜金额
      def calculate_win_amount(bet_amount, odds)
        (bet_amount * odds).to_i
      end

      # 凯利公式计算建议投注额
      # @param odds [Float] 赔率
      # @param win_probability [Float] 获胜概率（0-1）
      # @param balance [Integer] 用户余额
      # @return [Integer] 建议投注额
      def kelly_criterion(odds, win_probability, balance)
        return 0 if odds <= 1 || win_probability <= 0

        # 凯利公式: f = (bp - q) / b
        # b = 赔率-1, p = 获胜概率, q = 失败概率
        b = odds - 1
        q = 1 - win_probability
        f = (b * win_probability - q) / b

        # 限制最大投注比例为余额的25%（保守策略）
        f = [f, 0.25].min
        f = [f, 0].max

        (balance * f).to_i
      end

      private

      # 限制赔率在合理范围内
      def clamp_odds(odds)
        [[odds, MIN_ODDS].max, MAX_ODDS].min
      end
    end
  end
end
