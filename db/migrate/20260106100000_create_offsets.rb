class CreateOffsets < ActiveRecord::Migration[7.2]
  def change
    create_table :offsets, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :expense_transaction, type: :uuid, null: false, foreign_key: { to_table: :transactions, on_delete: :cascade }
      t.references :offset_transaction, type: :uuid, null: false, foreign_key: { to_table: :transactions, on_delete: :cascade }
      t.string :status, null: false, default: "pending"
      t.text :notes

      t.timestamps
    end

    add_index :offsets, [ :expense_transaction_id, :offset_transaction_id ], unique: true, name: "idx_offsets_expense_offset_unique"
    add_index :offsets, :status
  end
end
