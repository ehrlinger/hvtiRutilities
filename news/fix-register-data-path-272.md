* `register_data()` accepts a path into the study's data folder for `built`,
  such as `"00_datasets/built.csv"` or an absolute path, and records the file
  name alone. File-name completion inside the quotes gives that path, so it can
  now be used. A file in any other folder is still refused, and the message
  names the data folder (#272).
