* `study_setup()` cleanup now also deletes `config.fixtemplate`, the legacy
  `fixtemplates` step's config, anywhere in the study. Like `tp.*` files and
  `binder.summaries.doc` it goes by name, so a study-edited copy is deleted too.
