# frozen_string_literal: true

module ::MyPluginModule
  class JifenSignin < ActiveRecord::Base
    self.table_name = "jifen_signins"

    belongs_to :user

    validates :user_id, presence: true
    validates :date, presence: true
  end
end