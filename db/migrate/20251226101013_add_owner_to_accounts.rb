class AddOwnerToAccounts < ActiveRecord::Migration[7.2]
  def change
    # Add owner_id column - nullable for "shared" accounts
    add_reference :accounts, :owner, null: true, foreign_key: { to_table: :users }, type: :uuid, index: true
  end
end
