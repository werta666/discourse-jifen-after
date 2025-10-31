# frozen_string_literal: true

module ::MyPluginModule
  class DecorationGrant < ActiveRecord::Base
    self.table_name = 'qd_decoration_grants'
    
    belongs_to :user
    belongs_to :granted_by, class_name: 'User', foreign_key: 'granted_by_user_id'
    belongs_to :revoked_by, class_name: 'User', foreign_key: 'revoked_by_user_id', optional: true

    validates :user_id, presence: true
    validates :decoration_type, presence: true, inclusion: { in: ['avatar_frame', 'badge'] }
    validates :decoration_id, presence: true
    validates :granted_by_user_id, presence: true

    scope :active, -> { where(revoked: false).where('expires_at IS NULL OR expires_at > ?', Time.current) }
    scope :expired, -> { where('expires_at IS NOT NULL AND expires_at <= ?', Time.current) }
    scope :revoked, -> { where(revoked: true) }
    scope :for_user, ->(user_id) { where(user_id: user_id) }
    scope :avatar_frames, -> { where(decoration_type: 'avatar_frame') }
    scope :badges, -> { where(decoration_type: 'badge') }

    def active?
      !revoked && (expires_at.nil? || expires_at > Time.current)
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def permanent?
      expires_at.nil?
    end

    def time_remaining
      return nil if permanent? || expired?
      (expires_at - Time.current).to_i
    end
  end
end
