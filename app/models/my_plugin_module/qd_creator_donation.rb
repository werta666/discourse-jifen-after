# frozen_string_literal: true

module MyPluginModule
  class QdCreatorDonation < ActiveRecord::Base
    self.table_name = 'qd_creator_donations'
    
    belongs_to :work, class_name: 'MyPluginModule::QdCreatorWork', foreign_key: :work_id
    belongs_to :donor, class_name: 'User', foreign_key: :donor_id
    belongs_to :creator, class_name: 'User', foreign_key: :creator_id
    
    validates :work_id, presence: true
    validates :donor_id, presence: true
    validates :creator_id, presence: true
    validates :amount, presence: true, numericality: { greater_than: 0 }
    validates :currency_type, inclusion: { in: %w[jifen paid_coin] }
    validates :creator_received, presence: true, numericality: { greater_than_or_equal_to: 0 }
    
    scope :by_work, ->(work_id) { where(work_id: work_id) }
    scope :by_creator, ->(creator_id) { where(creator_id: creator_id) }
    scope :by_donor, ->(donor_id) { where(donor_id: donor_id) }
    scope :recent, -> { order(created_at: :desc) }
    
    # 计算抽成后的金额
    def self.calculate_creator_amount(amount, commission_rate)
      commission = (amount * commission_rate / 100.0).round
      creator_amount = amount - commission
      {
        commission_amount: commission,
        creator_received: creator_amount
      }
    end
  end
end
