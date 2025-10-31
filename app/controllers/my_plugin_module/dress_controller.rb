# frozen_string_literal: true

module MyPluginModule
  class DressController < ::ApplicationController
    requires_plugin 'jifen-system'
    # 只有管理相关的接口需要管理员权限
    before_action :ensure_admin, only: [:admin, :upload_frame, :upload_badge, :delete_frame, :delete_badge, :grants, :grant, :revoke_grant]
    before_action :ensure_logged_in, only: [:index, :equip_frame, :equip_badge]

    PLUGIN_NAME = "jifen_decoration_system"

    # 管理界面主页
    def admin
      render json: {
        avatar_frames: get_all_frames,
        badges: get_all_badges,
        grants_summary: get_grants_summary
      }
    end

    # 获取所有头像框
    def frames
      render json: { frames: get_all_frames }
    end

    # 获取所有勋章
    def badges
      render json: { badges: get_all_badges }
    end

    # 上传头像框（管理员）
    def upload_frame
      file = params[:file]
      name = params[:name]
      
      unless file
        return render json: { error: "未选择文件" }, status: 400
      end
      
      unless name.present?
        return render json: { error: "请输入头像框名称" }, status: 400
      end
      
      # 验证名称格式
      unless name =~ /^[a-zA-Z0-9_-]+$/
        return render json: { error: "名称只能包含字母、数字、下划线和连字符" }, status: 400
      end
      
      begin
        # 获取下一个ID
        frame_id = (PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                                  .where("key LIKE ?", "decoration_avatar_frame_%")
                                  .count + 1)
        
        # 创建上传目录
        upload_dir = File.join(Rails.root, "public", "uploads", "default", "decoration-frames")
        FileUtils.mkdir_p(upload_dir)
        
        # 使用用户定义的名称 + 文件扩展名
        ext = file.original_filename.split('.').last.downcase
        filename = "#{name}.#{ext}"
        file_path = File.join(upload_dir, filename)
        
        # 检查文件是否已存在
        if File.exist?(file_path)
          return render json: { error: "名称为 '#{name}' 的头像框已存在，请使用其他名称" }, status: 400
        end
        
        # 保存文件
        File.open(file_path, "wb") do |f|
          file.rewind
          f.write(file.read)
        end
        
        Rails.logger.info "[装饰系统] 头像框已保存: #{file_path}"
        
        # 生成URL
        image_url = "/uploads/default/decoration-frames/#{filename}"
        
        frame_data = {
          id: frame_id,
          name: name,
          image: image_url,
          width: params[:width].to_i > 0 ? params[:width].to_i : 64,
          height: params[:height].to_i > 0 ? params[:height].to_i : 64,
          top: params[:top] ? params[:top].to_i : -8,
          left: params[:left] ? params[:left].to_i : -8,
          uploaded_at: Time.current.iso8601,
          uploaded_by: current_user.username
        }
        
        # 保存到数据库
        PluginStore.set(PLUGIN_NAME, "decoration_avatar_frame_#{frame_id}", frame_data.to_json)
        
        render json: {
          success: true,
          frame: frame_data,
          message: "头像框上传成功"
        }
      rescue => e
        Rails.logger.error "[装饰系统] 上传头像框失败: #{e.message}"
        render json: { error: "上传失败：#{e.message}" }, status: 500
      end
    end

    # 上传勋章（管理员）
    def upload_badge
      name = params[:name]
      badge_type = params[:type] # "text" or "image"
      
      unless name.present? && badge_type.present?
        return render json: { error: "参数不完整" }, status: 400
      end
      
      begin
        # 获取下一个ID
        badge_id = (PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                                  .where("key LIKE ?", "decoration_badge_%")
                                  .count + 1)
        
        if badge_type == "text"
          text = params[:text]
          style = params[:style] || ""
          
          unless text.present?
            return render json: { error: "文字内容不能为空" }, status: 400
          end
          
          badge_data = {
            id: badge_id,
            name: name,
            type: "text",
            text: text,
            style: style,
            uploaded_at: Time.current.iso8601,
            uploaded_by: current_user.username
          }
        else
          file = params[:file]
          
          unless file.present?
            return render json: { error: "文件不能为空" }, status: 400
          end
          
          # 验证文件类型
          unless ["image/png", "image/webp", "image/gif"].include?(file.content_type)
            return render json: { error: "只支持 PNG/WEBP/GIF 格式" }, status: 400
          end
          
          # 创建上传目录
          upload_dir = File.join(Rails.root, "public", "uploads", "default", "decoration-badges")
          FileUtils.mkdir_p(upload_dir)
          
          # 生成唯一文件名
          ext = file.original_filename.split('.').last
          filename = "badge_#{Time.now.to_i}_#{SecureRandom.hex(4)}.#{ext}"
          file_path = File.join(upload_dir, filename)
          
          # 保存文件
          File.open(file_path, "wb") do |f|
            file.rewind
            f.write(file.read)
          end
          
          Rails.logger.info "[装饰系统] 勋章已保存: #{file_path}"
          
          # 生成URL
          image_url = "/uploads/default/decoration-badges/#{filename}"
          
          badge_data = {
            id: badge_id,
            name: name,
            type: "image",
            image: image_url,
            height: params[:height].to_i > 0 ? params[:height].to_i : 25,
            uploaded_at: Time.current.iso8601,
            uploaded_by: current_user.username
          }
        end
        
        # 保存到数据库
        PluginStore.set(PLUGIN_NAME, "decoration_badge_#{badge_id}", badge_data.to_json)
        
        render json: {
          success: true,
          badge: badge_data,
          message: "勋章上传成功"
        }
      rescue => e
        Rails.logger.error "[装饰系统] 上传勋章失败: #{e.message}"
        render json: { error: "上传失败：#{e.message}" }, status: 500
      end
    end

    # 更新头像框参数
    def update_frame_params
      frame_id = params[:frame_id].to_i
      frame_key = "decoration_avatar_frame_#{frame_id}"
      frame_row = PluginStoreRow.find_by(plugin_name: PLUGIN_NAME, key: frame_key)
      
      unless frame_row
        return render json: { error: "头像框不存在" }, status: 404
      end
      
      begin
        frame_data = JSON.parse(frame_row.value)
        
        frame_data["width"] = params[:width].to_i if params[:width].present?
        frame_data["height"] = params[:height].to_i if params[:height].present?
        frame_data["top"] = params[:top].to_i if params[:top].present?
        frame_data["left"] = params[:left].to_i if params[:left].present?
        
        PluginStore.set(PLUGIN_NAME, frame_key, frame_data.to_json)
        
        render json: {
          success: true,
          frame: frame_data,
          message: "参数更新成功"
        }
      rescue => e
        render json: { error: "更新失败：#{e.message}" }, status: 500
      end
    end

    # 更新勋章参数
    def update_badge_params
      badge_id = params[:badge_id].to_i
      badge_key = "decoration_badge_#{badge_id}"
      badge_row = PluginStoreRow.find_by(plugin_name: PLUGIN_NAME, key: badge_key)
      
      unless badge_row
        return render json: { error: "勋章不存在" }, status: 404
      end
      
      begin
        badge_data = JSON.parse(badge_row.value)
        
        if badge_data["type"] == "image"
          badge_data["height"] = params[:height].to_i if params[:height].present?
        end
        
        PluginStore.set(PLUGIN_NAME, badge_key, badge_data.to_json)
        
        render json: {
          success: true,
          badge: badge_data,
          message: "参数更新成功"
        }
      rescue => e
        render json: { error: "更新失败：#{e.message}" }, status: 500
      end
    end

    # 删除头像框
    def delete_frame
      frame_id = params[:frame_id].to_i
      frame_key = "decoration_avatar_frame_#{frame_id}"
      frame_row = PluginStoreRow.find_by(plugin_name: PLUGIN_NAME, key: frame_key)
      
      unless frame_row
        return render json: { error: "头像框不存在" }, status: 404
      end
      
      begin
        # 获取头像框数据以删除文件
        frame_data = JSON.parse(frame_row.value)
        
        # 删除图片文件
        if frame_data["image"].present?
          file_path = File.join(Rails.root, "public", frame_data["image"])
          if File.exist?(file_path)
            File.delete(file_path)
            Rails.logger.info "[装饰系统] 删除头像框文件: #{file_path}"
          end
        end
        
        # 删除数据库记录
        PluginStore.remove(PLUGIN_NAME, frame_key)
        
        # 撤销所有授予记录
        DecorationGrant.where(decoration_type: 'avatar_frame', decoration_id: frame_id).update_all(revoked: true, revoked_at: Time.current, revoked_by_user_id: current_user.id)
        
        render json: {
          success: true,
          message: "头像框已删除"
        }
      rescue => e
        Rails.logger.error "[装饰系统] 删除头像框失败: #{e.message}"
        render json: { error: "删除失败：#{e.message}" }, status: 500
      end
    end

    # 删除勋章
    def delete_badge
      badge_id = params[:badge_id].to_i
      badge_key = "decoration_badge_#{badge_id}"
      badge_row = PluginStoreRow.find_by(plugin_name: PLUGIN_NAME, key: badge_key)
      
      unless badge_row
        return render json: { error: "勋章不存在" }, status: 404
      end
      
      begin
        badge_data = JSON.parse(badge_row.value)
        
        # 删除图片文件（如果是图片勋章）
        if badge_data["type"] == "image" && badge_data["image"].present?
          file_path = File.join(Rails.root, "public", badge_data["image"])
          if File.exist?(file_path)
            File.delete(file_path)
            Rails.logger.info "[装饰系统] 删除勋章文件: #{file_path}"
          end
        end
        
        # 删除数据库记录
        PluginStore.remove(PLUGIN_NAME, badge_key)
        
        # 撤销所有授予记录
        DecorationGrant.where(decoration_type: 'badge', decoration_id: badge_id).update_all(revoked: true, revoked_at: Time.current, revoked_by_user_id: current_user.id)
        
        render json: {
          success: true,
          message: "勋章已删除"
        }
      rescue => e
        Rails.logger.error "[装饰系统] 删除勋章失败: #{e.message}"
        render json: { error: "删除失败：#{e.message}" }, status: 500
      end
    end

    # 给予装饰（管理员）
    def grant_decoration
      user_id = params[:user_id].to_i
      decoration_type = params[:decoration_type] # 'avatar_frame' or 'badge'
      decoration_id = params[:decoration_id].to_i
      expires_in_days = params[:expires_in_days].to_i # 0 = 永久
      reason = params[:reason]
      
      target_user = User.find_by(id: user_id)
      unless target_user
        return render json: { error: "用户不存在" }, status: 404
      end
      
      unless ['avatar_frame', 'badge'].include?(decoration_type)
        return render json: { error: "装饰类型无效" }, status: 400
      end
      
      begin
        # 检查是否已有未过期的授予
        existing_grant = DecorationGrant.active
          .where(user_id: user_id, decoration_type: decoration_type, decoration_id: decoration_id)
          .first
        
        if existing_grant
          return render json: { error: "该用户已拥有此装饰" }, status: 400
        end
        
        expires_at = expires_in_days > 0 ? expires_in_days.days.from_now : nil
        
        grant = DecorationGrant.create!(
          user_id: user_id,
          decoration_type: decoration_type,
          decoration_id: decoration_id,
          granted_by: Discourse.system_user,
          granted_at: Time.current,
          expires_at: expires_at,
          grant_reason: reason
        )
        
        render json: {
          success: true,
          grant: grant_to_json(grant),
          message: "装饰授予成功"
        }
      rescue => e
        Rails.logger.error "[装饰系统] 授予装饰失败: #{e.message}"
        render json: { error: "授予失败：#{e.message}" }, status: 500
      end
    end

    # 撤销授予
    def revoke_grant
      grant_id = params[:grant_id].to_i
      reason = params[:reason]
      
      grant = DecorationGrant.find_by(id: grant_id)
      unless grant
        return render json: { error: "授予记录不存在" }, status: 404
      end
      
      if grant.revoked
        return render json: { error: "该授予已被撤销" }, status: 400
      end
      
      begin
        grant.update!(
          revoked: true,
          revoked_at: Time.current,
          revoked_by_user_id: current_user.id,
          revoke_reason: reason
        )
        
        # 如果用户正在佩戴被撤销的装饰，自动取消装备
        user = grant.user
        if user
          case grant.decoration_type
          when "avatar_frame"
            equipped_frame_id = user.custom_fields["avatar_frame_id"]
            if equipped_frame_id.to_i == grant.decoration_id
              user.custom_fields["avatar_frame_id"] = nil
              user.save_custom_fields(true)
              Rails.logger.info "[装饰系统] 撤销装饰：自动取消用户 #{user.username} 的头像框装备"
            end
          when "badge"
            equipped_badge_id = user.custom_fields["decoration_badge_id"]
            if equipped_badge_id.to_i == grant.decoration_id
              user.custom_fields["decoration_badge_id"] = nil
              user.save_custom_fields(true)
              Rails.logger.info "[装饰系统] 撤销装饰：自动取消用户 #{user.username} 的勋章装备"
            end
          end
        end
        
        render json: {
          success: true,
          grant: grant_to_json(grant),
          message: "授予已撤销"
        }
      rescue => e
        render json: { error: "撤销失败：#{e.message}" }, status: 500
      end
    end

    # 获取授予列表
    def grants
      decoration_type = params[:decoration_type] # nil = 全部
      status = params[:status] # 'active', 'expired', 'revoked', 'all'
      
      grants_query = DecorationGrant.includes(:user, :granted_by)
      
      grants_query = grants_query.where(decoration_type: decoration_type) if decoration_type.present?
      
      case status
      when 'active'
        grants_query = grants_query.active
      when 'expired'
        grants_query = grants_query.expired
      when 'revoked'
        grants_query = grants_query.revoked
      end
      
      grants = grants_query.order(granted_at: :desc).limit(100).map { |g| grant_to_json(g) }
      
      render json: { grants: grants }
    end
    
    # 删除所有已撤销的记录
    def delete_revoked_grants
      ensure_admin
      
      begin
        deleted_count = DecorationGrant.where(revoked: true).delete_all
        
        render json: {
          success: true,
          deleted_count: deleted_count,
          message: "已删除 #{deleted_count} 条撤销记录"
        }
      rescue => e
        Rails.logger.error "[装饰系统] 删除撤销记录失败: #{e.message}"
        render json: { error: "删除失败：#{e.message}" }, status: 500
      end
    end

    # 个人装饰页面主页
    def index
      unless current_user
        return render json: { error: "请先登录" }, status: 401
      end
      
      # 获取用户拥有的装饰授予记录
      owned_frames = DecorationGrant.active
        .avatar_frames
        .for_user(current_user.id)
        .includes(:granted_by)
        .map { |g| 
          frame_data = get_frame_by_id(g.decoration_id)
          
          if frame_data.nil?
            Rails.logger.warn "[装饰系统] 无法获取头像框数据 ID: #{g.decoration_id}"
            next
          end
          
          Rails.logger.debug "[装饰系统] 头像框数据: #{frame_data.inspect}"
          
          frame_data.merge({
            grant_id: g.id,
            granted_at: g.granted_at,
            granted_by: g.granted_by.username,
            expires_at: g.expires_at,
            permanent: g.permanent?,
            time_remaining: g.time_remaining
          })
        }.compact
      
      owned_badges = DecorationGrant.active
        .badges
        .for_user(current_user.id)
        .includes(:granted_by)
        .map { |g|
          badge_data = get_badge_by_id(g.decoration_id)
          next unless badge_data
          badge_data["name"] ||= "勋章 ##{badge_data['id']}"
          
          badge_data.merge({
            grant_id: g.id,
            granted_at: g.granted_at,
            granted_by: g.granted_by.username,
            expires_at: g.expires_at,
            permanent: g.permanent?,
            time_remaining: g.time_remaining
          })
        }.compact
      
      # 获取当前装备
      equipped_frame_id = current_user.custom_fields["avatar_frame_id"]
      equipped_badge_id = current_user.custom_fields["decoration_badge_id"]
      
      Rails.logger.info "[装饰系统] 用户 #{current_user.username} 装备检查："
      Rails.logger.info "  - equipped_frame_id: #{equipped_frame_id}"
      Rails.logger.info "  - equipped_badge_id: #{equipped_badge_id}"
      Rails.logger.info "  - owned_frames 数量: #{owned_frames.count}"
      Rails.logger.info "  - owned_badges 数量: #{owned_badges.count}"
      
      # 检查装备的有效性：如果装备的装饰不在拥有列表中，自动取消装备
      # 只有当装备了装饰时才检查，避免误清除
      if equipped_frame_id.present?
        # 获取拥有的头像框ID列表，同时支持符号键和字符串键
        owned_frame_ids = owned_frames.map { |f| (f[:id] || f["id"]).to_i }
        Rails.logger.info "  - owned_frame_ids: #{owned_frame_ids.inspect}"
        Rails.logger.info "  - 检查 #{equipped_frame_id.to_i} 是否在列表中"
        
        if !owned_frame_ids.include?(equipped_frame_id.to_i)
          Rails.logger.warn "[装饰系统] 用户 #{current_user.username} 装备的头像框 ##{equipped_frame_id} 已失效，自动取消装备"
          current_user.custom_fields["avatar_frame_id"] = nil
          current_user.save_custom_fields(true)
          equipped_frame_id = nil
        else
          Rails.logger.info "[装饰系统] 头像框 ##{equipped_frame_id} 有效"
        end
      end
      
      if equipped_badge_id.present?
        # 获取拥有的勋章ID列表，同时支持符号键和字符串键
        owned_badge_ids = owned_badges.map { |b| (b[:id] || b["id"]).to_i }
        Rails.logger.info "  - owned_badge_ids: #{owned_badge_ids.inspect}"
        Rails.logger.info "  - 检查 #{equipped_badge_id.to_i} 是否在列表中"
        
        if !owned_badge_ids.include?(equipped_badge_id.to_i)
          Rails.logger.warn "[装饰系统] 用户 #{current_user.username} 装备的勋章 ##{equipped_badge_id} 已失效，自动取消装备"
          current_user.custom_fields["decoration_badge_id"] = nil
          current_user.save_custom_fields(true)
          equipped_badge_id = nil
        else
          Rails.logger.info "[装饰系统] 勋章 ##{equipped_badge_id} 有效"
        end
      end
      
      render json: {
        owned_frames: owned_frames,
        owned_badges: owned_badges,
        equipped_frame_id: equipped_frame_id,
        equipped_badge_id: equipped_badge_id,
        username: current_user.username
      }
    end

    # 装备头像框
    def equip_frame
      unless current_user
        Rails.logger.warn "[装饰系统] 未登录用户尝试装备头像框"
        return render json: { error: "请先登录" }, status: 401
      end
      
      frame_id = params[:frame_id].to_i
      Rails.logger.info "[装饰系统] 用户 #{current_user.username} 尝试装备头像框 ID: #{frame_id}"
      
      # 如果是0，表示取消装备
      if frame_id == 0
        current_user.custom_fields["avatar_frame_id"] = nil
        current_user.save_custom_fields(true)
        Rails.logger.info "[装饰系统] 用户 #{current_user.username} 取消装备头像框"
        return render json: { success: true, message: "已取消装备头像框" }
      end
      
      # 检查用户是否拥有此头像框
      grant = DecorationGrant.active
        .avatar_frames
        .for_user(current_user.id)
        .find_by(decoration_id: frame_id)
      
      Rails.logger.info "[装饰系统] 用户 #{current_user.username} 的头像框授予记录: #{grant.inspect}"
      
      unless grant
        Rails.logger.warn "[装饰系统] 用户 #{current_user.username} 没有头像框 ##{frame_id}"
        return render json: { error: "您没有此头像框" }, status: 403
      end
      
      # 装备头像框
      current_user.custom_fields["avatar_frame_id"] = frame_id
      current_user.save_custom_fields(true)
      
      Rails.logger.info "[装饰系统] 用户 #{current_user.username} 成功装备头像框 ##{frame_id}"
      
      render json: {
        success: true,
        message: "头像框装备成功",
        frame_id: frame_id
      }
    end

    # 装备勋章
    def equip_badge
      unless current_user
        return render json: { error: "请先登录" }, status: 401
      end
      
      badge_id = params[:badge_id].to_i
      
      # 如果是0，表示取消装备
      if badge_id == 0
        current_user.custom_fields["decoration_badge_id"] = nil
        current_user.save_custom_fields(true)
        return render json: { success: true, message: "已取消装备勋章" }
      end
      
      # 检查用户是否拥有此勋章
      grant = DecorationGrant.active
        .badges
        .for_user(current_user.id)
        .find_by(decoration_id: badge_id)
      
      unless grant
        return render json: { error: "您没有此勋章" }, status: 403
      end
      
      # 装备勋章
      current_user.custom_fields["decoration_badge_id"] = badge_id
      current_user.save_custom_fields(true)
      
      render json: {
        success: true,
        message: "勋章装备成功",
        badge_id: badge_id
      }
    end

    # 批量查询用户装饰（优化高并发）
    def batch_user_decorations
      usernames = params[:usernames]
      
      unless usernames.is_a?(Array) && usernames.length > 0
        return render json: { error: "参数错误" }, status: 400
      end
      
      # 限制单次查询数量
      usernames = usernames.first(50)
      
      # 查询所有用户并预加载 custom_fields
      users = User.where(username: usernames)
        .includes(:user_custom_fields)
        .select(:id, :username, :updated_at)
      
      result = {}
      users.each do |user|
        # 使用 custom_fields 获取装备数据
        frame_id = user.custom_fields["avatar_frame_id"]&.to_i
        badge_id = user.custom_fields["decoration_badge_id"]&.to_i
        
        result[user.username] = {
          avatar_frame_id: frame_id || nil,
          decoration_badge_id: badge_id || nil,
          updated_at: user.updated_at
        }
      end
      
      render json: { users: result }
    rescue => e
      Rails.logger.error "[装饰系统] 批量查询失败: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { error: "服务器错误", message: e.message }, status: 500
    end

    # 用户查看自己的装饰（简化版，用于API）
    def my_decorations
      frames = DecorationGrant.active
        .avatar_frames
        .for_user(current_user.id)
        .map { |g| { id: g.decoration_id, granted_at: g.granted_at, expires_at: g.expires_at } }
      
      badges = DecorationGrant.active
        .badges
        .for_user(current_user.id)
        .map { |g| { id: g.decoration_id, granted_at: g.granted_at, expires_at: g.expires_at } }
      
      render json: {
        avatar_frames: frames,
        badges: badges
      }
    end

    private

    def ensure_logged_in
      raise Discourse::InvalidAccess unless current_user
    end

    def ensure_admin
      raise Discourse::InvalidAccess unless current_user&.admin?
    end

    def get_all_frames
      PluginStoreRow.where(plugin_name: PLUGIN_NAME)
        .where("key LIKE ?", "decoration_avatar_frame_%")
        .map { |row| JSON.parse(row.value) }
        .sort_by { |f| f["id"] }
    end

    def get_all_badges
      PluginStoreRow.where(plugin_name: PLUGIN_NAME)
        .where("key LIKE ?", "decoration_badge_%")
        .map do |row|
          data = JSON.parse(row.value)
          data["name"] ||= "勋章 ##{data['id']}"
          data
        end
        .sort_by { |b| b["id"] }
    end

    def get_grants_summary
      {
        total_grants: DecorationGrant.count,
        active_grants: DecorationGrant.active.count,
        expired_grants: DecorationGrant.expired.count,
        revoked_grants: DecorationGrant.revoked.count,
        total_users: DecorationGrant.select(:user_id).distinct.count
      }
    end

    def grant_to_json(grant)
      {
        id: grant.id,
        user_id: grant.user_id,
        username: grant.user.username,
        decoration_type: grant.decoration_type,
        decoration_id: grant.decoration_id,
        granted_by_user_id: grant.granted_by_user_id,
        granted_by_username: grant.granted_by.username,
        granted_at: grant.granted_at,
        expires_at: grant.expires_at,
        permanent: grant.permanent?,
        revoked: grant.revoked,
        revoked_at: grant.revoked_at,
        revoked_by_username: grant.revoked_by&.username,
        grant_reason: grant.grant_reason,
        revoke_reason: grant.revoke_reason,
        active: grant.active?,
        expired: grant.expired?,
        time_remaining: grant.time_remaining
      }
    end

    def get_frame_by_id(frame_id)
      frame_row = PluginStoreRow.find_by(plugin_name: PLUGIN_NAME, key: "decoration_avatar_frame_#{frame_id}")
      return nil unless frame_row
      
      begin
        JSON.parse(frame_row.value)
      rescue
        nil
      end
    end

    def get_badge_by_id(badge_id)
      badge_row = PluginStoreRow.find_by(plugin_name: PLUGIN_NAME, key: "decoration_badge_#{badge_id}")
      return nil unless badge_row
      
      begin
        JSON.parse(badge_row.value)
      rescue
        nil
      end
    end
  end
end
