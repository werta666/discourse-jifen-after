# frozen_string_literal: true

module UserCardSerializerExtension
  def self.prepended(base)
    base.attributes :avatar_frame_id, :equipped_decoration_badge
  end

  def avatar_frame_id
    object.custom_fields["avatar_frame_id"]
  end

  def equipped_decoration_badge
    object.custom_fields["equipped_decoration_badge"]
  end
end

# 扩展 UserCardSerializer
::UserCardSerializer.prepend(UserCardSerializerExtension)

# 也扩展 UserSerializer，确保在用户信息中包含这些字段
::UserSerializer.prepend(UserCardSerializerExtension)
