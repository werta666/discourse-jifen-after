# frozen_string_literal: true

module ::MyPluginModule
  class BettingOption < ActiveRecord::Base
    self.table_name = "jifen_betting_options"

    belongs_to :event, class_name: "MyPluginModule::BettingEvent", foreign_key: :event_id
    has_many :records, class_name: "MyPluginModule::BettingRecord", foreign_key: :option_id, dependent: :destroy

    validates :event_id, presence: true
    validates :name, presence: true, length: { maximum: 255 }
    validates :sort_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :total_amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :total_votes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :current_odds, numericality: { greater_than: 0 }

    scope :by_sort_order, -> { order(:sort_order) }
    scope :winners, -> { where(is_winner: true) }

    # 投注百分比
    def bet_percentage
      return 0 if event.total_pool == 0
      ((total_amount.to_f / event.total_pool) * 100).round(2)
    end

    # 增加投注
    def add_bet!(amount)
      increment!(:total_amount, amount)
      increment!(:total_votes, 1)
    end

    # 更新赔率
    def update_odds!(new_odds)
      update!(current_odds: new_odds)
    end
  end
end
