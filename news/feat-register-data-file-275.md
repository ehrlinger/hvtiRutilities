* `register_data()` and `declare_data()` name their dataset argument `file =`, which was `built =` (#275).
  `built =` still works, with a warning, and will be removed in a later release; giving both is an error. A
  call that gives the file by position, `register_data(root, "built.csv")`, is unchanged.
