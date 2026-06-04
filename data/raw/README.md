# data/raw/

Read-only source extracts (SINAN notifications, SIM mortality, IBGE state
population, GeneXpert share-among-notified, and any external SIM-coverage
series). Git ignored.

Do not edit files here by hand and do not commit them. Scripts in
`code/02_data_processing/` read from here and write to `data/interim/` and
`data/processed/`. Record provenance (source, extract date, query) in
`data/README.md` when files are added.
