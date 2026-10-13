# The gate in read_built() refuses a non-interactive session with no job file,
# which is what testthat is. Tests that are not about the gate read as the
# interactive console would; test-working_read.R mocks these bindings itself.
testthat::local_mocked_bindings(.is_interactive = function() TRUE, .knitr_input = function() NULL,
                                .command_args = function() character(),
                                .package = "hvtiRutilities", .env = testthat::teardown_env())
