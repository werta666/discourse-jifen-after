class CreateCreatorWorks < ActiveRecord::Migration[7.0]
  def change
    create_table :qd_creator_works do |t|
      t.integer :user_id, null: false           # 创作者ID
      t.string :title                           # 作品标题（可选）
      t.string :image_url, null: false          # 图片URL
      t.string :post_url, null: false           # 跳转帖子地址
      t.integer :likes_count, default: 0        # 点赞数
      t.integer :clicks_count, default: 0       # 点击数
      t.string :status, default: 'pending'      # 状态: pending/approved/rejected
      t.datetime :approved_at                   # 审核通过时间
      t.integer :approved_by                    # 审核人ID
      t.text :rejection_reason                  # 驳回原因
      t.boolean :is_shop_product, default: false # 是否已上架为商品
      t.datetime :shop_applied_at               # 申请上架时间
      t.string :shop_status, default: 'none'    # 上架状态: none/pending/approved/rejected
      t.timestamps
    end

    add_index :qd_creator_works, :user_id
    add_index :qd_creator_works, :status
    add_index :qd_creator_works, :created_at
    add_index :qd_creator_works, :likes_count
    add_index :qd_creator_works, :clicks_count
  end
end
