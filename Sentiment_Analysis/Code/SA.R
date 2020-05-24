
library(dplyr)
library(readr)
library(lubridate)
library(ggplot2)
library(tidytext)
library(tidyverse)
library(stringr)
library(tidyr)
library(textdata)
library(scales)
library(broom)
library(purrr)
library(widyr)
library(igraph)
library(ggraph)
library(SnowballC)
library(wordcloud)
library(reshape2)

theme_set(theme_bw())
Sys.setlocale("LC_TIME", "C")

df <- read_csv("All.csv")

## The Data

df <- df[complete.cases(df), ]
df$review_date <- as.Date(df$review_date, format = "%d-%B-%Y")


dim(df); min(df$review_date); max(df$review_date)

df %>%
  count(Week = round_date(review_date, "week")) %>%
  ggplot(aes(Week, n)) +
  geom_line() +
  ggtitle('The Number of Reviews Per Week')

### Text Mining of the review text


df <- tibble::rowid_to_column(df, "ID2")
df <- df %>%
  mutate(review_date = as.POSIXct(review_date, origin = "1970-01-01"),month = round_date(review_date, "month"))
review_words <- df %>%
  distinct(review_body, .keep_all = TRUE) %>%
  unnest_tokens(word, review_body, drop = FALSE) %>%
  distinct(`Username`, word, .keep_all = TRUE) %>%
  anti_join(stop_words, by = "word") %>%
  filter(str_detect(word, "[^\\d]")) %>%
  group_by(word) %>%
  mutate(word_total = n()) %>%
  ungroup()
word_counts <- review_words %>%
  count(word, sort = TRUE)

word_counts %>%
  head(25) %>%
  mutate(word = reorder(word, n)) %>%
  ggplot(aes(word, n)) +
  geom_col(fill = "lightblue") +
  scale_y_continuous(labels = comma_format()) +
  coord_flip() +
  labs(title = "Most common words in review text 2002 to date",
       subtitle = "Among 13,701 reviews; stop words removed",
       y = "# of uses")


word_counts %>%
  head(25) %>%
  mutate(word = wordStem(word)) %>%
  mutate(word = reorder(word, n)) %>%
  ggplot(aes(word, n)) +
  geom_col(fill = "lightblue") +
  scale_y_continuous(labels = comma_format()) +
  coord_flip() +
  labs(title = "Most common words in review text 2002 to date",
       subtitle = "Among 13,701 reviews; stop words removed and stemmed",
       y = "# of uses")


### Bigrams

review_bigrams <- df %>%
  unnest_tokens(bigram, review_body, token = "ngrams", n = 2)
bigrams_separated <- review_bigrams %>%
  separate(bigram, c("word1", "word2"), sep = " ")
bigrams_filtered <- bigrams_separated %>%
  filter(!word1 %in% stop_words$word) %>%
  filter(!word2 %in% stop_words$word)
bigram_counts <- bigrams_filtered %>%
  count(word1, word2, sort = TRUE)
bigrams_united <- bigrams_filtered %>%
  unite(bigram, word1, word2, sep = " ")
bigrams_united %>%
  count(bigram, sort = TRUE)

review_subject <- df %>%
  unnest_tokens(word, review_body) %>%
  anti_join(stop_words)
my_stopwords <- data_frame(word = c(as.character(1:10)))
review_subject <- review_subject %>%
  anti_join(my_stopwords)
title_word_pairs <- review_subject %>%
  pairwise_count(word, ID, sort = TRUE, upper = FALSE)
set.seed(1234)
title_word_pairs %>%
  filter(n >= 700) %>%
  graph_from_data_frame() %>%
  ggraph(layout = "fr") +
  geom_edge_link(aes(edge_alpha = n, edge_width = n), edge_colour = "cyan4") +
  geom_node_point(size = 3) +
  geom_node_text(aes(label = name), repel = TRUE,
                 point.padding = unit(0.2, "lines")) +
  ggtitle('Word network in TripAdvisor reviews of HongKong, GuangZhou and Macau')
  theme_void()

### Trigrams

review_trigrams <- df %>%
  unnest_tokens(trigram, review_body, token = "ngrams", n = 4)
trigrams_separated <- review_trigrams %>%
  separate(trigram, c("word1", "word2", "word3"), sep = " ")
trigrams_filtered <- trigrams_separated %>%
  filter(!word1 %in% stop_words$word) %>%
  filter(!word2 %in% stop_words$word) %>%
  filter(!word3 %in% stop_words$word)
trigram_counts <- trigrams_filtered %>%
  count(word1, word2, word3, sort = TRUE)
trigrams_united <- trigrams_filtered %>%
  unite(trigram, word1, word2, word3, sep = " ")
trigrams_united %>%
  count(trigram, sort = TRUE)

### Important words trending in reviews.

reviews_per_month <- df %>%
  group_by(month) %>%
  summarize(month_total = n())
word_month_counts <- review_words %>%
  filter(word_total >= 200) %>%
  filter(!word %in% c("it's",'bao','xiao','la','tin','macau'))%>%
  count(word, month) %>%
  complete(word, month, fill = list(n = 0)) %>%
  inner_join(reviews_per_month, by = "month") %>%
  mutate(percent = n / month_total) %>%
  mutate(year = year(month) + yday(month) / 365)

mod <- ~ glm(cbind(n, month_total - n) ~ year, ., family = "binomial")

