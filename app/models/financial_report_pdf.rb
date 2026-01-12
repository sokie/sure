class FinancialReportPdf < Prawn::Document
  # Color Palette (Tailwind-ish)
  COLORS = {
    primary: "111827",    # gray-900
    secondary: "6B7280",  # gray-500
    success: "059669",    # emerald-600
    danger: "DC2626",     # red-600
    border: "E5E7EB",     # gray-200
    bg_subtle: "F9FAFB",  # gray-50
    bg_card: "FFFFFF"     # white
  }

  def initialize(period:, start_date:, end_date:, summary_metrics:, trends_data:, net_worth_metrics:, investment_metrics:, transactions_breakdown:)
    super(page_size: "A4", margin: 50, page_layout: :portrait)

    @period = period
    @start_date = start_date
    @end_date = end_date
    @summary_metrics = summary_metrics
    @trends_data = trends_data
    @net_worth_metrics = net_worth_metrics
    @investment_metrics = investment_metrics
    @transactions_breakdown = transactions_breakdown
    @currency = Current.family.currency

    # Set default font
    font "Helvetica"
    default_leading 5

    generate
  end

  def generate
    header
    move_down 30
    summary_dashboard
    move_down 30
    net_worth_section
    move_down 30
    investment_section if @investment_metrics[:has_investments]
    move_down 30
    trends_section
    move_down 30
    transactions_section

    number_pages "<page> / <total>",
      at: [ bounds.right - 50, 0 ],
      align: :right,
      size: 9,
      color: COLORS[:secondary]
  end

  private

    def header
      # Logo / Title Area
      float do
        text "SURE", size: 20, style: :bold, color: COLORS[:primary]
        text "Financial Report", size: 10, color: COLORS[:secondary]
      end

      # Date Range Right Aligned
      bounding_box([ bounds.width - 200, cursor ], width: 200) do
        text "Period", size: 10, color: COLORS[:secondary], align: :right
        text "#{@start_date.strftime('%B %d, %Y')} - #{@end_date.strftime('%B %d, %Y')}",
             size: 12, style: :bold, align: :right, color: COLORS[:primary]
      end

      move_down 10
      stroke_horizontal_rule
      stroke_color COLORS[:border]
    end

    def summary_dashboard
      text "Summary", size: 16, style: :bold, color: COLORS[:primary]
      move_down 15

      # Card layout using bounding boxes
      card_width = (bounds.width - 20) / 3
      y_position = cursor

      # Card 1: Income
      draw_summary_card([ 0, y_position ], card_width, "Total Income", @summary_metrics[:current_income], :success)

      # Card 2: Expenses
      draw_summary_card([ card_width + 10, y_position ], card_width, "Total Expenses", @summary_metrics[:current_expenses], :danger)

      # Card 3: Net Savings
      is_positive = @summary_metrics[:net_savings].positive?
      draw_summary_card([ card_width * 2 + 20, y_position ], card_width, "Net Savings", @summary_metrics[:net_savings], is_positive ? :success : :danger)

      move_down 60 # Space after cards
    end

    def draw_summary_card(at, width, title, money, color_key)
      bounding_box(at, width: width, height: 60) do
        # Background
        fill_color COLORS[:bg_subtle]
        fill_rounded_rectangle [ 0, bounds.height ], bounds.width, bounds.height, 5
        fill_color COLORS[:primary] # Reset

        pad(10) do
          indent(10) do
            text title, size: 9, color: COLORS[:secondary], style: :bold
            move_down 5
            text format_money(money), size: 14, style: :bold, color: COLORS[color_key]
          end
        end
      end
    end

    def net_worth_section
      heading "Net Worth"

      # Hero metric for Net Worth
      text "Current Net Worth", size: 10, color: COLORS[:secondary]
      text format_money(@net_worth_metrics[:current_net_worth]), size: 20, style: :bold, color: COLORS[:primary]

      if @net_worth_metrics[:trend]
        trend = @net_worth_metrics[:trend]
        direction = trend.direction == "up" ? "+" : "-"
        color = trend.direction == "up" ? COLORS[:success] : COLORS[:danger]
        text "#{direction}#{format_money(trend.value)} vs previous period", size: 9, color: color
      end

      move_down 15

      # Assets vs Liabilities Table
      data = [
        [ { content: "Assets", font_style: :bold }, { content: format_money(@net_worth_metrics[:total_assets]), font_style: :bold, align: :right } ],
        [ { content: "Liabilities", font_style: :bold }, { content: format_money(@net_worth_metrics[:total_liabilities]), font_style: :bold, align: :right } ]
      ]

      @net_worth_metrics[:asset_groups].each do |g|
        data.insert(1, [ indent_name(g[:name]), { content: g[:total].format, align: :right } ])
      end

      @net_worth_metrics[:liability_groups].each do |g|
        data.push([ indent_name(g[:name]), { content: g[:total].format, align: :right } ])
      end

      draw_table(data)
    end

    def investment_section
      start_new_page if cursor < 200
      heading "Investment Performance"

      text "Portfolio Value: #{format_money(@investment_metrics[:portfolio_value])}", size: 14, style: :bold
      move_down 15

      if @investment_metrics[:top_holdings].any?
        text "Top Holdings", size: 12, style: :bold, color: COLORS[:primary]
        move_down 5

        header = [ "Name", "Value", "Allocation" ]
        data = @investment_metrics[:top_holdings].map do |h|
          [
            h.name,
            { content: format_money(h.amount_money), align: :right },
            { content: "#{h.weight.round(1)}%", align: :right }
          ]
        end

        draw_table([ header ] + data, header: true)
      end
    end

    def trends_section
      start_new_page if cursor < 300
      heading "Monthly Trends"

      header = [ "Month", "Income", "Expenses", "Net" ]
      data = @trends_data.map do |t|
        [
          t[:month],
          { content: format_money(Money.new(t[:income], @currency)), align: :right, text_color: COLORS[:success] },
          { content: format_money(Money.new(t[:expenses], @currency)), align: :right, text_color: COLORS[:danger] },
          { content: format_money(Money.new(t[:net], @currency)), align: :right }
        ]
      end

      draw_table([ header ] + data, header: true)
    end

    def transactions_section
      start_new_page
      heading "Transactions Breakdown"

      header = [ "Category", "Type", "Count", "Total" ]
      data = @transactions_breakdown.map do |t|
        [
          t[:category_name],
          t[:type].capitalize,
          { content: t[:count].to_s, align: :center },
          { content: format_money(Money.new(t[:total], @currency)), align: :right }
        ]
      end

      draw_table([ header ] + data, header: true)
    end

    # Helpers -----------------------

    def heading(title)
      text title, size: 16, style: :bold, color: COLORS[:primary]
      stroke do
        stroke_color COLORS[:border]
        line [ 0, cursor - 5 ], [ bounds.width, cursor - 5 ]
      end
      move_down 20
    end

    def draw_table(data, header: false)
      table(data, width: bounds.width) do
        cells.padding = [ 8, 12 ]
        cells.borders = [ :bottom ]
        cells.border_width = 1
        cells.border_color = COLORS[:bg_subtle]
        cells.text_color = COLORS[:primary]

        if header
          row(0).font_style = :bold
          row(0).background_color = COLORS[:bg_subtle]
          row(0).border_bottom_color = COLORS[:border]
          row(0).text_color = COLORS[:secondary]
        end
      end
    end

    def indent_name(name)
      Prawn::Text::NBSP * 4 + name
    end

    def format_money(money)
      return "$0.00" if money.nil?
      money.format
    end
end
