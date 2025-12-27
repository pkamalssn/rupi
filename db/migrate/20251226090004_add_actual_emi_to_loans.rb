class AddActualEmiToLoans < ActiveRecord::Migration[7.2]
  def change
    add_column :loans, :actual_emi, :decimal
  end
end
