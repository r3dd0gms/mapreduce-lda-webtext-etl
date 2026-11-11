library(rvest)
library(stringr)
library(dplyr)
library(readr)

# Question 4.1
get_page <- function(u) {
  page  <- read_html(u)
  boxes <- page %>% html_nodes(".quote")
  
  data.frame(
    quote_text    = page %>% html_nodes(".quote .text")   %>% html_text(),
    author        = page %>% html_nodes(".quote .author") %>% html_text(),
    tag_count_str = as.character(sapply(boxes, function(b) {
      length(html_nodes(b, ".tags .tag"))
    })),
    stringsAsFactors = FALSE
  )
}

df_raw <- bind_rows(
  get_page("https://quotes.toscrape.com/"),
  get_page("https://quotes.toscrape.com/page/2/")
)

nrow(df_raw)   # should be 20

# Introduce deliberate "dirty" values to demonstrate cleaning
set.seed(42)
df_raw$tag_count_str[c(4, 15)] <- c("approx 3 tags", NA)
df_raw$author[9]               <- ""
df_raw$quote_text[12]          <- NA

head(df_raw, 5)


# Question 4.2
df_clean <- df_raw %>%
  mutate(
    quote_text = ifelse(is.na(quote_text) | quote_text == "",
                        "[Missing Quote Content]", quote_text),
    author     = ifelse(is.na(author) | author == "", "Anonymous", author)
  ) %>%
  mutate(
    extracted_tags = str_extract(tag_count_str, "[0-9]+"),
    numeric_tags   = as.numeric(extracted_tags)
  ) %>%
  mutate(
    word_count = str_count(quote_text, "\\S+")
  )

# Impute missing tag counts with the median (rounded so it fits an INT column)
median_tags <- round(median(df_clean$numeric_tags, na.rm = TRUE))

df_clean <- df_clean %>%
  mutate(numeric_tags = as.integer(coalesce(numeric_tags, median_tags))) %>%
  select(quote_text, author, word_count, numeric_tags)

write_csv(df_clean, "cleaned_quotes_dataset.csv")
print(paste("Dataset cleaned and exported with", nrow(df_clean), "records."))

getwd()   # shows where the CSV was saved