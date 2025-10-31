class CreateCreatorApplications < ActiveRecord::Migration[7.0]
  def change
    create_table :qd_creator_applications do |t|
      t.integer :user_id, null: false           # 申请人ID
      t.text :creative_field                    # 创作领域
      t.text :creative_experience               # 创作经历
      t.string :portfolio_images, array: true, default: [] # 代表作/证明图片数组
      t.string :status, default: 'pending'      # 状态: pending/approved/rejected
      t.datetime :submitted_at                  # 提交时间
      t.datetime :reviewed_at                   # 审核时间
      t.integer :reviewed_by                    # 审核人ID
      t.text :rejection_reason                  # 拒绝原因
      t.boolean :fee_refunded, default: false   # 是否已退还费用
      t.integer :application_fee, default: 0    # 申请费用（记录实际花费）
      t.timestamps
    end

    add_index :qd_creator_applications, :user_id
    add_index :qd_creator_applications, :status
    add_index :qd_creator_applications, :submitted_at
    add_index :qd_creator_applications, :created_at
  end
end
