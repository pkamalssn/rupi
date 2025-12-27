class AddCategoryFieldsToImportRows < ActiveRecord::Migration[7.1]
  def change
    # Create import_rows table first if it doesn't exist (fix for migration order issue)
    unless table_exists?(:import_rows)
      create_table :import_rows, id: :uuid do |t|
        t.references :import, null: false, foreign_key: true, type: :uuid
        t.string :account
        t.string :date
        t.string :qty
        t.string :ticker
        t.string :price
        t.string :amount
        t.string :currency
        t.string :name
        t.string :category
        t.string :tags
        t.string :entity_type
        t.text :notes

        t.timestamps
      end
    end

    add_column :import_rows, :category_parent, :string
    add_column :import_rows, :category_color, :string
    add_column :import_rows, :category_classification, :string
  end
end
