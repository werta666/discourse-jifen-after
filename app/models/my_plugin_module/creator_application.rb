# frozen_string_literal: true

module ::MyPluginModule
  class CreatorApplication < ActiveRecord::Base
    self.table_name = "qd_creator_applications"

    # 状态常量
    STATUS_PENDING = "pending"
    STATUS_APPROVED = "approved"
    STATUS_REJECTED = "rejected"

    # 关联
    belongs_to :user, class_name: "User", foreign_key: :user_id
    belongs_to :reviewer, class_name: "User", foreign_key: :reviewed_by, optional: true

    # 验证
    validates :user_id, presence: true, uniqueness: { scope: :status, conditions: -> { where(status: STATUS_PENDING) }, message: "已有待审核的申请" }
    validates :creative_field, presence: true, length: { minimum: 10, maximum: 500 }
    validates :creative_experience, presence: true, length: { minimum: 20, maximum: 2000 }
    validates :status, inclusion: { in: [STATUS_PENDING, STATUS_APPROVED, STATUS_REJECTED] }
    validates :application_fee, numericality: { greater_than_or_equal_to: 0 }

    # 作用域
    scope :pending, -> { where(status: STATUS_PENDING) }
    scope :approved, -> { where(status: STATUS_APPROVED) }
    scope :rejected, -> { where(status: STATUS_REJECTED) }
    scope :recent, -> { order(created_at: :desc) }

    # 实例方法
    def pending?
      status == STATUS_PENDING
    end

    def approved?
      status == STATUS_APPROVED
    end

    def rejected?
      status == STATUS_REJECTED
    end

    # 通过申请
    def approve!(reviewer_user)
      ActiveRecord::Base.transaction do
        update!(
          status: STATUS_APPROVED,
          reviewed_at: Time.current,
          reviewed_by: reviewer_user.id
        )

        # 授予创作者权限
        user.custom_fields["is_creator"] = "true"
        user.save_custom_fields(true)
        
        # 添加到白名单
        whitelist = PluginStore.get(MyPluginModule::PLUGIN_NAME, 'creator_whitelist') || []
        unless whitelist.include?(user.username)
          whitelist << user.username
          PluginStore.set(MyPluginModule::PLUGIN_NAME, 'creator_whitelist', whitelist)
        end

        # 发送系统消息
        send_approval_message(reviewer_user)
      end
    end

    # 拒绝申请
    def reject!(reviewer_user, reason:, refund: false)
      ActiveRecord::Base.transaction do
        update!(
          status: STATUS_REJECTED,
          reviewed_at: Time.current,
          reviewed_by: reviewer_user.id,
          rejection_reason: reason,
          fee_refunded: refund
        )

        # 退还申请费用
        if refund && application_fee > 0
          MyPluginModule::JifenService.adjust_points!(
            Discourse.system_user,
            user,
            application_fee
          )
        end
        
        # 删除作品集图片
        delete_portfolio_images

        # 发送系统消息
        send_rejection_message(reviewer_user, reason, refund)
      end
    end

    private
    
    # 删除作品集图片
    def delete_portfolio_images
      return if portfolio_images.blank?
      
      begin
        images = JSON.parse(portfolio_images)
        deleted_count = 0
        
        images.each do |image_url|
          next if image_url.blank?
          
          # 尝试通过URL查找Upload记录
          # URL格式: /uploads/default/original/1X/abc123def456.jpg
          upload = Upload.find_by(url: image_url)
          
          if upload
            # 删除上传记录（这会同时删除物理文件）
            upload.destroy
            deleted_count += 1
            Rails.logger.info "[创作者申请] 已删除作品集图片: #{image_url} (ID: #{upload.id})"
          else
            Rails.logger.warn "[创作者申请] 未找到上传记录: #{image_url}"
          end
        end
        
        Rails.logger.info "[创作者申请] 用户 #{user.username} 的申请被拒绝，共删除 #{deleted_count} 个作品集图片"
      rescue JSON::ParserError => e
        Rails.logger.error "[创作者申请] 解析作品集图片失败: #{e.message}"
      rescue => e
        Rails.logger.error "[创作者申请] 删除作品集图片失败: #{e.message}\n#{e.backtrace.join("\n")}"
      end
    end

    # 发送通过消息
    def send_approval_message(reviewer_user)
      PostCreator.create!(
        Discourse.system_user,
        title: "创作者申请已通过",
        raw: "恭喜！您的创作者申请已通过审核，现在您可以在创作者中心发布作品了。\n\n审核人员：@#{reviewer_user.username}\n审核时间：#{reviewed_at.strftime('%Y-%m-%d %H:%M:%S')}",
        archetype: Archetype.private_message,
        target_usernames: [user.username],
        skip_validations: true
      )
    end

    # 发送拒绝消息
    def send_rejection_message(reviewer_user, reason, refund)
      refund_text = refund ? "\n\n您的申请费用（#{application_fee} 积分）已退还，您可以修改后重新申请。" : "\n\n申请费用不予退还。"
      
      PostCreator.create!(
        Discourse.system_user,
        title: "创作者申请未通过",
        raw: "抱歉，您的创作者申请未通过审核。\n\n拒绝理由：#{reason}\n\n审核人员：@#{reviewer_user.username}\n审核时间：#{reviewed_at.strftime('%Y-%m-%d %H:%M:%S')}#{refund_text}",
        archetype: Archetype.private_message,
        target_usernames: [user.username],
        skip_validations: true
      )
    end
  end
end
