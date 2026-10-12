* A `_study.yml` that is not valid YAML now stops with a message that names
  the function, the file, the line and the usual cause, instead of the YAML
  parser's bare "Scanner error" from `yaml.load`. A hand-edited value holding
  `": "`, such as a long study title, reads as a nested mapping unless it is
  quoted; the message says so (#213).
