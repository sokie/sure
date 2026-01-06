class IncomeStatement::Totals
  def initialize(family, transactions_scope:)
    @family = family
    @transactions_scope = transactions_scope
  end

  def call
    ActiveRecord::Base.connection.select_all(query_sql).map do |row|
      TotalsRow.new(
        parent_category_id: row["parent_category_id"],
        category_id: row["category_id"],
        classification: row["classification"],
        total: row["total"],
        transactions_count: row["transactions_count"]
      )
    end
  end

  private
    TotalsRow = Data.define(:parent_category_id, :category_id, :classification, :total, :transactions_count)

    def query_sql
      ActiveRecord::Base.sanitize_sql_array([
        optimized_query_sql_with_offsets,
        sql_params
      ])
    end

    # OPTIMIZED: Direct SUM aggregation with offset deductions
    # - Expenses are reduced by their confirmed offset amounts
    # - Income transactions that are linked as confirmed offsets are excluded (they reduce expenses, not add to income)
    def optimized_query_sql_with_offsets
      <<~SQL
        WITH base_transactions AS (
          SELECT
            at.id as transaction_id,
            at.category_id,
            ae.id as entry_id,
            ae.amount,
            ae.currency,
            ae.date,
            CASE WHEN ae.amount < 0 THEN 'income' ELSE 'expense' END as classification
          FROM (#{@transactions_scope.to_sql}) at
          JOIN entries ae ON ae.entryable_id = at.id AND ae.entryable_type = 'Transaction'
          -- Exclude transactions that are linked as confirmed offsets (they reduce expenses instead of adding to income)
          LEFT JOIN offsets confirmed_offset ON confirmed_offset.offset_transaction_id = at.id AND confirmed_offset.status = 'confirmed'
          WHERE at.kind NOT IN ('funds_movement', 'one_time', 'cc_payment')
            AND ae.excluded = false
            AND confirmed_offset.id IS NULL
        ),
        offset_deductions AS (
          SELECT
            o.expense_transaction_id,
            SUM(ABS(oe.amount) * COALESCE(er.rate, 1)) as total_offset
          FROM offsets o
          JOIN entries oe ON oe.entryable_id = o.offset_transaction_id AND oe.entryable_type = 'Transaction'
          LEFT JOIN exchange_rates er ON (
            er.date = oe.date AND
            er.from_currency = oe.currency AND
            er.to_currency = :target_currency
          )
          WHERE o.status = 'confirmed'
          GROUP BY o.expense_transaction_id
        )
        SELECT
          c.id as category_id,
          c.parent_id as parent_category_id,
          bt.classification,
          ABS(SUM(
            CASE
              WHEN bt.classification = 'expense' THEN
                (bt.amount * COALESCE(er.rate, 1)) - COALESCE(od.total_offset, 0)
              ELSE
                bt.amount * COALESCE(er.rate, 1)
            END
          )) as total,
          COUNT(bt.entry_id) as transactions_count
        FROM base_transactions bt
        LEFT JOIN categories c ON c.id = bt.category_id
        LEFT JOIN exchange_rates er ON (
          er.date = bt.date AND
          er.from_currency = bt.currency AND
          er.to_currency = :target_currency
        )
        LEFT JOIN offset_deductions od ON od.expense_transaction_id = bt.transaction_id
        GROUP BY c.id, c.parent_id, bt.classification;
      SQL
    end

    def sql_params
      {
        target_currency: @family.currency
      }
    end
end
