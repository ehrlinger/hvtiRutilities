# The gate in read_built() refuses a non-interactive session with no job file,
# which is what testthat is. Tests that are not about the gate read as the
# interactive console would; test-working_read.R mocks these bindings itself.
testthat::local_mocked_bindings(.is_interactive = function() TRUE, .knitr_input = function() NULL,
                                .command_args = function() character(),
                                .signal_working_read = function(file) invisible(NULL),
                                .package = "hvtiRutilities", .env = testthat::teardown_env())
# A developer's own HVTI_DATA must not change what the suite reads; tests that
# are about it set it themselves.
withr::local_envvar(HVTI_DATA = NA, .local_envir = testthat::teardown_env())
