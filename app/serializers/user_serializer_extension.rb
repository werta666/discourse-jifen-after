# frozen_string_literal: true

module UserSerializerExtension
  def self.prepended(base)
    # 添加自定义字段到序列化器
    base.attributes :avatar_frame_id, :equipped_decoration_badge
  end

  def avatar_frame_id
    object.custom_fields["avatar_frame_id"]
  end

  def equipped_decoration_badge
    object.custom_fields["equipped_decoration_badge"]
  end
end

# 同时扩展 UserCardSerializer 和 UserSerializer
::UserCardSerializer.prepend(UserSerializerExtension)
::UserSerializer.prepend(UserSerializerExtension)
