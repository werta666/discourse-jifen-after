# frozen_string_literal: true

class ExtendBettingOptionLogoLength < ActiveRecord::Migration[6.0]
  def up
    if table_exists?(:jifen_betting_options)
      change_column :jifen_betting_options, :logo, :string, limit: 100
    end
  end

  def down
    if table_exists?(:jifen_betting_options)
      change_column :jifen_betting_options, :logo, :string, limit: 10
    end
  end
end
