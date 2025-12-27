# frozen_string_literal: true

# Migration to add bank statement import fields
class AddBankStatementFieldsToImports < ActiveRecord::Migration[7.2]
  def change
    add_column :imports, :bank_name, :string
    add_column :imports, :account_number, :string

    # Add index for bank_name for faster lookups
    add_index :imports, :bank_name
  end
end
