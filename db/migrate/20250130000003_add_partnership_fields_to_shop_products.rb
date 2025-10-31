# frozen_string_literal: true

class AddPartnershipFieldsToShopProducts < ActiveRecord::Migration[7.0]
  def up
    # 是否为合作商品
    unless column_exists?(:qd_shop_products, :is_partnership)
      add_column :qd_shop_products, :is_partnership, :boolean, default: false
    end

    # 合作用户名
    unless column_exists?(:qd_shop_products, :partner_username)
      add_column :qd_shop_products, :partner_username, :string
    end

    # 商品分类：decoration（装饰品）/ virtual（虚拟物品）
    unless column_exists?(:qd_shop_products, :partnership_category)
      add_column :qd_shop_products, :partnership_category, :string, limit: 20
    end

    # 关联帖子 URL
    unless column_exists?(:qd_shop_products, :related_post_url)
      add_column :qd_shop_products, :related_post_url, :string
    end

    # 装饰品类型：头像框 ID
    unless column_exists?(:qd_shop_products, :decoration_frame_id)
      add_column :qd_shop_products, :decoration_frame_id, :integer
    end

    # 装饰品类型：勋章 ID
    unless column_exists?(:qd_shop_products, :decoration_badge_id)
      add_column :qd_shop_products, :decoration_badge_id, :integer
    end

    # 虚拟物品：邮箱变量模板
    unless column_exists?(:qd_shop_products, :virtual_email_template)
      add_column :qd_shop_products, :virtual_email_template, :text
    end

    # 虚拟物品：地址 URL 变量模板
    unless column_exists?(:qd_shop_products, :virtual_address_template)
      add_column :qd_shop_products, :virtual_address_template, :text
    end

    # 抽成比例（0-100，表示百分比）
    unless column_exists?(:qd_shop_products, :commission_rate)
      add_column :qd_shop_products, :commission_rate, :decimal, precision: 5, scale: 2, default: 0
    end

    # 添加索引
    unless index_exists?(:qd_shop_products, :is_partnership, name: "idx_shop_products_partnership")
      add_index :qd_shop_products, :is_partnership, name: "idx_shop_products_partnership"
    end

    unless index_exists?(:qd_shop_products, :partner_username, name: "idx_shop_products_partner_username")
      add_index :qd_shop_products, :partner_username, name: "idx_shop_products_partner_username"
    end
  end

  def down
    if column_exists?(:qd_shop_products, :is_partnership)
      remove_column :qd_shop_products, :is_partnership
    end

    if column_exists?(:qd_shop_products, :partner_username)
      remove_column :qd_shop_products, :partner_username
    end

    if column_exists?(:qd_shop_products, :partnership_category)
      remove_column :qd_shop_products, :partnership_category
    end

    if column_exists?(:qd_shop_products, :related_post_url)
      remove_column :qd_shop_products, :related_post_url
    end

    if column_exists?(:qd_shop_products, :decoration_frame_id)
      remove_column :qd_shop_products, :decoration_frame_id
    end

    if column_exists?(:qd_shop_products, :decoration_badge_id)
      remove_column :qd_shop_products, :decoration_badge_id
    end

    if column_exists?(:qd_shop_products, :virtual_email_template)
      remove_column :qd_shop_products, :virtual_email_template
    end

    if column_exists?(:qd_shop_products, :virtual_address_template)
      remove_column :qd_shop_products, :virtual_address_template
    end

    if column_exists?(:qd_shop_products, :commission_rate)
      remove_column :qd_shop_products, :commission_rate
    end
  end
end
