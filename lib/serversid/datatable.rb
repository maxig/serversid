class Datatable

  attr_reader :columns, :model_name, :searchable_columns

  def initialize(view)
    @view = view
  end

  def method_missing(meth, *args, &block)
    @view.send(meth, *args, &block)
  end

  def as_json(options = {})
    response = {
      sEcho: params[:sEcho].to_i,
      aaData: data,
      iTotalRecords: @model_name.count,
      iTotalDisplayRecords: get_raw_record_count,
      # aoColumnDefs: [
      #   { bSortable: false, aTargets: [ 0, 1 ] }
      # ],
    }
    if respond_to? :get_custom_table_message
      response[:oLanguage] = { sZeroRecords: get_custom_table_message}
    end

    response
  end

private

  def get_raw_record_count
    begin
      filter_records(search_records(get_raw_records)).count(distinct: true)
    rescue
      0
    end
  end

  def normalize(*columns)
    columns.to_a.first.each do |data_array|
      data_array.map! { |column| column.to_s }
    end
  end

  def fetch_records
    filter_records(search_records(sort_records(paginate_records(get_raw_records))))
  end

  def fetch_records_without_pagination
    filter_records(search_records(sort_records(get_raw_records)))
  end

  def paginate_records(records)
    records.offset((page - 1) * per_page).limit(per_page)
  end

  def sort_records(records)
    params[:iSortingCols].to_i.times do |ordinal_number|
      attribute_number = params["iSortCol_#{ordinal_number}"]
      column = get_column attribute_number
      if need_to_use_association column
        records = sort_by_associations_in records, get_column(attribute_number, false), ordinal_number
      else
        records = records.order "#{@model_name.table_name}.#{column} #{sort_direction ordinal_number}"
      end
    end

    records
  end

  def search_records(records)
    if params[:sSearch].present?
      query = @searchable_columns.map do |column|
        "#{column} LIKE :search"
      end.join(" OR ")
      records = records.where(query, search: "%#{params[:sSearch]}%")
    end

    records
  end

  def filter_records(records)
    # Filtering for default column's filters in table header
    params[:iFilteringCols].to_i.times do |ordinal_number|
      attribute_number = params["iFilterCol_#{ordinal_number}"]
      column = get_column attribute_number
      value = filter_value ordinal_number
      if _filtered = try_custom_filter(get_column(attribute_number, false), records, value)
        records = _filtered
      elsif need_to_use_association column
        records = filter_by_associations_in records, get_column(attribute_number, false), value
      else
        records = records.where "#{column} = :filter", filter: value
      end
    end

    # Filtering for select outside the table header and/or table
    params[:iFilteringMenus].to_i.times do |ordinal_number|
      attribute = params["iFilterMenu_#{ordinal_number}"]
      column = attribute.split(".")[0]
      value = params["sFilterMenu_#{ordinal_number}"]
      if _filtered = try_custom_filter(attribute, records, value)
        records = _filtered
      elsif need_to_use_association column
        records = filter_by_associations_in records, attribute, value
      else
        records = records.where "#{column} = :filter", filter: value
      end
    end

    records
  end

  def page
    params[:iDisplayStart].to_i/per_page + 1
  end

  def per_page
    params[:iDisplayLength].to_i > 0 ? params[:iDisplayLength].to_i : 10
  end

  # Method helps find out which column (model attribute) need to use
  # ordinal_number - ordinal column number (get from client)
  # split (optional) - option used when need to sort by assosiation (need to be false),
  #                    return processing association name by default
  def get_column(ordinal_number, split = true)
    column = @columns[ordinal_number.to_i]
    if split
      column = column.split "."
      column[0]
    else
      column
    end
  end

  def sort_direction(index)
    params["sSortDir_#{index}"] == "desc" ? "DESC" : "ASC"
  end

  def filter_value(ordinal_number)
    params["sFilterCol_#{ordinal_number}"]
  end

  def need_to_use_association(column_name)
    @model_name.reflect_on_all_associations.map { |mac| mac.name.to_s }.include? column_name
  end

  def sort_by_associations_in(records, column, ordinal_number)
    column_name, attribute = column.split "."
    reflection = @model_name.reflect_on_all_associations.map { |mac| mac if mac.name.to_s == column_name }.compact.first

    records.joins(column_name.to_sym).order "#{reflection.table_name}.#{attribute} #{sort_direction ordinal_number}"
  end

  def filter_by_associations_in(records, column, value)
    column_name, attribute = column.split "."
    reflection = @model_name.reflect_on_all_associations.map { |mac| mac if mac.name.to_s == column_name }.compact.first

    records.joins(column_name.to_sym).where "#{reflection.table_name}.#{attribute} = '#{value}'"
  end

  # Add custom filter or scope for selected column
  # Search methods in datatables class or model class
  # To register custom filter simply use register_filter method
  # and passed them column or column and value divided by space when filter must be applied
  # e.g. register_filter 'category', :category
  #      register_filter 'category.name food', :food
  # NB Expected that method without defined value receive current filtered value.

  def self.register_filter(column, method_name)
    @@custom_filters ||= {}
    @@custom_filters[column] = method_name
  end

  def responsed_for_method(method)
    if respond_to? method
      self
    elsif @model_name.respond_to? method
      @model_name
    else
      raise NoMethodError
    end
  end

  def try_custom_filter(column, records, value_for_filter)
    @@custom_filters ||= {}
    with_value = nil

    if method_name = @@custom_filters.fetch(column, nil)
      with_value = true
    elsif method_name = @@custom_filters.fetch("#{column} #{value_for_filter}", nil)
      with_value = false
    end

    if with_value != nil
      value = with_value ? value_for_filter : nil
      if responsed_for_method(method_name) == self
        self.send method_name, records, column, value
      else
        records.send method_name, value
      end
    else
      false
    end

  end

end