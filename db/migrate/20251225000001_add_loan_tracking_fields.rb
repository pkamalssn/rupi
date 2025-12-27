# frozen_string_literal: true

class AddLoanTrackingFields < ActiveRecord::Migration[7.2]
  def change
    # Add enhanced loan tracking fields
    add_column :loans, :emi_day, :integer, comment: "Day of month when EMI is debited (1-28)"
    add_column :loans, :lender_name, :string, comment: "Bank/NBFC name"
    add_column :loans, :loan_account_number, :string, comment: "Loan account number"
    add_column :loans, :disbursement_date, :date, comment: "When loan was disbursed"

    # Create EMI payments table
    create_table :emi_payments, id: :uuid do |t|
      t.references :loan, null: false, foreign_key: true, type: :uuid
      t.references :entry, null: true, foreign_key: true, type: :uuid, comment: "Linked transaction"
      
      t.date :due_date, null: false
      t.date :paid_date
      
      t.decimal :emi_amount, precision: 15, scale: 2
      t.decimal :principal_component, precision: 15, scale: 2
      t.decimal :interest_component, precision: 15, scale: 2
      
      t.string :status, default: "pending", null: false, comment: "pending, paid, overdue, prepayment"
      t.text :notes

      t.timestamps
    end

    add_index :emi_payments, :due_date
    add_index :emi_payments, :status
    add_index :emi_payments, [:loan_id, :due_date], unique: true
  end
end
