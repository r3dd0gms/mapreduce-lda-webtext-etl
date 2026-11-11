# ITBDA Formative Assessment 2

Big-data analytics project covering four questions: a MapReduce keyword search, topic modelling with LDA, a web-text information-extraction proof of concept, and an ETL pipeline with SQL analysis. All code is in R (plus SQL for PostgreSQL).

| Q | Topic | Notebook | Source |
|---|---|---|---|
| 1 | Keyword location (row, column) with MapReduce on R + Hadoop Streaming | [`Q1_keyword_search_mapreduce.ipynb`](notebooks/Q1_keyword_search_mapreduce.ipynb) | [`src/q1_keyword_search_mapreduce/`](src/q1_keyword_search_mapreduce/) |
| 2 | LDA topic modelling of South African news | [`Q2_topic_modelling_lda.ipynb`](notebooks/Q2_topic_modelling_lda.ipynb) | [`src/q2_topic_modelling_lda.R`](src/q2_topic_modelling_lda.R) |
| 3 | WebText API: TF-IDF keywords and TextRank summary of a Wikipedia article | [`Q3_webtext_api.ipynb`](notebooks/Q3_webtext_api.ipynb) | [`src/q3_webtext_api.R`](src/q3_webtext_api.R) |
| 4 | Web-scraping ETL, then SQL analysis in PostgreSQL | [`Q4_etl_and_sql_analysis.ipynb`](notebooks/Q4_etl_and_sql_analysis.ipynb) | [`src/q4_etl_quotes.R`](src/q4_etl_quotes.R), [`src/q4_webscraping_quotes.sql`](src/q4_webscraping_quotes.sql) |

## Repository structure

```
.
├── README.md
├── docs/
│   ├── Project_Documentation_Q1-Q4.docx    project documentation (Questions 1-4)
│   └── images/                             screenshots from the documentation, shown in the notebooks
├── data/                                   project datasets (see data/README.md)
│   ├── q1_map_reduce_test_docs/  (+ .zip)
│   ├── q2_news/                            put news.zip here
│   └── q4_quotes/cleaned_quotes_dataset.csv
├── notebooks/                              analytics flow for Questions 1-4
│   ├── Q1_keyword_search_mapreduce.ipynb
│   ├── Q2_topic_modelling_lda.ipynb
│   ├── Q3_webtext_api.ipynb
│   └── Q4_etl_and_sql_analysis.ipynb
└── src/                                    original scripts
    ├── q1_keyword_search_mapreduce/        mapper, reducer, Hadoop config, tests, own README
    ├── q2_topic_modelling_lda.R
    ├── q3_webtext_api.R
    ├── q4_etl_quotes.R
    └── q4_webscraping_quotes.sql
```

## Running the notebooks

The notebooks use the R kernel (`IRkernel`). In R:

```r
install.packages(c("IRkernel", "tidyverse", "tm", "topicmodels", "tidytext", "wordcloud",
                   "RColorBrewer", "rvest", "textrank", "stringr", "readr", "dplyr", "DBI", "RPostgres"))
IRkernel::installspec()
```

Then start Jupyter (or VS Code) and open a notebook from `notebooks/`. Paths are relative to that folder. The notebooks are saved without outputs; the recorded results are shown as screenshots from the project documentation.

Q3 and Q4 fetch live web pages (Wikipedia, quotes.toscrape.com), so they need an internet connection. Q4.3 needs a PostgreSQL database; the notebook reproduces both SQL investigations with `dplyr` so it can be followed without one.

## Known gaps

* **Q2 dataset missing.** `news.zip` was not in the folder this repo was built from. Add it to `data/q2_news/` (see the README there).
* **`data/q4_quotes/cleaned_quotes_dataset.csv` looks out of date.** It contains only 10 real quotes followed by 10 truncated `[Missing Quote Conten]` rows, whereas the PostgreSQL screenshot in the documentation shows all 20 quotes with only one missing. Re-run `Q4_etl_and_sql_analysis.ipynb` (cells 4.1 and 4.2) to regenerate it.
* **Notebooks were assembled, not executed**, so their code cells have no outputs yet. Run them once and save before pushing if you want outputs to display on GitHub.
* The notebook versions of Q2 and Q3 fix small bugs in the original scripts (`stringAsFactors` typo, deprecated `data_frame()`); the scripts in `src/` are unchanged.
