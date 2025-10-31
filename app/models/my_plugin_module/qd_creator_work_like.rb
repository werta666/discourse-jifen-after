# frozen_string_literal: true

module MyPluginModule
  class QdCreatorWorkLike < ActiveRecord::Base
    self.table_name = 'qd_creator_work_likes'
    
    belongs_to :work, class_name: 'MyPluginModule::QdCreatorWork', foreign_key: :work_id
    belongs_to :user
    
    validates :work_id, presence: true
    validates :user_id, presence: true
    validates :user_id, uniqueness: { scope: :work_id, message: "已经点赞过此作品" }
  end
end
