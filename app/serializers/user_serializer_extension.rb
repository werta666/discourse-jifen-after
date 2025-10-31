# frozen_string_literal: true

module UserSerializerExtension
  def self.prepended(base)
    # 添加装饰系统字段到序列化器
    base.attributes :avatar_frame_id, :decoration_badge_id, :custom_fields
  end

  def avatar_frame_id
    object.custom_fields["avatar_frame_id"]
  end

  def decoration_badge_id
    object.custom_fields["decoration_badge_id"]
  end
  
  def custom_fields
    {
      "avatar_frame_id" => object.custom_fields["avatar_frame_id"],
      "decoration_badge_id" => object.custom_fields["decoration_badge_id"]
    }
  end
end

# 同时扩展 UserCardSerializer 和 UserSerializer
::UserCardSerializer.prepend(UserSerializerExtension)
::UserSerializer.prepend(UserSerializerExtension)
