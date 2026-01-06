require "test_helper"

class OffsetTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @category = categories(:food_and_drink)
  end

  test "offset links expense to refund" do
    expense = create_transaction(date: 5.days.ago.to_date, account: accounts(:depository), amount: 100, category: @category)
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50, category: @category)

    offset = Offset.create!(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction,
      status: "confirmed"
    )

    assert offset.persisted?
    assert_equal 50, offset.net_expense_amount.amount
  end

  test "offset requires same category or uncategorized" do
    other_category = Category.create!(name: "Other", family: @family)
    expense = create_transaction(date: Date.current, account: accounts(:depository), amount: 100, category: @category)
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50, category: other_category)

    offset = Offset.new(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction
    )

    assert offset.invalid?
    assert_includes offset.errors.full_messages, "Offset must have the same category as the expense or be uncategorized"
  end

  test "offset allows uncategorized refund" do
    expense = create_transaction(date: Date.current, account: accounts(:depository), amount: 100, category: @category)
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50) # no category

    offset = Offset.new(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction,
      status: "confirmed"
    )

    assert offset.valid?
  end

  test "offset requires expense to be positive and refund to be negative" do
    expense = create_transaction(date: Date.current, account: accounts(:depository), amount: -100, category: @category) # wrong sign
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50, category: @category)

    offset = Offset.new(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction
    )

    assert offset.invalid?
    assert_includes offset.errors.full_messages, "Expense must be positive and offset must be negative"
  end

  test "offset dates must be within 30 days for pending" do
    expense = create_transaction(date: 35.days.ago.to_date, account: accounts(:depository), amount: 100, category: @category)
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50, category: @category)

    offset = Offset.new(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction,
      status: "pending"
    )

    assert offset.invalid?
    assert_includes offset.errors.full_messages, "Must be within 30 days"
  end

  test "offset dates can be within 365 days for confirmed" do
    expense = create_transaction(date: 60.days.ago.to_date, account: accounts(:depository), amount: 100, category: @category)
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50, category: @category)

    offset = Offset.new(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction,
      status: "confirmed"
    )

    assert offset.valid?
  end

  test "offset must be from same family" do
    family2 = families(:empty)
    family2_account = family2.accounts.create!(name: "Family 2 Account", balance: 5000, currency: "USD", accountable: Depository.new)

    expense = create_transaction(date: Date.current, account: accounts(:depository), amount: 100, category: @category)
    refund = create_transaction(date: Date.current, account: family2_account, amount: -50)

    offset = Offset.new(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction
    )

    assert offset.invalid?
    assert_includes offset.errors.full_messages, "Must be from same family"
  end

  test "offset transaction can only be used once" do
    expense1 = create_transaction(date: Date.current, account: accounts(:depository), amount: 100, category: @category)
    expense2 = create_transaction(date: Date.current, account: accounts(:depository), amount: 150, category: @category)
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50, category: @category)

    Offset.create!(
      expense_transaction: expense1.transaction,
      offset_transaction: refund.transaction,
      status: "confirmed"
    )

    offset2 = Offset.new(
      expense_transaction: expense2.transaction,
      offset_transaction: refund.transaction,
      status: "confirmed"
    )

    assert offset2.invalid?
  end

  test "expense can have multiple offsets" do
    expense = create_transaction(date: Date.current, account: accounts(:depository), amount: 100, category: @category)
    refund1 = create_transaction(date: Date.current, account: accounts(:depository), amount: -30, category: @category)
    refund2 = create_transaction(date: Date.current, account: accounts(:depository), amount: -20, category: @category)

    Offset.create!(
      expense_transaction: expense.transaction,
      offset_transaction: refund1.transaction,
      status: "confirmed"
    )

    offset2 = Offset.create!(
      expense_transaction: expense.transaction,
      offset_transaction: refund2.transaction,
      status: "confirmed"
    )

    assert offset2.persisted?
    assert_equal 50, expense.transaction.net_expense_amount.amount
  end

  test "reject creates rejected offset and destroys offset" do
    expense = create_transaction(date: Date.current, account: accounts(:depository), amount: 100, category: @category)
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50, category: @category)

    offset = Offset.create!(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction,
      status: "pending"
    )

    assert_difference -> { Offset.count } => -1, -> { RejectedOffset.count } => 1 do
      offset.reject!
    end
  end

  test "confirm changes status to confirmed" do
    expense = create_transaction(date: Date.current, account: accounts(:depository), amount: 100, category: @category)
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50, category: @category)

    offset = Offset.create!(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction,
      status: "pending"
    )

    offset.confirm!
    assert offset.confirmed?
  end

  test "transaction has_offsets returns true when has confirmed offsets" do
    expense = create_transaction(date: Date.current, account: accounts(:depository), amount: 100, category: @category)
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50, category: @category)

    assert_not expense.transaction.has_offsets?

    Offset.create!(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction,
      status: "confirmed"
    )

    assert expense.transaction.has_offsets?
  end

  test "transaction is_offset returns true when linked as offset" do
    expense = create_transaction(date: Date.current, account: accounts(:depository), amount: 100, category: @category)
    refund = create_transaction(date: Date.current, account: accounts(:depository), amount: -50, category: @category)

    assert_not refund.transaction.is_offset?

    Offset.create!(
      expense_transaction: expense.transaction,
      offset_transaction: refund.transaction,
      status: "confirmed"
    )

    refund.transaction.reload
    assert refund.transaction.is_offset?
  end
end
