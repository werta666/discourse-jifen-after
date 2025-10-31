class CreateCreatorWorkLikes < ActiveRecord::Migration[7.0]
  def change
    create_table :qd_creator_work_likes do |t|
      t.integer :work_id, null: false    # 作品ID
      t.integer :user_id, null: false    # 点赞用户ID
      t.timestamps
    end

    add_index :qd_creator_work_likes, [:work_id, :user_id], unique: true
    add_index :qd_creator_work_likes, :work_id
    add_index :qd_creator_work_likes, :user_id
  end
end
