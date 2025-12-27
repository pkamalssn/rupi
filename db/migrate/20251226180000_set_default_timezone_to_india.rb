class SetDefaultTimezoneToIndia < ActiveRecord::Migration[7.2]
  def up
    # Set default timezone to Asia/Kolkata (IST) for India-centric experience
    change_column_default :families, :timezone, "Asia/Kolkata"
    
    # Update existing families that have NULL timezone to IST
    execute <<~SQL
      UPDATE families 
      SET timezone = 'Asia/Kolkata' 
      WHERE timezone IS NULL
    SQL
  end

  def down
    change_column_default :families, :timezone, nil
  end
end
