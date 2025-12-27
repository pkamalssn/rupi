# frozen_string_literal: true

class CreateLoanDocumentImports < ActiveRecord::Migration[7.2]
  def change
    create_table :loan_document_imports, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, null: true, foreign_key: true, type: :uuid
      
      t.string :status, null: false, default: "pending"
      t.jsonb :extracted_data, default: {}
      t.text :error
      
      # User-edited values (after reviewing AI extraction)
      t.string :lender_name
      t.string :loan_type
      t.decimal :principal_amount, precision: 19, scale: 4
      t.string :currency, default: "INR"
      t.decimal :interest_rate, precision: 10, scale: 4
      t.string :rate_type
      t.integer :tenure_months
      t.decimal :emi_amount, precision: 19, scale: 4
      t.integer :emi_day
      t.date :disbursement_date
      t.string :loan_account_number
      t.decimal :outstanding_balance, precision: 19, scale: 4
      t.date :maturity_date
      t.decimal :processing_fee, precision: 19, scale: 4
      t.string :prepayment_charges
      t.float :confidence
      t.text :notes
      
      t.timestamps
    end

    add_index :loan_document_imports, :status
  end
end
