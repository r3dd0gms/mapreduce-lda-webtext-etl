library(tidyverse)
library(tm)
library(topicmodels)
library(tidytext)
library(ggplot2)
library(wordcloud)
library(RColorBrewer)

# Question 2.1(Data Frame Creation and Preprocessing)
unzip("news.zip", exdir = "extracted_news")
file_paths <- list.files("extracted_news/sa_news",pattern = "\\.txt$", full.names = TRUE)
news_df <- data.frame(
  file_name = basename(file_paths),
  content = sapply(file_paths, function(path){
    readLines(path, warn = FALSE, encoding = "UTF-8") %>% paste(collapse = " ")
  }),
  stringAsFactors = FALSE
)
print("--- Data Frame Preview ---")
print(head(news_df))

corpus <- VCorpus(VectorSource(news_df$content))
corpus <- tm_map(corpus, content_transformer(tolower))
corpus <- tm_map(corpus, removePunctuation)
corpus <- tm_map(corpus, removeNumbers)
corpus <- tm_map(corpus, removeWords, stopwords("english"))
corpus <- tm_map(corpus, stripWhitespace)

dtm <- DocumentTermMatrix(corpus)

row_totals <- apply(dtm, 1, sum)
dtm <- dtm[row_totals >0,]

dtm <- removeSparseTerms(dtm, 0.99)

#  Question 2.2 Latent Dirichet Alooaction (LDA)
n_topics <- 3
k_words <- 5

set.seed(42)
lda_model <- LDA(dtm, k = n_topics, control = list(seed = 42))

topic_word_probs <- tidy(lda_model, matrix = "beta")

top_terms <- topic_word_probs %>%
  group_by(topic) %>%
  slice_max(beta, n = k_words) %>%
  ungroup() %>%
  arrange(topic, -beta)

print(" Top Words and Word distributaion ( Beta) per Topic")
print(top_terms)

doc_topics_probs <- tidy(lda_model , matrix = "gamma")
print("Document Topic Distribuation (Gamma) Preview")
print(head(doc_topics_probs))

#  Question 2.3 - Visualization 
vis_plot_1 <- top_terms %>%
  mutate(term = reorder_within(term, beta, topic)) %>%
  ggplot(aes(x = beta, y = term, fill = factor(topic))) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~ topic, scales = "free") +
  scale_y_reordered() +
  labs(
    title = "Top Keywords in Each Topic (LDA Model)",
    subtitle = "Faceted by Topic with Word Distribution Probabilities (Beta)",
    x = "Word Distribution Probability (Beta)",
    y = "Terms"
  ) +
  theme_minimal()

print(vis_plot_1)
  
  par(mfrow = c(1, n_topics))
  for (i in 1:n_topics) {
    topic_data <- topic_word_probs %>% filter(topic == i)
    wordcloud(
      words = topic_data$term, 
      freq = topic_data$beta, 
      max.words = 20, 
      random.order = FALSE, 
      colors = brewer.pal(8, "Dark2")
    )
    title(main = paste("Topic", i))
  }
  par(mfrow = c(1, 1))
    
