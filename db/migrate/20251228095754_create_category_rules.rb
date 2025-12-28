class CreateCategoryRules < ActiveRecord::Migration[7.2]
  def change
    create_table :category_rules, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :category, null: false, foreign_key: true, type: :uuid
      t.string :pattern, null: false
      t.string :match_type, default: "contains", null: false  # contains, exact, regex
      t.string :source, default: "auto", null: false          # auto, manual, ai
      t.float :confidence, default: 0.9
      t.integer :times_matched, default: 0
      t.string :merchant_name
      t.boolean :active, default: true

      t.timestamps
    end
    
    add_index :category_rules, [:family_id, :pattern], unique: true
    add_index :category_rules, [:family_id, :active]
  end
end
