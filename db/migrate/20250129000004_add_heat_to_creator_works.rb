# frozen_string_literal: true

class AddHeatToCreatorWorks < ActiveRecord::Migration[7.0]
  def change
    add_column :qd_creator_works, :heat_score, :integer, default: 0, null: false
    add_index :qd_creator_works, :heat_score
  end
end
