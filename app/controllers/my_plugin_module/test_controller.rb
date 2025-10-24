# frozen_string_literal: true

module ::MyPluginModule
  class TestController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    before_action :ensure_logged_in
    
    # 测试页面
    def index
      render "default/empty"
    end

    # 获取所有头像框
    def frames
      frames = PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                             .where("key LIKE ?", "test_avatar_frame_%")
                             .map { |row| JSON.parse(row.value) }
      
      render json: {
        frames: frames,
        equipped_frame_id: current_user.custom_fields["avatar_frame_id"]
      }
    end

    # 获取所有装饰勋章
    def badges
      badges = PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                             .where("key LIKE ?", "test_decoration_badge_%")
                             .map { |row| JSON.parse(row.value) }
      
      render json: {
        badges: badges,
        equipped_badge_id: current_user.custom_fields["equipped_decoration_badge"]
      }
    end

    # 上传头像框（管理员）
    def upload_frame
      return render json: { error: "无权限" }, status: 403 unless current_user.admin?
      
      file = params[:file]
      name = params[:name] || file.original_filename.split('.').first
      
      unless file.present?
        return render json: { error: "文件不能为空" }, status: 400
      end
      
      # 验证文件类型
      unless ["image/png", "image/jpeg", "image/jpg"].include?(file.content_type)
        return render json: { error: "只支持 PNG/JPG 格式" }, status: 400
      end
      
      begin
        # 创建上传目录
        upload_dir = File.join(Rails.root, "public", "uploads", "default", "avatar-frames")
        FileUtils.mkdir_p(upload_dir)
        
        # 生成唯一文件名
        ext = file.original_filename.split('.').last
        filename = "frame_#{Time.now.to_i}_#{SecureRandom.hex(4)}.#{ext}"
        file_path = File.join(upload_dir, filename)
        
        # 保存文件
        File.open(file_path, "wb") do |f|
          file.rewind
          f.write(file.read)
        end
        
        Rails.logger.info "[测试装饰系统] 头像框已保存: #{file_path}"
        
        # 生成URL
        image_url = "/uploads/default/avatar-frames/#{filename}"
        
        # 获取下一个ID
        frame_id = (PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                                  .where("key LIKE ?", "test_avatar_frame_%")
                                  .count + 1)
        
        # 保存到数据库
        frame_data = {
          id: frame_id,
          name: name,
          image: image_url,
          uploaded_at: Time.current.iso8601,
          uploaded_by: current_user.username
        }
        
        PluginStore.set(PLUGIN_NAME, "test_avatar_frame_#{frame_id}", frame_data.to_json)
        
        render json: {
          success: true,
          frame: frame_data,
          message: "头像框上传成功"
        }
      rescue => e
        Rails.logger.error "[测试装饰系统] 上传头像框失败: #{e.message}"
        render json: { error: "上传失败：#{e.message}" }, status: 500
      end
    end

    # 上传装饰勋章（管理员）
    def upload_badge
      return render json: { error: "无权限" }, status: 403 unless current_user.admin?
      
      name = params[:name]
      badge_type = params[:type] # "text" or "image"
      
      unless name.present? && badge_type.present?
        return render json: { error: "参数不完整" }, status: 400
      end
      
      begin
        # 获取下一个ID
        badge_id = (PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                                  .where("key LIKE ?", "test_decoration_badge_%")
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
          unless ["image/png", "image/jpeg", "image/jpg"].include?(file.content_type)
            return render json: { error: "只支持 PNG/JPG 格式" }, status: 400
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
          
          Rails.logger.info "[测试装饰系统] 勋章已保存: #{file_path}"
          
          # 生成URL
          image_url = "/uploads/default/decoration-badges/#{filename}"
          
          badge_data = {
            id: badge_id,
            name: name,
            type: "image",
            image: image_url,
            uploaded_at: Time.current.iso8601,
            uploaded_by: current_user.username
          }
        end
        
        # 保存到数据库
        PluginStore.set(PLUGIN_NAME, "test_decoration_badge_#{badge_id}", badge_data.to_json)
        
        render json: {
          success: true,
          badge: badge_data,
          message: "勋章上传成功"
        }
      rescue => e
        Rails.logger.error "[测试装饰系统] 上传勋章失败: #{e.message}"
        render json: { error: "上传失败：#{e.message}" }, status: 500
      end
    end

    # 装备头像框
    def equip_frame
      frame_id = params[:frame_id].to_i
      
      # 验证头像框存在
      frame_key = "test_avatar_frame_#{frame_id}"
      frame_row = PluginStoreRow.find_by(plugin_name: PLUGIN_NAME, key: frame_key)
      
      unless frame_row
        return render json: { error: "头像框不存在" }, status: 404
      end
      
      # 装备头像框
      current_user.custom_fields["avatar_frame_id"] = frame_id
      current_user.save_custom_fields(true)
      
      Rails.logger.info "[测试装饰系统] 用户 #{current_user.username} 装备了头像框 ##{frame_id}"
      
      render json: {
        success: true,
        frame_id: frame_id,
        message: "头像框已装备"
      }
    end

    # 装备勋章
    def equip_badge
      badge_id = params[:badge_id].to_i
      
      # 验证勋章存在
      badge_key = "test_decoration_badge_#{badge_id}"
      badge_row = PluginStoreRow.find_by(plugin_name: PLUGIN_NAME, key: badge_key)
      
      unless badge_row
        return render json: { error: "勋章不存在" }, status: 404
      end
      
      # 装备勋章
      current_user.custom_fields["equipped_decoration_badge"] = badge_id
      current_user.save_custom_fields(true)
      
      Rails.logger.info "[测试装饰系统] 用户 #{current_user.username} 装备了勋章 ##{badge_id}"
      
      render json: {
        success: true,
        badge_id: badge_id,
        message: "勋章已装备"
      }
    end
  end
end
