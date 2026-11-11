library(rvest)
library(tidyverse)
library(tm)
library(tidytext)
library(textrank)
library(ggplot2)

# Question 3.1 
url <- "https://en.wikipedia.org/wiki/Natural_language_processing"
webpage <- read_html(url)

paragraphs <-webpage %>%
  html_nodes("p") %>%
  html_text()

paragraphs <- paragraphs[paragraphs != "" & nchar(paragraphs) >20]
full_text <- paste(paragraphs, collapse = " " )

web_df <- data.frame(
  file_name = url,
  content = full_text,
  stringsAsFactors = FALSE
)

str(web_df)

# Question 3.2
corpus <- VCorpus(VectorSource(web_df$content))
corpus <- tm_map(corpus, content_transformer(tolower))
corpus <- tm_map(corpus, removePunctuation)
corpus <- tm_map(corpus, removeNumbers)
corpus <- tm_map(corpus, removeWords, stopwords("english"))
corpus <- tm_map(corpus, stripWhitespace)

cleaned_text <- content(corpus[[1]])

print(" Text Preprocessing Complete (First 200 chars)")
print(substr(cleaned_text, 1, 200))

#Question 3.3

para_df <- data_frame(
  doc_id = 1:length(paragraphs),
  text = paragraphs,
  stringsAsFactors = FALSE
)

# Technique 1: TF-IDF Keyword Extraction

para_tokens <- para_df %>%
  unnest_tokens(word, text) %>%
  anti_join(stop_words, by = "word") %>%
  count(doc_id, word, sort = TRUE)

total_words <- para_tokens %>% 
  group_by(doc_id) %>% 
  summarise(total = sum(n), .groups = 'drop')

para_tokens <- left_join(para_tokens, total_words, by = "doc_id")
para_tfidf <- para_tokens %>%
  bind_tf_idf(word, doc_id, n) %>%
  arrange(desc(tf_idf))

print("--- Top TF-IDF Summary Keywords Preview ---")
print(head(para_tfidf, 5))

#Technique 2: TextRank Extractive Sentences
sentence_words <- para_df %>%
  unnest_tokens(word, text) %>%
  anti_join(stop_words, by = "word")

tr_sentences <- textrank_sentences(data = para_df, terminology = sentence_words)
summary_sentences <- summary(tr_sentences, n = 3, sentence_format = "markdown")

print("--- Extractive Summary (Top Sentences via TextRank) ---")
print(summary_sentences)

# Top Keywords Bar Chart (TF-IDF)
top_keywords <- para_tfidf %>%
  group_by(word) %>%
  summarise(mean_tf_idf = mean(tf_idf), .groups = 'drop') %>%
  slice_max(mean_tf_idf, n = 10)

vis_1 <- ggplot(top_keywords, aes(x = reorder(word, mean_tf_idf), y = mean_tf_idf, fill = mean_tf_idf)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(
    title = "Top 10 Keywords by TF-IDF Score",
    subtitle = "WebText API Proof of Concept - Content Analysis",
    x = "Keywords",
    y = "Mean TF-IDF Score"
  ) +
  theme_minimal()

print(vis_1)

# TextRank Sentence Scores Bar Chart ---
top_sent_scores <- head(tr_sentences$sentences, 5) %>%
  mutate(sentence_id = row_number()) 

vis_2 <- ggplot(top_sent_scores, aes(x = reorder(as.factor(sentence_id), textrank), y = textrank, fill = textrank)) +
  geom_col(show.legend = FALSE) +
  coord_flip() +
  labs(
    title = "Top Extractive Sentences by TextRank Score",
    subtitle = "Graph-Based Sentence Importance Ranking",
    x = "Sentence ID",
    y = "TextRank Score"
  ) +
  theme_minimal()

print(vis_2)