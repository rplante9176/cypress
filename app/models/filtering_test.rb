class FilteringTest < ProductTest
  field :options, type: Hash
  accepts_nested_attributes_for :tasks

  def pick_filter_criteria
    return unless options && options['filters']
    # select a random patient
    rand_record = records.sample
    # iterate over the filters and assign random codes
    options['filters'].each do |k, v|
      next if v.count > 0
      case k
      when 'races'
        v << rand_record.race['code']
      when 'ethnicities'
        v << rand_record.ethnicity['code']
      when 'genders'
        v << rand_record.gender
      when 'payers'
        v << rand_record.insurance_providers.first.name
      when 'providers'
        v << lookup_provider(rand_record)
      when 'problems'
        v << lookup_problem
      end
    end
    save!
  end

  def lookup_provider(record)
    provider = Provider.find(record.provider_performances.first['provider_id'])
    address = provider.addresses.first
    address_hash = { 'street' => address.street, 'city' => address.city, 'state' => address.state, 'zip' => address.zip,
                     'country' => address.country }
    { 'npi' => provider.npi, 'tin' => provider.tin, 'address' => address_hash }
  end

  def lookup_problem
    measure = Measure.find_by(hqmf_id: measure_ids.first)
    criteria_keys = measure.hqmf_document.source_data_criteria.keys
    # determine which data criteira is the diagnosis
    diagnosis_criteria_key = criteria_keys.find { |key| measure.hqmf_document.source_data_criteria.send(key).definition.eql? 'diagnosis' }
    measure.hqmf_document.source_data_criteria.send(diagnosis_criteria_key).code_list_id
  end

  # Final Rule defines 9 different criteria that can be filtered:
  #
  # (A) TIN .................... (F) Age
  # (B) NPI .................... (G) Sex
  # (C) Provider Type .......... (H) Race + Ethnicity
  # (D) Practice Site Address .. (I) Problem
  # (E) Patient Insurance
  #
  def patient_cache_filter
    input_filters = (options['filters'] || {}).dup
    filters = {}
    # QME can handle races, ethnicities, genders, providers, and patient_ids (and languages)
    # so pass these through directly

    filters['races'] = input_filters.delete 'races' if input_filters['races']
    filters['ethnicities'] = input_filters.delete 'ethnicities' if input_filters['ethnicities']
    filters['genders'] = input_filters.delete 'genders' if input_filters['genders']

    if input_filters['providers']
      providers = Cypress::ProviderFilter.filter(Provider.all, input_filters['providers'], options)
      filters['providers'] = providers.pluck(:_id)
      input_filters.delete 'providers'
    end

    # for the rest, manually filter to get the record IDs and pass those in
    if input_filters.count > 0
      filters['patients'] = Cypress::RecordFilter.filter(records, input_filters, effective_date: effective_date).pluck(:_id)
    end

    filters
  end

  def filtered_records
    Cypress::RecordFilter.filter(records, input_filters, effective_date: effective_date)
  end
end
