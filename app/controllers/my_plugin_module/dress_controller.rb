# frozen_string_literal: true

module ::MyPluginModule
  class DressController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    before_action :ensure_logged_in
    
    # 装饰主页面
    def index
      render :layout => false
    end

    # 获取所有头像框
    def frames
      # 从数据库获取所有头像框
      frames = PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                             .where("key LIKE ?", "avatar_frame_%")
                             .map { |row| JSON.parse(row.value) }

      # 获取用户拥有的头像框
      owned_frames = current_user.custom_fields["owned_avatar_frames"] || [1]
      owned_frames = owned_frames.is_a?(String) ? JSON.parse(owned_frames) : owned_frames

      render json: {
        frames: frames,
        owned_frames: owned_frames,
        equipped_frame_id: current_user.custom_fields["avatar_frame_id"]
      }
    end

    # 装备头像框
    def equip_frame
      frame_id = params[:frame_id].to_i
      
      # 检查用户是否拥有这个头像框
      owned_frames = current_user.custom_fields["owned_avatar_frames"] || [1]
      owned_frames = owned_frames.is_a?(String) ? JSON.parse(owned_frames) : owned_frames
      
      unless owned_frames.include?(frame_id)
        return render json: { error: "你还没有拥有这个头像框" }, status: 403
      end

      # 装备头像框
      current_user.custom_fields["avatar_frame_id"] = frame_id
      current_user.save_custom_fields(true)

      render json: { success: true, frame_id: frame_id }
    end

    # 购买头像框
    def purchase_frame
      frame_id = params[:frame_id].to_i
      currency = params[:currency] # "points" or "paid_coins"
      price = params[:price].to_i

      # 获取头像框信息
      frame_key = "avatar_frame_#{frame_id}"
      frame_row = PluginStoreRow.find_by(plugin_name: PLUGIN_NAME, key: frame_key)
      
      unless frame_row
        return render json: { error: "头像框不存在" }, status: 404
      end

      # 检查用户余额
      if currency == "points"
        user_balance = (current_user.custom_fields["points"] || 0).to_i
        if user_balance < price
          return render json: { error: "积分不足" }, status: 402
        end
      else
        user_balance = (current_user.custom_fields["paid_coins"] || 0).to_i
        if user_balance < price
          return render json: { error: "付费币不足" }, status: 402
        end
      end

      # 检查是否已经拥有
      owned_frames = current_user.custom_fields["owned_avatar_frames"] || [1]
      owned_frames = owned_frames.is_a?(String) ? JSON.parse(owned_frames) : owned_frames
      
      if owned_frames.include?(frame_id)
        return render json: { error: "你已经拥有这个头像框" }, status: 400
      end

      # 扣除货币
      if currency == "points"
        new_balance = user_balance - price
        current_user.custom_fields["points"] = new_balance
      else
        new_balance = user_balance - price
        current_user.custom_fields["paid_coins"] = new_balance
      end

      # 添加到拥有列表
      owned_frames << frame_id
      current_user.custom_fields["owned_avatar_frames"] = owned_frames.to_json
      current_user.save_custom_fields(true)

      render json: { 
        success: true, 
        new_balance: new_balance,
        owned_frames: owned_frames
      }
    end

    # 上传头像框（管理员）
    def upload_frame
      return render json: { error: "无权限" }, status: 403 unless current_user.admin?

      filename = params[:filename]
      file = params[:file]
      price = params[:price].to_i
      currency = params[:currency]

      unless filename.present? && file.present?
        return render json: { error: "文件名和文件不能为空" }, status: 400
      end

      # 验证文件类型
      unless file.content_type == "image/png"
        return render json: { error: "只支持 PNG 格式" }, status: 400
      end

      begin
        # 确保创建目标目录
        upload_dir = File.join(Rails.root, "public", "uploads", "default", "jifen")
        FileUtils.mkdir_p(upload_dir)
        
        Rails.logger.info "[装饰系统] 上传目录: #{upload_dir}"

        # 保存文件
        file_path = File.join(upload_dir, "#{filename}.png")
        File.open(file_path, "wb") do |f|
          file.rewind
          f.write(file.read)
        end
        
        Rails.logger.info "[装饰系统] 文件已保存: #{file_path}"

        # 生成URL
        image_url = "/uploads/default/jifen/#{filename}.png"

        # 保存到数据库
        frame_id = (PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                                  .where("key LIKE ?", "avatar_frame_%")
                                  .count + 1)

        frame_data = {
          id: frame_id,
          name: filename,
          image: image_url,
          price: price,
          currency: currency
        }

        PluginStore.set(PLUGIN_NAME, "avatar_frame_#{frame_id}", frame_data.to_json)

        render json: { 
          success: true, 
          frame: frame_data,
          message: "上传成功"
        }
      rescue => e
        Rails.logger.error "[装饰系统] 上传头像框失败: #{e.message}"
        render json: { error: "上传失败：#{e.message}" }, status: 500
      end
    end

    # 删除头像框（管理员）
    def delete_frame
      return render json: { error: "无权限" }, status: 403 unless current_user.admin?

      frame_id = params[:id].to_i
      frame_key = "avatar_frame_#{frame_id}"

      PluginStore.remove(PLUGIN_NAME, frame_key)

      render json: { success: true, message: "删除成功" }
    end

    # 我的头像框
    def my_frames
      owned_frames = current_user.custom_fields["owned_avatar_frames"] || [1]
      owned_frames = owned_frames.is_a?(String) ? JSON.parse(owned_frames) : owned_frames

      # 获取完整的头像框信息
      frames = PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                             .where("key LIKE ?", "avatar_frame_%")
                             .map { |row| JSON.parse(row.value) }
                             .select { |frame| owned_frames.include?(frame["id"]) }

      render json: { frames: frames }
    end

    # 我的装饰
    def my_decorations
      # 暂时返回空数组，后续可以扩展
      render json: { decorations: [] }
    end

    # ========================================
    # 装饰勋章相关方法
    # ========================================

    # 获取所有装饰勋章
    def decoration_badges
      # 从数据库获取所有装饰勋章
      badges = PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                              .where("key LIKE ?", "decoration_badge_%")
                              .map { |row| JSON.parse(row.value) }

      # 获取用户拥有的勋章
      owned_badges = current_user.custom_fields["owned_decoration_badges"] || []
      owned_badges = owned_badges.is_a?(String) ? JSON.parse(owned_badges) : owned_badges

      render json: {
        badges: badges,
        owned_badges: owned_badges,
        equipped_badge_id: current_user.custom_fields["equipped_decoration_badge"]
      }
    end

    # 装备勋章
    def equip_badge
      badge_id = params[:badge_id].to_i
      
      # 检查用户是否拥有这个勋章
      owned_badges = current_user.custom_fields["owned_decoration_badges"] || []
      owned_badges = owned_badges.is_a?(String) ? JSON.parse(owned_badges) : owned_badges
      
      unless owned_badges.include?(badge_id)
        return render json: { error: "你还没有拥有这个勋章" }, status: 403
      end

      # 装备勋章
      current_user.custom_fields["equipped_decoration_badge"] = badge_id
      current_user.save_custom_fields(true)

      render json: { success: true, badge_id: badge_id }
    end

    # 购买勋章
    def purchase_badge
      badge_id = params[:badge_id].to_i
      currency = params[:currency]
      price = params[:price].to_i

      # 获取勋章信息
      badge_key = "decoration_badge_#{badge_id}"
      badge_row = PluginStoreRow.find_by(plugin_name: PLUGIN_NAME, key: badge_key)
      
      unless badge_row
        return render json: { error: "勋章不存在" }, status: 404
      end

      # 检查用户余额
      if currency == "points"
        user_balance = (current_user.custom_fields["points"] || 0).to_i
        if user_balance < price
          return render json: { error: "积分不足" }, status: 402
        end
      else
        user_balance = (current_user.custom_fields["paid_coins"] || 0).to_i
        if user_balance < price
          return render json: { error: "付费币不足" }, status: 402
        end
      end

      # 检查是否已经拥有
      owned_badges = current_user.custom_fields["owned_decoration_badges"] || []
      owned_badges = owned_badges.is_a?(String) ? JSON.parse(owned_badges) : owned_badges
      
      if owned_badges.include?(badge_id)
        return render json: { error: "你已经拥有这个勋章" }, status: 400
      end

      # 扣除货币
      if currency == "points"
        new_balance = user_balance - price
        current_user.custom_fields["points"] = new_balance
      else
        new_balance = user_balance - price
        current_user.custom_fields["paid_coins"] = new_balance
      end

      # 添加到拥有列表
      owned_badges << badge_id
      current_user.custom_fields["owned_decoration_badges"] = owned_badges.to_json
      current_user.save_custom_fields(true)

      render json: { 
        success: true, 
        new_balance: new_balance,
        owned_badges: owned_badges
      }
    end

    # 上传勋章（管理员）
    def upload_badge
      return render json: { error: "无权限" }, status: 403 unless current_user.admin?

      name = params[:name]
      badge_type = params[:type] # "text" or "image"
      price = params[:price].to_i
      currency = params[:currency]

      unless name.present? && badge_type.present?
        return render json: { error: "参数不完整" }, status: 400
      end

      begin
        badge_id = (PluginStoreRow.where(plugin_name: PLUGIN_NAME)
                                   .where("key LIKE ?", "decoration_badge_%")
                                   .count + 1)

        if badge_type == "text"
          text = params[:text]
          style = params[:style]

          unless text.present?
            return render json: { error: "文字内容不能为空" }, status: 400
          end

          badge_data = {
            id: badge_id,
            name: name,
            type: "text",
            text: text,
            style: style || "",
            price: price,
            currency: currency
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

          # 确保创建目标目录
          upload_dir = File.join(Rails.root, "public", "uploads", "default", "jifen2")
          FileUtils.mkdir_p(upload_dir)
          
          Rails.logger.info "[装饰系统] 勋章上传目录: #{upload_dir}"

          # 保存文件
          filename = "badge_#{badge_id}_#{Time.now.to_i}.#{file.original_filename.split('.').last}"
          file_path = File.join(upload_dir, filename)
          File.open(file_path, "wb") do |f|
            file.rewind
            f.write(file.read)
          end
          
          Rails.logger.info "[装饰系统] 勋章文件已保存: #{file_path}"

          # 生成URL
          image_url = "/uploads/default/jifen2/#{filename}"

          badge_data = {
            id: badge_id,
            name: name,
            type: "image",
            image: image_url,
            price: price,
            currency: currency
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

    # 删除勋章（管理员）
    def delete_badge
      return render json: { error: "无权限" }, status: 403 unless current_user.admin?

      badge_id = params[:id].to_i
      badge_key = "decoration_badge_#{badge_id}"

      PluginStore.remove(PLUGIN_NAME, badge_key)

      render json: { success: true, message: "删除成功" }
    end
  end
end
