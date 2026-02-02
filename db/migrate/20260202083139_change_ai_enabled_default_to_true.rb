class ChangeAiEnabledDefaultToTrue < ActiveRecord::Migration[7.2]
  def up
    # Change the default for new users to true
    change_column_default :users, :ai_enabled, from: false, to: true
    
    # Update all existing users to have AI enabled
    # This is a prime selling point - users shouldn't have to opt-in
    execute <<-SQL
      UPDATE users SET ai_enabled = true WHERE ai_enabled = false
    SQL
  end

  def down
    change_column_default :users, :ai_enabled, from: true, to: false
  end
end