slopes <- word_month_counts %>%
  nest(-word) %>%
  mutate(model= map(df, mod)) %>%
  unnest(map(model, tidy)) %>%
  filter(term == "year") %>%
  arrange(desc(estimate))

slopes %>%
  head(14) %>%
  inner_join(word_month_counts, by = "word") %>%
  mutate(word = reorder(word, -estimate)) %>%
  ggplot(aes(month, n / month_total, color = word)) +
  geom_line(show.legend = FALSE) +
  scale_y_continuous(labels = percent_format()) +
  facet_wrap(~ word, scales = "free_y") +
  expand_limits(y = 0) +
  labs(x = "Year",
       y = "Percentage of reviews containing this word",
       title = "9 fastest growing words in TripAdvisor reviews",
       subtitle = "Judged by growth rate over 15 years")

slopes %>%
  tail(9) %>%
  inner_join(word_month_counts, by = "word") %>%
  mutate(word = reorder(word, estimate)) %>%
  ggplot(aes(month, n / month_total, color = word)) +
  geom_line(show.legend = FALSE) +
  scale_y_continuous(labels = percent_format()) +
  facet_wrap(~ word, scales = "free_y") +
  expand_limits(y = 0) +
  labs(x = "Year",
       y = "Percentage of reviews containing this term",
       title = "9 fastest shrinking words in TripAdvisor reviews",
       subtitle = "Judged by growth rate over 15 years")

word_month_counts %>%
  filter(word %in% c("price", "food")) %>%
  ggplot(aes(month, n / month_total, color = word)) +
  geom_line(size = 1, alpha = .8) +
  scale_y_continuous(labels = percent_format()) +
  expand_limits(y = 0) +
  labs(x = "Year",
       y = "Percentage of reviews containing this term", title = "price vs food in terms of reviewers interest")
reviews <- df %>%
  filter(!is.na(review_body)) %>%
  select(ID, review_body) %>%
  group_by(row_number()) %>%
  ungroup()
reviews <- df %>%
  filter(!is.na(review_body)) %>%
  select(ID, review_body) %>%
  group_by(row_number()) %>%
  ungroup()

tidy_reviews <- reviews %>%
  unnest_tokens(word, review_body)
tidy_reviews <- tidy_reviews %>%
  anti_join(stop_words)
bing_word_counts <- tidy_reviews %>%
  inner_join(get_sentiments("bing")) %>%
  count(word, sentiment, sort = TRUE) %>%
  ungroup()
bing_word_counts %>%
  group_by(sentiment) %>%
  top_n(10) %>%
  ungroup() %>%
  mutate(word = reorder(word, n)) %>%
  ggplot(aes(word, n, fill = sentiment)) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~sentiment, scales = "free") +
  labs(y = "Contribution to sentiment", x = NULL) +
  coord_flip() +
  ggtitle('Words that contribute to positive and negative sentiment in the reviews')

contributions <- tidy_reviews %>%
  inner_join(get_sentiments("afinn"), by = "word") %>%
  group_by(word) %>%
  summarize(occurences = n(),
            value = sum(value))

contributions %>%
  top_n(20, abs(value)) %>%
  mutate(word = reorder(word, value)) %>%
  ggplot(aes(word, value, fill = value > 0)) +
  ggtitle('Words with the greatest contributions to positive/negative sentiment in reviews') +
  theme(plot.title = element_text(hjust = 0.5))+
  geom_col(show.legend = FALSE) +
  coord_flip()

p_w<-AFINN[AFINN$value >= 0, c("word")]
n_w<-AFINN[AFINN$value >= 0, c("word")]

res<-trigrams_separated %>%
  filter(word1%in%c("location"))%>%
  ##filter(!word2 %in% stop_words$word)%>%
  count(word1, word2, word3,sort = TRUE)

a<-bigrams_separated %>%
  filter(word1 ==c("location"))%>%
  count(word1, word2,sort = TRUE)


negation_words <- c("not", "no", "never", "without")
AFINN <- get_sentiments("afinn")
negated_words <- bigrams_separated %>%
  filter(word1 %in% negation_words) %>%
  inner_join(AFINN, by = c(word2 = "word")) %>%
  count(word1, word2, value, sort = TRUE) %>%
  ungroup()

negated_words %>%
  mutate(contribution = n * value,
         word2 = reorder(paste(word2, word1, sep = "__"), contribution)) %>%
  group_by(word1) %>%
  top_n(12, abs(contribution)) %>%
  ggplot(aes(word2, contribution, fill = n * value > 0)) +
  geom_col(show.legend = FALSE) +
  facet_wrap(~ word1, scales = "free") +
  scale_x_discrete(labels = function(x) gsub("__.+$", "", x)) +
  xlab("Words preceded by negation term") +
  ylab("Sentiment score * # of occurrences") +
  ggtitle('The most common positive or negative words to follow negations
          such as "no", "not", "never" and "without"') +
  theme(plot.title = element_text(hjust = 0.5))+
  coord_flip()

sentiment_messages <- tidy_reviews %>%
  inner_join(get_sentiments("afinn"), by = "word") %>%
  group_by(ID) %>%
  summarize(sentiment = mean(value),
            words = n()) %>%
  ungroup() %>%
  filter(words >= 5)
sentiment_messages %>%
  arrange(desc(sentiment))