# frozen_string_literal: true

class CreateDecorationGrants < ActiveRecord::Migration[7.0]
  def change
    create_table :qd_decoration_grants do |t|
      t.integer :user_id, null: false
      t.string :decoration_type, null: false # 'avatar_frame' or 'badge'
      t.integer :decoration_id, null: false
      t.integer :granted_by_user_id, null: false
      t.datetime :granted_at, null: false
      t.datetime :expires_at # null = 永久
      t.boolean :revoked, default: false
      t.datetime :revoked_at
      t.integer :revoked_by_user_id
      t.text :grant_reason
      t.text :revoke_reason
      
      t.timestamps
    end

    add_index :qd_decoration_grants, :user_id
    add_index :qd_decoration_grants, [:user_id, :decoration_type, :decoration_id], name: 'index_qd_grants_on_user_decoration'
    add_index :qd_decoration_grants, :granted_by_user_id
    add_index :qd_decoration_grants, :expires_at
  end
end
