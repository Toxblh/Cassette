cassette_test_sources = [
  vapi_sources,
  cassette_client_sources,
  resources
]

test('Test Jsoner',
  executable('jsoner-test',
    sources: ['jsoner-test.vala'] + cassette_test_sources,
    dependencies: cassette_dependencies,
    include_directories: config_h_dir,
    c_args: cassette_c_args,
  )
)

test('Test Client Utils',
  executable('client-utils-test',
    sources: ['client-utils-test.vala'] + cassette_test_sources,
    dependencies: cassette_dependencies,
    include_directories: config_h_dir,
    c_args: cassette_c_args,
  )
)

test('Test Info Database',
  executable('info-db-test',
    sources: ['info-db-test.vala'] + cassette_test_sources,
    dependencies: cassette_dependencies,
    include_directories: config_h_dir,
    c_args: cassette_c_args,
  )
)

test('Test Storager',
  executable('storager-test',
    sources: ['storager-test.vala'] + cassette_test_sources,
    dependencies: cassette_dependencies,
    include_directories: config_h_dir,
    c_args: cassette_c_args,
  )
)


test('Test Glagol',
  executable('glagol-test',
    sources: ['glagol-test.vala'] + cassette_test_sources,
    dependencies: cassette_dependencies,
    include_directories: config_h_dir,
    c_args: cassette_c_args,
  )
)

# Skips unless CASSETTE_GLAGOL_E2E_HOST points at a station on the network.
test('Test Glagol E2E',
  executable('glagol-e2e-test',
    sources: ['glagol-e2e-test.vala'] + cassette_test_sources,
    dependencies: cassette_dependencies,
    include_directories: config_h_dir,
    c_args: cassette_c_args,
  )
)
